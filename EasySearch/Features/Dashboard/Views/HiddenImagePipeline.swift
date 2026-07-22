import Foundation
import ImageIO
import UIKit

final class HiddenImagePipeline {
    static let shared = HiddenImagePipeline()

    private let lock = NSLock()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [NSURL: Task<UIImage, Error>] = [:]
    private let maxDecodedPixelDimension: CGFloat = 3_200

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL) async throws -> UIImage {
        let candidates = HiddenSpaceAPI.imageURLCandidates(for: url)
        let keyURL = candidates.first ?? HiddenSpaceAPI.normalizeImageURL(url)
        let key = keyURL as NSURL
        let decoderMaxPixelDimension = maxDecodedPixelDimension

        if let cached = cache.object(forKey: key) {
            return cached
        }
        // Also hit cache if a later candidate was previously stored under its own key.
        for candidate in candidates {
            if let cached = cache.object(forKey: candidate as NSURL) {
                cache.setObject(cached, forKey: key, cost: cached.hiddenCacheCost)
                return cached
            }
        }

        let task = task(
            for: key,
            candidates: candidates,
            maxPixelDimension: decoderMaxPixelDimension
        )

        do {
            let image = try await task.value
            cache.setObject(image, forKey: key, cost: image.hiddenCacheCost)
            removeInFlightTask(for: key)
            return image
        } catch {
            removeInFlightTask(for: key)
            throw error
        }
    }

    func cachedImage(for url: URL) -> UIImage? {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        return cache.object(forKey: normalizedURL as NSURL)
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            Task {
                _ = try? await image(for: url)
            }
        }
    }

    func cachedAspectRatio(for url: URL) -> CGFloat? {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        guard let image = cache.object(forKey: normalizedURL as NSURL) else {
            return nil
        }
        return image.hiddenAspectRatio
    }

    private func removeInFlightTask(for key: NSURL) {
        lock.lock()
        inFlightTasks[key] = nil
        lock.unlock()
    }

    private func task(
        for key: NSURL,
        candidates: [URL],
        maxPixelDimension: CGFloat
    ) -> Task<UIImage, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let existingTask = inFlightTasks[key] {
            return existingTask
        }

        let task = Self.makeImageTask(
            candidates: candidates,
            maxPixelDimension: maxPixelDimension
        )
        inFlightTasks[key] = task
        return task
    }

    private static func makeImageTask(
        candidates: [URL],
        maxPixelDimension: CGFloat
    ) -> Task<UIImage, Error> {
        Task.detached(priority: .utility) {
            var lastError: Error?

            for candidate in candidates {
                do {
                    let image = try await fetchImage(from: candidate, maxPixelDimension: maxPixelDimension)
                    return image
                } catch {
                    lastError = error
                }
            }

            throw mapImageError(lastError)
        }
    }

    private static func fetchImage(from url: URL, maxPixelDimension: CGFloat) async throws -> UIImage {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "HiddenImagePipeline",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: "图片加载失败 (\(code))"]
            )
        }

        return try decodedImage(from: data, maxPixelDimension: maxPixelDimension)
    }

    private static func mapImageError(_ error: Error?) -> Error {
        guard let error else {
            return NSError(
                domain: "HiddenImagePipeline",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "图片加载失败"]
            )
        }

        let nsError = error as NSError
        if nsError.domain == "HiddenImagePipeline" {
            return nsError
        }
        if nsError.domain == NSURLErrorDomain,
           [NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired].contains(nsError.code) {
            return NSError(
                domain: "HiddenImagePipeline",
                code: nsError.code,
                userInfo: [NSLocalizedDescriptionKey: "TLS 错误：图片 CDN 域名可能已切换"]
            )
        }
        return nsError
    }

    private static func decodedImage(from data: Data, maxPixelDimension: CGFloat) throws -> UIImage {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw decodeError()
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(maxPixelDimension)
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(maxPixelDimension)
        let sourceMaxPixel = max(pixelWidth, pixelHeight, 1)
        let thumbnailMaxPixel = Int(min(sourceMaxPixel, Double(maxPixelDimension)))

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixel
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            throw decodeError()
        }

        return UIImage(cgImage: cgImage)
    }

    private static func decodeError() -> NSError {
        NSError(
            domain: "HiddenImagePipeline",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "图片解码失败"]
        )
    }
}

extension UIImage {
    var hiddenAspectRatio: CGFloat {
        max(size.width / max(size.height, 1), 0.35)
    }

    var hiddenCacheCost: Int {
        let pixelCount = Int(size.width * scale * size.height * scale)
        return max(pixelCount * 4, 1)
    }
}

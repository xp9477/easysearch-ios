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
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        let key = normalizedURL as NSURL
        let decoderMaxPixelDimension = maxDecodedPixelDimension

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let task = task(
            for: key,
            normalizedURL: normalizedURL,
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
        normalizedURL: URL,
        maxPixelDimension: CGFloat
    ) -> Task<UIImage, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let existingTask = inFlightTasks[key] {
            return existingTask
        }

        let task = Self.makeImageTask(
            normalizedURL: normalizedURL,
            maxPixelDimension: maxPixelDimension
        )
        inFlightTasks[key] = task
        return task
    }

    private static func makeImageTask(
        normalizedURL: URL,
        maxPixelDimension: CGFloat
    ) -> Task<UIImage, Error> {
        Task.detached(priority: .utility) {
            var request = URLRequest(url: normalizedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            request.setValue("image/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(
                    domain: "HiddenImagePipeline",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "图片加载失败"]
                )
            }

            return try decodedImage(from: data, maxPixelDimension: maxPixelDimension)
        }
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

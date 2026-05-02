import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

@MainActor
final class HiddenImagePipeline {
    static let shared = HiddenImagePipeline()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [NSURL: Task<UIImage, Error>] = [:]

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL) async throws -> UIImage {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        let key = normalizedURL as NSURL

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existingTask = inFlightTasks[key] {
            return try await existingTask.value
        }

        let task = Task<UIImage, Error> {
            var request = URLRequest(url: normalizedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            request.setValue("image/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                throw NSError(
                    domain: "HiddenImagePipeline",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "图片加载失败"]
                )
            }

            return image
        }

        inFlightTasks[key] = task

        do {
            let image = try await task.value
            cache.setObject(image, forKey: key, cost: image.hiddenCacheCost)
            inFlightTasks[key] = nil
            return image
        } catch {
            inFlightTasks[key] = nil
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

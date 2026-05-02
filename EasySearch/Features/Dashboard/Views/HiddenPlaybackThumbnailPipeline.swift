import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

actor HiddenPlaybackThumbnailPipeline {
    static let shared = HiddenPlaybackThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage, Error>] = [:]
    private var seekThumbnailConfigCache: [String: HiddenJavDBSeekThumbnailConfiguration] = [:]
    private var inFlightSeekThumbnailConfigs: [String: Task<HiddenJavDBSeekThumbnailConfiguration?, Never>] = [:]

    init() {
        cache.countLimit = 36
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for playback: HiddenJavDBFavoritePlayback) async throws -> UIImage {
        let key = cacheKey(for: playback)
        let nsKey = key as NSString

        if let cachedImage = cache.object(forKey: nsKey) {
            return cachedImage
        }

        if let existingTask = inFlightTasks[key] {
            return try await existingTask.value
        }

        let task = Task(priority: .utility) {
            let seekThumbnailConfiguration = await self.seekThumbnailConfiguration(for: playback)
            return try await Self.generateThumbnail(
                for: playback,
                seekThumbnailConfiguration: seekThumbnailConfiguration
            )
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }

        let image = try await task.value
        let cost = Self.imageCost(for: image)
        cache.setObject(image, forKey: nsKey, cost: cost)
        return image
    }

    private func seekThumbnailConfiguration(
        for playback: HiddenJavDBFavoritePlayback
    ) async -> HiddenJavDBSeekThumbnailConfiguration? {
        let key = "\(playback.movie.id)|\(playback.sourceName)"
        if let cachedConfiguration = seekThumbnailConfigCache[key] {
            return cachedConfiguration
        }

        if let existingTask = inFlightSeekThumbnailConfigs[key] {
            return await existingTask.value
        }

        let task = Task(priority: .utility) {
            await HiddenJavDBAPI.resolveSeekThumbnailConfig(for: playback)
        }
        inFlightSeekThumbnailConfigs[key] = task
        defer { inFlightSeekThumbnailConfigs[key] = nil }

        let configuration = await task.value
        if let configuration {
            seekThumbnailConfigCache[key] = configuration
        }
        return configuration
    }

    private func cacheKey(for playback: HiddenJavDBFavoritePlayback) -> String {
        let normalizedTime = Int(playback.positionSeconds.rounded(.toNearestOrAwayFromZero))
        return "\(playback.movie.id)|\(playback.sourceName)|\(normalizedTime)"
    }

    private static func generateThumbnail(
        for playback: HiddenJavDBFavoritePlayback,
        seekThumbnailConfiguration: HiddenJavDBSeekThumbnailConfiguration?
    ) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            if let seekThumbnailConfiguration {
                return try await generateThumbnailFromSeekSprite(
                    for: playback,
                    configuration: seekThumbnailConfiguration
                )
            }

            throw NSError(
                domain: "HiddenPlaybackThumbnailPipeline",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未取到可用预览帧"]
            )
        }.value
    }

    private static func generateThumbnailFromSeekSprite(
        for playback: HiddenJavDBFavoritePlayback,
        configuration: HiddenJavDBSeekThumbnailConfiguration
    ) async throws -> UIImage {
        guard configuration.durationSeconds.isFinite,
              configuration.durationSeconds > 0,
              configuration.picNum > 0,
              configuration.width > 0,
              configuration.height > 0,
              configuration.col > 0,
              configuration.row > 0,
              !configuration.urls.isEmpty else {
            throw NSError(
                domain: "HiddenPlaybackThumbnailPipeline",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "seek 缩略图配置无效"]
            )
        }

        let frameCapacityPerSprite = configuration.col * configuration.row
        let totalFrames = max(1, min(configuration.picNum, configuration.urls.count * frameCapacityPerSprite))
        let clampedPosition = min(max(0, playback.positionSeconds), configuration.durationSeconds)
        let progress = configuration.durationSeconds > 0 ? clampedPosition / configuration.durationSeconds : 0
        let frameIndex = min(
            max(Int((progress * Double(totalFrames - 1)).rounded(.down)), 0),
            totalFrames - 1
        )

        let spriteIndex = min(frameIndex / frameCapacityPerSprite, configuration.urls.count - 1)
        let cellIndex = frameIndex % frameCapacityPerSprite
        let rowIndex = cellIndex / configuration.col
        let columnIndex = cellIndex % configuration.col

        let imageData = try await HiddenJavDBAPI.fetchBinaryData(
            from: configuration.urls[spriteIndex],
            refererURL: configuration.pageURL
        )
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw NSError(
                domain: "HiddenPlaybackThumbnailPipeline",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "seek 缩略图解码失败"]
            )
        }

        let x = configuration.offsetX + columnIndex * (configuration.width + configuration.offsetX)
        let y = configuration.offsetY + rowIndex * (configuration.height + configuration.offsetY)
        let cropRect = CGRect(
            x: x,
            y: y,
            width: configuration.width,
            height: configuration.height
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard cropRect.width >= 1,
              cropRect.height >= 1,
              let croppedImage = cgImage.cropping(to: cropRect.integral) else {
            throw NSError(
                domain: "HiddenPlaybackThumbnailPipeline",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "seek 缩略图裁切失败"]
            )
        }

        return UIImage(
            cgImage: croppedImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }

    private static func imageCost(for image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

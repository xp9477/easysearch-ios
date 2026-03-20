import CoreImage
import Foundation
import ImageIO
import UIKit
@preconcurrency import Vision

struct OCRTextLine: Identifiable, Hashable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct OCRRecognitionResult: Hashable {
    let fullText: String
    let lines: [OCRTextLine]
}

enum ImageOCRService {
    static func extractText(
        from image: UIImage,
        recognitionLanguages: [String]
    ) async throws -> OCRRecognitionResult {
        let preparedImage = preparedImageForRecognition(image)
        guard let cgImage = preparedImage.cgImage ?? makeCGImage(from: preparedImage) else {
            throw ImageTranslateError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = makeRequest(continuation: continuation)

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = recognitionLanguages

                do {
                    let handler = VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: CGImagePropertyOrientation(preparedImage.imageOrientation),
                        options: [:]
                    )
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: ImageTranslateError.ocrFailure(error.localizedDescription))
                }
            }
        }
    }

    static func extractText(
        from imageData: Data,
        recognitionLanguages: [String]
    ) async throws -> OCRRecognitionResult {
        guard let image = UIImage(data: imageData) else {
            throw ImageTranslateError.invalidImage
        }

        return try await extractText(from: image, recognitionLanguages: recognitionLanguages)
    }

    static func cropImage(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        let normalizedImage = uprightImage(from: image)
        guard let cgImage = normalizedImage.cgImage else { return nil }

        let boundedRect = CGRect(
            x: min(max(normalizedRect.minX, 0), 1),
            y: min(max(normalizedRect.minY, 0), 1),
            width: min(max(normalizedRect.width, 0), 1),
            height: min(max(normalizedRect.height, 0), 1)
        )

        guard boundedRect.width > 0.02, boundedRect.height > 0.02 else {
            return nil
        }

        let cropRect = CGRect(
            x: boundedRect.minX * normalizedImage.size.width,
            y: boundedRect.minY * normalizedImage.size.height,
            width: boundedRect.width * normalizedImage.size.width,
            height: boundedRect.height * normalizedImage.size.height
        ).integral

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }

    static func storedImageData(from image: UIImage) -> Data? {
        encodedJPEGData(from: image, maxDimension: 1600, compressionQuality: 0.82)
    }

    static func previewImageData(from image: UIImage) -> Data? {
        encodedJPEGData(from: image, maxDimension: 320, compressionQuality: 0.68)
    }

    private static func encodedJPEGData(
        from image: UIImage,
        maxDimension: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        let resized = resizedImage(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: compressionQuality)
    }

    private static func makeRequest(
        continuation: CheckedContinuation<OCRRecognitionResult, Error>
    ) -> VNRecognizeTextRequest {
        VNRecognizeTextRequest { request, error in
            if let error {
                continuation.resume(throwing: ImageTranslateError.ocrFailure(error.localizedDescription))
                return
            }

            let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                .sorted { lhs, rhs in
                    compareObservation(lhs: lhs, rhs: rhs)
                }

            let lines = observations.compactMap { observation -> OCRTextLine? in
                guard let text = observation.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return nil
                }

                return OCRTextLine(text: text)
            }

            let fullText = lines
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !fullText.isEmpty else {
                continuation.resume(throwing: ImageTranslateError.noTextRecognized)
                return
            }

            continuation.resume(returning: OCRRecognitionResult(fullText: fullText, lines: lines))
        }
    }

    private static func compareObservation(
        lhs: VNRecognizedTextObservation,
        rhs: VNRecognizedTextObservation
    ) -> Bool {
        let yDifference = lhs.boundingBox.maxY - rhs.boundingBox.maxY
        if abs(yDifference) > 0.02 {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }

        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private static func preparedImageForRecognition(_ image: UIImage) -> UIImage {
        resizedImage(image, maxDimension: 2400)
    }

    private static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let upright = uprightImage(from: image)
        let longestSide = max(upright.size.width, upright.size.height)
        guard longestSide > maxDimension, longestSide > 0 else {
            return upright
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: upright.size.width * scale, height: upright.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            upright.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func uprightImage(from image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func makeCGImage(from image: UIImage) -> CGImage? {
        if let ciImage = image.ciImage {
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }

        return nil
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

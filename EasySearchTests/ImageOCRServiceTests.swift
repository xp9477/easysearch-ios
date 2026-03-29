import UIKit
import XCTest
@testable import EasySearch

final class ImageOCRServiceTests: XCTestCase {
    func testCropSelectionMapsToOriginalPixelsWithoutVerticalOffset() {
        let image = makeStripedImage(scale: 3)
        let selection = ImageCropSelection(
            normalizedRect: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2),
            displaySize: CGSize(width: 275, height: 550)
        )

        guard let croppedImage = ImageOCRService.cropImage(image, selection: selection) else {
            XCTFail("Expected crop result")
            return
        }

        XCTAssertEqual(croppedImage.size.width, 80, accuracy: 0.5)
        XCTAssertEqual(croppedImage.size.height, 40, accuracy: 0.5)
        assertColor(sampledColor(from: croppedImage), closeTo: .systemBlue)
    }

    func testCropNormalizedRectUsesSamePixelMapping() {
        let image = makeStripedImage(scale: 2)

        guard let croppedImage = ImageOCRService.cropImage(
            image,
            normalizedRect: CGRect(x: 0, y: 0.8, width: 1, height: 0.2)
        ) else {
            XCTFail("Expected crop result")
            return
        }

        XCTAssertEqual(croppedImage.size.width, 100, accuracy: 0.5)
        XCTAssertEqual(croppedImage.size.height, 40, accuracy: 0.5)
        assertColor(sampledColor(from: croppedImage), closeTo: .systemPink)
    }

    func testNormalizedDisplayImageRasterizesUpOrientedCIBackedImages() {
        let image = makeCIBackedStripedImage(scale: 3)

        XCTAssertNil(image.cgImage)

        let normalizedImage = ImageOCRService.normalizedDisplayImage(image)

        XCTAssertNotNil(normalizedImage.cgImage)
        XCTAssertEqual(normalizedImage.imageOrientation, .up)

        guard let croppedImage = ImageOCRService.cropImage(
            normalizedImage,
            normalizedRect: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2)
        ) else {
            XCTFail("Expected crop result")
            return
        }

        assertColor(sampledColor(from: croppedImage), closeTo: .systemBlue)
    }

    private func makeStripedImage(scale: CGFloat) -> UIImage {
        let size = CGSize(width: 100, height: 200)
        let stripeHeight = size.height / 5
        let colors: [UIColor] = [
            .systemRed,
            .systemGreen,
            .systemBlue,
            .systemYellow,
            .systemPink
        ]

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(
                    CGRect(
                        x: 0,
                        y: CGFloat(index) * stripeHeight,
                        width: size.width,
                        height: stripeHeight
                    )
                )
            }
        }
    }

    private func makeCIBackedStripedImage(scale: CGFloat) -> UIImage {
        let rasterized = makeStripedImage(scale: 1)
        guard let cgImage = rasterized.cgImage else {
            XCTFail("Missing cgImage")
            return rasterized
        }

        let ciImage = CIImage(cgImage: cgImage)
        return UIImage(ciImage: ciImage, scale: scale, orientation: .up)
    }

    private func sampledColor(from image: UIImage) -> UIColor {
        guard let cgImage = image.cgImage else {
            XCTFail("Missing cgImage")
            return .clear
        }
        guard let centerPixel = cgImage.cropping(
            to: CGRect(
                x: cgImage.width / 2,
                y: cgImage.height / 2,
                width: 1,
                height: 1
            )
        ) else {
            XCTFail("Missing center pixel")
            return .clear
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Missing CGContext")
            return .clear
        }

        context.interpolationQuality = .none
        context.draw(centerPixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255
        )
    }

    private func assertColor(_ actual: UIColor, closeTo expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0

        XCTAssertTrue(actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertTrue(expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha), file: file, line: line)

        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.05, file: file, line: line)
    }
}

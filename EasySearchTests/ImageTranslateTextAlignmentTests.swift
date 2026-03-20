import XCTest
@testable import EasySearch

final class ImageTranslateTextAlignmentTests: XCTestCase {
    func testParagraphAlignmentWhenCountsMatch() {
        let source = """
        First paragraph.

        Second paragraph.
        """
        let translation = """
        第一段。

        第二段。
        """

        let sections = ImageTranslateTextAlignment.sections(
            source: source,
            translation: translation
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].sourceText, "First paragraph.")
        XCTAssertEqual(sections[0].translatedText, "第一段。")
        XCTAssertEqual(sections[1].sourceText, "Second paragraph.")
        XCTAssertEqual(sections[1].translatedText, "第二段。")
    }

    func testLineAlignmentWhenLineCountsAreClose() {
        let source = """
        One
        Two
        Three
        """
        let translation = """
        一
        二
        """

        let sections = ImageTranslateTextAlignment.sections(
            source: source,
            translation: translation
        )

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].translatedText, "一")
        XCTAssertEqual(sections[1].translatedText, "二")
        XCTAssertEqual(sections[2].translatedText, "")
    }

    func testFallbackToSingleSectionWhenStructureDoesNotMatch() {
        let source = """
        A
        B
        C
        D
        E
        """
        let translation = "统一译文"

        let sections = ImageTranslateTextAlignment.sections(
            source: source,
            translation: translation
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].sourceText, source)
        XCTAssertEqual(sections[0].translatedText, translation)
    }
}

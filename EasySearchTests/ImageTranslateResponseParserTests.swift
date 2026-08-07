import XCTest
@testable import EasySearch

final class ImageTranslateResponseParserTests: XCTestCase {
    func testLexicalQueryDetectsSingleWordAndShortPhrase() {
        XCTAssertTrue(ImageTranslateResponseParser.isLikelyLexicalQuery("hello"))
        XCTAssertTrue(ImageTranslateResponseParser.isLikelyLexicalQuery("look up"))
        XCTAssertTrue(ImageTranslateResponseParser.isLikelyLexicalQuery("人工智能"))
        XCTAssertTrue(ImageTranslateResponseParser.isLikelyLexicalQuery("make sense of"))
    }

    func testLexicalQueryRejectsSentencesAndLongText() {
        XCTAssertFalse(ImageTranslateResponseParser.isLikelyLexicalQuery("Hello, how are you?"))
        XCTAssertFalse(ImageTranslateResponseParser.isLikelyLexicalQuery("这是一句完整的话。"))
        XCTAssertFalse(ImageTranslateResponseParser.isLikelyLexicalQuery("line one\nline two"))
        XCTAssertFalse(
            ImageTranslateResponseParser.isLikelyLexicalQuery(
                String(repeating: "word ", count: 20)
            )
        )
    }

    func testSanitizeJSONContentStripsCodeFenceAndSurroundingNoise() {
        let raw = """
        Here is the result:
        ```json
        {"translation":"你好","notes":"","detected_source_language":"English","meanings":[],"examples":[],"collocations":[]}
        ```
        """

        let cleaned = ImageTranslateResponseParser.sanitizeJSONContent(raw)
        XCTAssertTrue(cleaned.hasPrefix("{"))
        XCTAssertTrue(cleaned.hasSuffix("}"))
        XCTAssertTrue(cleaned.contains("\"translation\":\"你好\""))
        XCTAssertFalse(cleaned.contains("```"))
    }

    func testMaxTokensIsBoundedForLexicalAndMinimalModes() {
        XCTAssertEqual(ImageTranslateResponseParser.maxTokens(isLexical: true, isMinimal: false), 700)
        XCTAssertEqual(ImageTranslateResponseParser.maxTokens(isLexical: false, isMinimal: false), 1200)
        XCTAssertEqual(ImageTranslateResponseParser.maxTokens(isLexical: true, isMinimal: true), 320)
        XCTAssertLessThan(
            ImageTranslateResponseParser.maxTokens(isLexical: true, isMinimal: false),
            2400
        )
    }
}

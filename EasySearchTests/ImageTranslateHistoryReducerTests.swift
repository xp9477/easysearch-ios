import Foundation
import XCTest
@testable import EasySearch

final class ImageTranslateHistoryReducerTests: XCTestCase {
    func testUpsertKeepsNewestRecordFirst() {
        let earlier = makeRecord(title: "Earlier", updatedAt: Date(timeIntervalSince1970: 10))
        let later = makeRecord(title: "Later", updatedAt: Date(timeIntervalSince1970: 20))

        let records = ImageTranslateHistoryReducer.upsert(earlier, into: [later])

        XCTAssertEqual(records.map(\.title), ["Later", "Earlier"])
    }

    func testUpsertReplacesExistingRecordWithSameID() {
        let id = UUID()
        let original = makeRecord(
            id: id,
            title: "Old",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let updated = makeRecord(
            id: id,
            title: "New",
            updatedAt: Date(timeIntervalSince1970: 30)
        )

        let records = ImageTranslateHistoryReducer.upsert(updated, into: [original])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.title, "New")
    }

    func testUpsertRespectsLimit() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let existing = (0 ..< 20).map { index in
            makeRecord(
                title: "Record \(index)",
                updatedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        let newest = makeRecord(
            title: "Newest",
            updatedAt: baseDate.addingTimeInterval(100)
        )

        let records = ImageTranslateHistoryReducer.upsert(newest, into: existing, limit: 20)

        XCTAssertEqual(records.count, 20)
        XCTAssertEqual(records.first?.title, "Newest")
    }

    func testDeleteRemovesMatchingRecord() {
        let kept = makeRecord(title: "Keep", updatedAt: Date(timeIntervalSince1970: 10))
        let removed = makeRecord(title: "Remove", updatedAt: Date(timeIntervalSince1970: 20))

        let records = ImageTranslateHistoryReducer.delete(
            recordID: removed.id,
            from: [kept, removed]
        )

        XCTAssertEqual(records, [kept])
    }

    private func makeRecord(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date
    ) -> ImageTranslateHistoryRecord {
        ImageTranslateHistoryRecord(
            id: id,
            updatedAt: updatedAt,
            imageSource: .clipboard,
            targetLanguage: .simplifiedChinese,
            detectedSourceLanguage: "English",
            title: title,
            sourceSnippet: "Source snippet",
            translationSnippet: "Translation snippet",
            sourceText: "Source text",
            translation: "Translation text",
            translationNotes: "",
            meanings: [],
            examples: [],
            collocations: [],
            conversation: [],
            suggestedReplies: [],
            selectedImageData: nil,
            previewImageData: nil
        )
    }
}

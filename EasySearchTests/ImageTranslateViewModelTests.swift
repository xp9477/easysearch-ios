import Foundation
import XCTest
@testable import EasySearch

@MainActor
final class ImageTranslateViewModelTests: XCTestCase {
    func testPrepareLoadsHistoryWithoutClearingPersistedRecords() async {
        let record = makeRecord(title: "Saved translation")
        let store = SpyImageTranslateSessionStore(history: [record])
        let viewModel = ImageTranslateViewModel(
            store: store,
            notificationCenter: NotificationCenter()
        )

        await viewModel.prepare()

        XCTAssertEqual(viewModel.history, [record])
        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertTrue(store.savedHistoryRecords.isEmpty)
    }

    private func makeRecord(
        id: UUID = UUID(),
        title: String
    ) -> ImageTranslateHistoryRecord {
        ImageTranslateHistoryRecord(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 100),
            imageSource: .clipboard,
            targetLanguage: .simplifiedChinese,
            detectedSourceLanguage: "English",
            title: title,
            sourceSnippet: "Source",
            translationSnippet: "Translation",
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

private final class SpyImageTranslateSessionStore: ImageTranslateSessionStore {
    private let currentState: ImageTranslatePersistedState?
    private let historyRecords: [ImageTranslateHistoryRecord]
    private(set) var savedHistoryRecords: [[ImageTranslateHistoryRecord]] = []

    init(
        currentState: ImageTranslatePersistedState? = nil,
        history: [ImageTranslateHistoryRecord]
    ) {
        self.currentState = currentState
        self.historyRecords = history
    }

    func loadCurrentState() -> ImageTranslatePersistedState? {
        currentState
    }

    func saveCurrentState(_ state: ImageTranslatePersistedState) {}

    func clearCurrentState() {}

    func loadHistory() -> [ImageTranslateHistoryRecord] {
        historyRecords
    }

    func saveHistory(_ records: [ImageTranslateHistoryRecord]) {
        savedHistoryRecords.append(records)
    }
}

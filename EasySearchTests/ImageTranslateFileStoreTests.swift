import Foundation
import XCTest
@testable import EasySearch

final class ImageTranslateFileStoreTests: XCTestCase {
    func testSaveAndLoadCurrentState() throws {
        let directoryURL = makeTemporaryDirectory()
        let store = ImageTranslateFileStore(baseDirectoryURL: directoryURL)
        let state = ImageTranslatePersistedState(
            sessionID: UUID(),
            imageSource: .camera,
            targetLanguage: .english,
            selectedImageData: Data([0x01, 0x02]),
            previewImageData: Data([0x03]),
            extractedText: "hello",
            latestTranslation: "你好",
            translationNotes: "note",
            detectedSourceLanguage: "English",
            conversation: [
                ImageTranslateConversationMessage(role: .assistant, text: "done")
            ],
            suggestedReplies: ["继续"],
            composerText: "follow up",
            lastTranslatedSourceText: "hello"
        )

        store.saveCurrentState(state)

        XCTAssertEqual(store.loadCurrentState(), state)
    }

    func testSaveAndLoadHistory() throws {
        let directoryURL = makeTemporaryDirectory()
        let store = ImageTranslateFileStore(baseDirectoryURL: directoryURL)
        let record = ImageTranslateHistoryRecord(
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 100),
            imageSource: .photoLibrary,
            targetLanguage: .japanese,
            detectedSourceLanguage: "English",
            title: "History",
            sourceSnippet: "Source",
            translationSnippet: "Translation",
            sourceText: "Source full",
            translation: "Translation full",
            translationNotes: "note",
            conversation: [],
            suggestedReplies: ["继续"],
            selectedImageData: Data([0x10]),
            previewImageData: Data([0x20])
        )

        store.saveHistory([record])

        XCTAssertEqual(store.loadHistory(), [record])
    }

    func testClearCurrentStateRemovesPersistedFile() throws {
        let directoryURL = makeTemporaryDirectory()
        let store = ImageTranslateFileStore(baseDirectoryURL: directoryURL)
        let state = ImageTranslatePersistedState(
            sessionID: UUID(),
            imageSource: nil,
            targetLanguage: .simplifiedChinese,
            selectedImageData: nil,
            previewImageData: nil,
            extractedText: "text",
            latestTranslation: "",
            translationNotes: "",
            detectedSourceLanguage: nil,
            conversation: [],
            suggestedReplies: [],
            composerText: "",
            lastTranslatedSourceText: ""
        )

        store.saveCurrentState(state)
        store.clearCurrentState()

        XCTAssertNil(store.loadCurrentState())
    }

    private func makeTemporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }
}

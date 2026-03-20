import Foundation

struct ImageTranslatePersistedState: Codable, Equatable {
    var sessionID: UUID
    var imageSource: ImageTranslateInputSource?
    var targetLanguage: ImageTranslateTargetLanguage
    var selectedImageData: Data?
    var previewImageData: Data?
    var extractedText: String
    var latestTranslation: String
    var translationNotes: String
    var detectedSourceLanguage: String?
    var conversation: [ImageTranslateConversationMessage]
    var suggestedReplies: [String]
    var composerText: String
    var lastTranslatedSourceText: String
}

struct ImageTranslateHistoryRecord: Identifiable, Hashable, Codable, Equatable {
    var id: UUID
    var updatedAt: Date
    var imageSource: ImageTranslateInputSource?
    var targetLanguage: ImageTranslateTargetLanguage
    var detectedSourceLanguage: String?
    var title: String
    var sourceSnippet: String
    var translationSnippet: String
    var sourceText: String
    var translation: String
    var translationNotes: String
    var conversation: [ImageTranslateConversationMessage]
    var suggestedReplies: [String]
    var selectedImageData: Data?
    var previewImageData: Data?
}

protocol ImageTranslateSessionStore {
    func loadCurrentState() -> ImageTranslatePersistedState?
    func saveCurrentState(_ state: ImageTranslatePersistedState)
    func clearCurrentState()
    func loadHistory() -> [ImageTranslateHistoryRecord]
    func saveHistory(_ records: [ImageTranslateHistoryRecord])
}

enum ImageTranslateHistoryReducer {
    static func upsert(
        _ record: ImageTranslateHistoryRecord,
        into existingRecords: [ImageTranslateHistoryRecord],
        limit: Int = 20
    ) -> [ImageTranslateHistoryRecord] {
        let filtered = existingRecords.filter { $0.id != record.id }
        let sorted = ([record] + filtered)
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }

        return Array(sorted.prefix(limit))
    }

    static func delete(
        recordID: UUID,
        from existingRecords: [ImageTranslateHistoryRecord]
    ) -> [ImageTranslateHistoryRecord] {
        existingRecords.filter { $0.id != recordID }
    }
}

final class ImageTranslateFileStore: ImageTranslateSessionStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var currentStateURL: URL {
        directoryURL.appendingPathComponent("current-state.json")
    }

    private var historyURL: URL {
        directoryURL.appendingPathComponent("history.json")
    }

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let baseDirectoryURL {
            self.directoryURL = baseDirectoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = appSupport.appendingPathComponent("EasySearch/ImageTranslate", isDirectory: true)
        }

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        createDirectoryIfNeeded()
    }

    func loadCurrentState() -> ImageTranslatePersistedState? {
        readValue(ImageTranslatePersistedState.self, from: currentStateURL)
    }

    func saveCurrentState(_ state: ImageTranslatePersistedState) {
        writeValue(state, to: currentStateURL)
    }

    func clearCurrentState() {
        try? fileManager.removeItem(at: currentStateURL)
    }

    func loadHistory() -> [ImageTranslateHistoryRecord] {
        readValue([ImageTranslateHistoryRecord].self, from: historyURL) ?? []
    }

    func saveHistory(_ records: [ImageTranslateHistoryRecord]) {
        writeValue(records, to: historyURL)
    }

    private func createDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func readValue<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func writeValue<T: Encodable>(_ value: T, to url: URL) {
        createDirectoryIfNeeded()
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

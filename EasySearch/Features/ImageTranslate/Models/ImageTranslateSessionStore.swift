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
    var meanings: [ImageTranslateMeaning]
    var examples: [ImageTranslateExample]
    var collocations: [ImageTranslateCollocation]
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
    var meanings: [ImageTranslateMeaning]
    var examples: [ImageTranslateExample]
    var collocations: [ImageTranslateCollocation]
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

extension ImageTranslatePersistedState {
    private enum CodingKeys: String, CodingKey {
        case sessionID
        case imageSource
        case targetLanguage
        case selectedImageData
        case previewImageData
        case extractedText
        case latestTranslation
        case translationNotes
        case detectedSourceLanguage
        case meanings
        case examples
        case collocations
        case conversation
        case suggestedReplies
        case composerText
        case lastTranslatedSourceText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        imageSource = try container.decodeIfPresent(ImageTranslateInputSource.self, forKey: .imageSource)
        targetLanguage = try container.decode(ImageTranslateTargetLanguage.self, forKey: .targetLanguage)
        selectedImageData = try container.decodeIfPresent(Data.self, forKey: .selectedImageData)
        previewImageData = try container.decodeIfPresent(Data.self, forKey: .previewImageData)
        extractedText = try container.decode(String.self, forKey: .extractedText)
        latestTranslation = try container.decode(String.self, forKey: .latestTranslation)
        translationNotes = try container.decode(String.self, forKey: .translationNotes)
        detectedSourceLanguage = try container.decodeIfPresent(String.self, forKey: .detectedSourceLanguage)
        meanings = try container.decodeIfPresent([ImageTranslateMeaning].self, forKey: .meanings) ?? []
        examples = try container.decodeIfPresent([ImageTranslateExample].self, forKey: .examples) ?? []
        collocations = try container.decodeIfPresent([ImageTranslateCollocation].self, forKey: .collocations) ?? []
        conversation = try container.decodeIfPresent([ImageTranslateConversationMessage].self, forKey: .conversation) ?? []
        suggestedReplies = try container.decodeIfPresent([String].self, forKey: .suggestedReplies) ?? []
        composerText = try container.decodeIfPresent(String.self, forKey: .composerText) ?? ""
        lastTranslatedSourceText = try container.decodeIfPresent(String.self, forKey: .lastTranslatedSourceText) ?? ""
    }
}

extension ImageTranslateHistoryRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case updatedAt
        case imageSource
        case targetLanguage
        case detectedSourceLanguage
        case title
        case sourceSnippet
        case translationSnippet
        case sourceText
        case translation
        case translationNotes
        case meanings
        case examples
        case collocations
        case conversation
        case suggestedReplies
        case selectedImageData
        case previewImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        imageSource = try container.decodeIfPresent(ImageTranslateInputSource.self, forKey: .imageSource)
        targetLanguage = try container.decode(ImageTranslateTargetLanguage.self, forKey: .targetLanguage)
        detectedSourceLanguage = try container.decodeIfPresent(String.self, forKey: .detectedSourceLanguage)
        title = try container.decode(String.self, forKey: .title)
        sourceSnippet = try container.decode(String.self, forKey: .sourceSnippet)
        translationSnippet = try container.decode(String.self, forKey: .translationSnippet)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        translation = try container.decode(String.self, forKey: .translation)
        translationNotes = try container.decode(String.self, forKey: .translationNotes)
        meanings = try container.decodeIfPresent([ImageTranslateMeaning].self, forKey: .meanings) ?? []
        examples = try container.decodeIfPresent([ImageTranslateExample].self, forKey: .examples) ?? []
        collocations = try container.decodeIfPresent([ImageTranslateCollocation].self, forKey: .collocations) ?? []
        conversation = try container.decodeIfPresent([ImageTranslateConversationMessage].self, forKey: .conversation) ?? []
        suggestedReplies = try container.decodeIfPresent([String].self, forKey: .suggestedReplies) ?? []
        selectedImageData = try container.decodeIfPresent(Data.self, forKey: .selectedImageData)
        previewImageData = try container.decodeIfPresent(Data.self, forKey: .previewImageData)
    }
}

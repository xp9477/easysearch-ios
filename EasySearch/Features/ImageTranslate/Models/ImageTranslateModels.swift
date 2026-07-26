import Foundation

enum ImageTranslateInputSource: String, Equatable, Codable {
    case camera
    case photoLibrary
    case clipboard

    var title: String {
        switch self {
        case .camera:
            return "拍照"
        case .photoLibrary:
            return "相册"
        case .clipboard:
            return "剪贴板"
        }
    }

    var symbolName: String {
        switch self {
        case .camera:
            return "camera.fill"
        case .photoLibrary:
            return "photo.on.rectangle.angled"
        case .clipboard:
            return "doc.on.clipboard"
        }
    }
}

enum ImageTranslateTargetLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese
    case english
    case japanese
    case korean

    var id: Self { self }

    var title: String {
        switch self {
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "英语"
        case .japanese:
            return "日语"
        case .korean:
            return "韩语"
        }
    }

    var promptLabel: String {
        switch self {
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .english:
            return "English"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        }
    }
}

enum ImageTranslateNoticeTone: Equatable {
    case neutral
    case success
    case caution
}

struct ImageTranslateNotice: Equatable {
    let tone: ImageTranslateNoticeTone
    let message: String
}

enum ImageTranslateConversationRole: String, Codable {
    case user
    case assistant
}

struct ImageTranslateConversationMessage: Identifiable, Hashable, Codable, Equatable {
    let id: UUID
    let role: ImageTranslateConversationRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ImageTranslateConversationRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct ImageTranslateMeaning: Hashable, Codable, Equatable {
    let partOfSpeech: String
    let meaning: String
}

struct ImageTranslateExample: Hashable, Codable, Equatable {
    let source: String
    let translation: String
}

struct ImageTranslateCollocation: Hashable, Codable, Equatable {
    let phrase: String
    let translation: String
    let note: String
}

struct ImageTranslateResult: Equatable {
    let translation: String
    let reply: String
    let notes: String
    let detectedSourceLanguage: String?
    let meanings: [ImageTranslateMeaning]
    let examples: [ImageTranslateExample]
    let collocations: [ImageTranslateCollocation]
    let suggestedReplies: [String]
}

struct ImageTranslateConfiguration: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    var targetLanguage: ImageTranslateTargetLanguage

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "deepseek-chat" : trimmed
    }

    var deepSeekConfiguration: DeepSeekClientConfiguration {
        DeepSeekClientConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            model: resolvedModel
        )
    }

    var serviceConfiguration: AIServiceConfiguration {
        AIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    init(baseURL: String, apiKey: String, model: String, targetLanguage: ImageTranslateTargetLanguage) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.targetLanguage = targetLanguage
    }

    init(service: AIServiceConfiguration, targetLanguage: ImageTranslateTargetLanguage) {
        self.baseURL = service.baseURL
        self.apiKey = service.apiKey
        self.model = service.model
        self.targetLanguage = targetLanguage
    }
}

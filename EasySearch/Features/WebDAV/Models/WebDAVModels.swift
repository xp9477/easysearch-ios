import Foundation

struct WebDAVConfiguration: Equatable, Sendable {
    let locationID: UUID?
    let displayName: String
    let baseURL: URL
    let username: String
    let password: String

    init(
        locationID: UUID? = nil,
        displayName: String = "",
        baseURL: URL,
        username: String,
        password: String
    ) {
        self.locationID = locationID
        self.displayName = displayName
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    var isSMB: Bool {
        baseURL.scheme?.lowercased() == "smb"
    }

    var isWebDAV: Bool {
        let scheme = baseURL.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    var isValid: Bool {
        // Disallow inline credentials in URL to prevent plain-text credential leaks in UserDefaults
        if baseURL.user != nil || baseURL.password != nil {
            return false
        }

        guard let scheme = baseURL.scheme?.lowercased() else { return false }
        let path = baseURL.path
        if path.contains("..") || path.contains("\\") || path.contains("\0") {
            return false
        }

        if scheme == "http" || scheme == "https" {
            guard let host = baseURL.host, !host.isEmpty else { return false }
            return true
        }

        if scheme == "smb" {
            guard let host = baseURL.host, !host.isEmpty else { return false }
            let parts = path.split(separator: "/").filter { !$0.isEmpty }
            return !parts.isEmpty
        }

        return false
    }

    var cacheKey: String {
        "\(locationID?.uuidString ?? "legacy")|\(baseURL.absoluteString)|\(username)|\(password.hashValue)"
    }
}

struct WebDAVLocation: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let baseURL: URL
    let username: String
    let password: String

    var configuration: WebDAVConfiguration {
        WebDAVConfiguration(
            locationID: id,
            displayName: name,
            baseURL: baseURL,
            username: username,
            password: password
        )
    }

    var isSMB: Bool {
        baseURL.scheme?.lowercased() == "smb"
    }
}

struct WebDAVItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case file
        case directory
    }

    let path: String
    let name: String
    let kind: Kind
    let contentLength: Int64?
    let modifiedAt: Date?
    let contentType: String?
    let etag: String?

    init(
        path: String,
        name: String,
        kind: Kind,
        contentLength: Int64?,
        modifiedAt: Date?,
        contentType: String? = nil,
        etag: String? = nil
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.contentLength = contentLength
        self.modifiedAt = modifiedAt
        self.contentType = contentType
        self.etag = etag
    }

    var id: String { path }
    var isDirectory: Bool { kind == .directory }
    var isHiddenFolder: Bool { isDirectory && name.hasPrefix(".") }
}

struct WebDAVItemDetails: Equatable, Sendable {
    let fileCount: Int
    let folderCount: Int
    let totalSize: Int64
    let unknownSizeFileCount: Int
}

struct WebDAVTransferProgress: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64?
    let completedFiles: Int
    let totalFiles: Int

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

enum WebDAVError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case malformedListing
    case localFileMissing
    case symbolicLinkUnsupported
    case tooManyNameConflicts
    case editConflict
    case textFileTooLarge
    case unsupportedTextEncoding
    case invalidDestination
    case destinationExists
    case destinationIsDescendant

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "请先完成存储连接配置。"
        case .invalidURL:
            return "存储服务器地址无效，请检查协议和地址格式（不得包含内联用户名密码或 .. 路径）。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case let .server(statusCode, message):
            if message.isEmpty {
                return "请求失败（状态码 \(statusCode)）。"
            }
            return "请求失败（状态码 \(statusCode)）：\(message)"
        case .malformedListing:
            return "服务器目录列表格式无法解析。"
        case .localFileMissing:
            return "本地文件已不存在，请重新选择。"
        case .symbolicLinkUnsupported:
            return "暂不支持上传符号链接。"
        case .tooManyNameConflicts:
            return "远程目录中存在过多同名项目，无法生成可用名称。"
        case .editConflict:
            return "远程文件已被修改或版本不一致，请重新打开后再编辑。"
        case .textFileTooLarge:
            return "该文本文件过大，无法在 App 内编辑。"
        case .unsupportedTextEncoding:
            return "该文档不是可编辑的 UTF-8 文本。"
        case .invalidDestination:
            return "目标路径无效，请选择合法的目标目录。"
        case .destinationExists:
            return "目标位置已存在同名项目。"
        case .destinationIsDescendant:
            return "无法将文件夹移动到自身或其子目录中。"
        }
    }
}

import Foundation

struct WebDAVConfiguration: Equatable, Sendable {
    let baseURL: URL
    let username: String
    let password: String

    var isValid: Bool {
        guard let scheme = baseURL.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && baseURL.host != nil
    }

    var cacheKey: String {
        "\(baseURL.absoluteString)|\(username)"
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

    var id: String { path }
    var isDirectory: Bool { kind == .directory }
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

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "请先完成 WebDAV 连接配置。"
        case .invalidURL:
            return "WebDAV 地址无效，请检查协议和域名。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case let .server(statusCode, message):
            if message.isEmpty {
                return "WebDAV 请求失败（HTTP \(statusCode)）。"
            }
            return "WebDAV 请求失败（HTTP \(statusCode)）：\(message)"
        case .malformedListing:
            return "服务器目录列表格式无法解析。"
        case .localFileMissing:
            return "本地文件已不存在，请重新选择。"
        case .symbolicLinkUnsupported:
            return "暂不支持上传符号链接。"
        case .tooManyNameConflicts:
            return "远程目录中存在过多同名项目，无法生成可用名称。"
        }
    }
}

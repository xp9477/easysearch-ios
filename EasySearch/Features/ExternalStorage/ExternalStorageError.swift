import FileProvider
import Foundation
import Security
import Darwin

enum ExternalStorageError: LocalizedError, Sendable {
    case appGroupUnavailable(identifier: String)
    case keychainFailure(status: OSStatus)
    case passwordNotFound(locationID: UUID)
    case locationNotFound(locationID: UUID)
    case cannotAcquireLock(path: String)
    case invalidRemotePath(path: String)
    case traversalDetected(path: String)
    case rootOperationForbidden
    case versionConflict(expected: String, actual: String)
    case itemNotFound(pathOrID: String)
    case nameCollision(name: String)
    case serverUnreachable(message: String)

    var errorDescription: String? {
        switch self {
        case let .appGroupUnavailable(identifier):
            return "无法访问 App Group 共享存储空间（\(identifier)）。"
        case let .keychainFailure(status):
            return "共享钥匙串操作失败，状态码: \(status)。"
        case let .passwordNotFound(locationID):
            return "未在共享钥匙串中找到位置 \(locationID.uuidString) 的密码凭证。"
        case let .locationNotFound(locationID):
            return "未找到指定的存储位置配置：\(locationID.uuidString)。"
        case let .cannotAcquireLock(path):
            return "无法获取元数据文件锁：\(path)。"
        case let .invalidRemotePath(path):
            return "远程路径格式无效：\(path)。"
        case let .traversalDetected(path):
            return "检测到非法路径穿越尝试：\(path)。"
        case .rootOperationForbidden:
            return "根目录不支持重命名、移动或删除操作。"
        case let .versionConflict(expected, actual):
            return "版本发生冲突（基准版本: \(expected), 当前版本: \(actual)），请刷新后重试。"
        case let .itemNotFound(pathOrID):
            return "未找到指定的项目：\(pathOrID)。"
        case let .nameCollision(name):
            return "远程已存在同名项目：\(name)。"
        case let .serverUnreachable(message):
            return "远程服务器无法连接：\(message)。"
        }
    }

    func toNSFileProviderError() -> Error {
        switch self {
        case .keychainFailure, .passwordNotFound, .locationNotFound:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.notAuthenticated.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Not authenticated"]
            )
        case .itemNotFound:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.noSuchItem.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "No such item"]
            )
        case .nameCollision:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.filenameCollision.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Filename collision"]
            )
        case .serverUnreachable:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.serverUnreachable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Server unreachable"]
            )
        case .versionConflict:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.versionNoLongerAvailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Version out of date"]
            )
        case .rootOperationForbidden, .traversalDetected, .invalidRemotePath:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Forbidden operation"]
            )
        case .appGroupUnavailable, .cannotAcquireLock:
            return NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "System storage error"]
            )
        }
    }
}

enum ExternalStorageErrorMapper {
    static func mapToNSFileProviderError(_ error: Error) -> Error {
        if error is CancellationError { return CocoaError(.userCancelled) }
        let underlying = error as NSError
        if underlying.domain == NSPOSIXErrorDomain {
            switch underlying.code {
            case Int(ENOENT): return NSFileProviderError(.noSuchItem)
            case Int(EEXIST): return NSFileProviderError(.filenameCollision)
            case Int(EACCES), Int(EPERM): return NSFileProviderError(.notAuthenticated)
            default: break
            }
        }
        if let fpError = error as? NSFileProviderError {
            return fpError
        }
        let nsError = error as NSError
        if nsError.domain == NSFileProviderErrorDomain,
           let _ = NSFileProviderError.Code(rawValue: nsError.code) {
            return error
        }

        if let extError = error as? ExternalStorageError {
            return extError.toNSFileProviderError()
        }

        if let webDAVError = error as? WebDAVError {
            switch webDAVError {
            case .invalidConfiguration:
                return NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.notAuthenticated.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: webDAVError.localizedDescription]
                )
            case let .server(statusCode, message):
                switch statusCode {
                case 401, 403:
                    return NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.notAuthenticated.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "身份认证失败（HTTP \(statusCode)）：\(message)"]
                    )
                case 404:
                    return NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.noSuchItem.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "项目未找到（HTTP 404）"]
                    )
                case 409:
                    return NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.filenameCollision.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "名称冲突（HTTP 409）"]
                    )
                case 412:
                    return NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.versionNoLongerAvailable.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "版本过期冲突（HTTP 412）"]
                    )
                default:
                    return NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.serverUnreachable.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "服务器通信失败（HTTP \(statusCode)）"]
                    )
                }
            case .editConflict:
                return NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.versionNoLongerAvailable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: webDAVError.localizedDescription]
                )
            case .tooManyNameConflicts, .destinationExists:
                return NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.filenameCollision.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: webDAVError.localizedDescription]
                )
            case .localFileMissing:
                return NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.noSuchItem.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: webDAVError.localizedDescription]
                )
            case .invalidDestination, .destinationIsDescendant, .invalidURL, .invalidResponse, .malformedListing, .symbolicLinkUnsupported,
                 .textFileTooLarge, .unsupportedTextEncoding:
                return NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: webDAVError.localizedDescription]
                )
            }
        }

        return NSError(
            domain: NSFileProviderErrorDomain,
            code: NSFileProviderError.Code.serverUnreachable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
}

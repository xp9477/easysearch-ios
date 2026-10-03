import Foundation

protocol ExternalStorageClientProtocol {
    func list(path: String) async throws -> [WebDAVItem]
    func createDirectory(path: String) async throws
    func uploadExact(localURL: URL, remotePath: String) async throws
    func move(item: WebDAVItem, to newPath: String) async throws
    func delete(item: WebDAVItem) async throws
    func replace(localURL: URL, item: WebDAVItem, force: Bool) async throws
    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL
    func makeStreamingRequest(for item: WebDAVItem, rangeHeader: String?) throws -> URLRequest
}

final class ExternalStorageWebDAVAdapter: ExternalStorageClientProtocol {
    private let client: WebDAVClient

    init(configuration: WebDAVConfiguration, session: URLSession = .shared) {
        self.client = WebDAVClient(configuration: configuration, session: session)
    }

    func list(path: String) async throws -> [WebDAVItem] {
        try await client.list(path: path)
    }

    func createDirectory(path: String) async throws {
        try await client.createDirectory(path: path)
    }

    func uploadExact(localURL: URL, remotePath: String) async throws {
        try await client.uploadExact(localURL: localURL, remotePath: remotePath)
    }

    func move(item: WebDAVItem, to newPath: String) async throws {
        try await client.move(item: item, to: newPath)
    }

    func delete(item: WebDAVItem) async throws {
        try await client.delete(item: item)
    }

    func replace(localURL: URL, item: WebDAVItem, force: Bool) async throws {
        try await client.replace(localURL: localURL, item: item, force: force)
    }

    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        try await client.downloadForPreview(item: item, progress: progress)
    }

    func makeStreamingRequest(for item: WebDAVItem, rangeHeader: String?) throws -> URLRequest {
        try client.makeStreamingRequest(for: item, rangeHeader: rangeHeader)
    }
}

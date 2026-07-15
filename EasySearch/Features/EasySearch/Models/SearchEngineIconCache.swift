import Foundation
import UIKit

actor SearchEngineIconCache {
    static let shared = SearchEngineIconCache()

    private enum Constants {
        static let memoryCapacity = 4 * 1024 * 1024
        static let diskCapacity = 32 * 1024 * 1024
        static let maximumImageSize = 1024 * 1024
    }

    private enum CacheError: Error {
        case invalidResponse
        case unsuccessfulResponse(Int)
        case invalidContentType
        case imageTooLarge
        case invalidImageData
    }

    private struct LoadResult {
        let data: Data
        let allowsMemoryCaching: Bool
    }

    private let memoryCache = NSCache<NSString, NSData>()
    private let urlCache: URLCache
    private let session: URLSession
    private var inFlightTasks: [String: Task<LoadResult, Error>] = [:]

    init(
        urlCache: URLCache? = nil,
        cacheDirectoryURL: URL? = nil,
        protocolClasses: [AnyClass]? = nil
    ) {
        let resolvedURLCache: URLCache
        if let urlCache {
            resolvedURLCache = urlCache
        } else {
            let directoryURL = cacheDirectoryURL ?? Self.defaultCacheDirectoryURL()
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            resolvedURLCache = URLCache(
                memoryCapacity: Constants.memoryCapacity,
                diskCapacity: Constants.diskCapacity,
                directory: directoryURL
            )
        }

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = resolvedURLCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        self.urlCache = resolvedURLCache
        self.session = URLSession(configuration: configuration)
        memoryCache.countLimit = 64
        memoryCache.totalCostLimit = Constants.memoryCapacity
    }

    func data(for url: URL) async throws -> Data {
        let key = url.absoluteString
        let memoryKey = key as NSString

        if let cachedData = memoryCache.object(forKey: memoryKey) {
            return cachedData as Data
        }

        if let existingTask = inFlightTasks[key] {
            return try await existingTask.value.data
        }

        let request = Self.request(for: url)
        let session = session
        let urlCache = urlCache
        let task = Task(priority: .utility) {
            try await Self.loadData(
                for: request,
                session: session,
                urlCache: urlCache
            )
        }

        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }

        let result = try await task.value
        if result.allowsMemoryCaching {
            memoryCache.setObject(
                result.data as NSData,
                forKey: memoryKey,
                cost: result.data.count
            )
        }
        return result.data
    }

    func invalidate() {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        memoryCache.removeAllObjects()
        session.invalidateAndCancel()
    }

    private static func loadData(
        for request: URLRequest,
        session: URLSession,
        urlCache: URLCache
    ) async throws -> LoadResult {
        do {
            let (data, response) = try await session.data(for: request)

            do {
                let validatedData = try validate(data: data, response: response)
                let allowsCaching = allowsCaching(response: response)
                if allowsCaching {
                    store(validatedData, response: response, for: request, in: urlCache)
                } else {
                    urlCache.removeCachedResponse(for: request)
                }
                return LoadResult(
                    data: validatedData,
                    allowsMemoryCaching: allowsCaching
                )
            } catch {
                urlCache.removeCachedResponse(for: request)
                throw error
            }
        } catch let error as CacheError {
            throw error
        } catch {
            guard let cachedResponse = urlCache.cachedResponse(for: request) else {
                throw error
            }

            do {
                let data = try validate(
                    data: cachedResponse.data,
                    response: cachedResponse.response
                )
                return LoadResult(data: data, allowsMemoryCaching: true)
            } catch {
                urlCache.removeCachedResponse(for: request)
                throw error
            }
        }
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 20
        )
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    private static func validate(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CacheError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CacheError.unsuccessfulResponse(httpResponse.statusCode)
        }
        guard httpResponse.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw CacheError.invalidContentType
        }
        guard data.count <= Constants.maximumImageSize else {
            throw CacheError.imageTooLarge
        }
        guard UIImage(data: data) != nil else {
            throw CacheError.invalidImageData
        }
        return data
    }

    private static func store(
        _ data: Data,
        response: URLResponse,
        for request: URLRequest,
        in urlCache: URLCache
    ) {
        let cachedResponse = CachedURLResponse(
            response: response,
            data: data,
            storagePolicy: .allowed
        )
        urlCache.storeCachedResponse(cachedResponse, for: request)
    }

    private static func allowsCaching(response: URLResponse) -> Bool {
        let cacheControl = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Cache-Control")?
            .lowercased()
        return cacheControl?.contains("no-store") != true
    }

    private static func defaultCacheDirectoryURL() -> URL {
        let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return cachesURL
            .appendingPathComponent("EasySearch", isDirectory: true)
            .appendingPathComponent("Favicons-v1", isDirectory: true)
    }
}

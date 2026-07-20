import Foundation

// MARK: - Models

enum ExchangeRateSource: String, Codable {
    case network
    case cache
}

struct ExchangeRateResult {
    let rate: Double
    let updatedAt: Date
    let source: ExchangeRateSource
}

// MARK: - Service

actor ExchangeRateService {
    static let shared = ExchangeRateService()

    private let urlSession: URLSession
    private let userDefaults: UserDefaults

    private static let apiURL = URL(string: "https://open.er-api.com/v6/latest/CNY")!
    private static let cacheRateKey = "currencyConverter.cachedRate"
    private static let cacheDateKey = "currencyConverter.cachedDate"
    private static let cacheValiditySeconds: TimeInterval = 30 * 60 // 30 minutes

    private var lastFetchedResult: ExchangeRateResult?

    init(urlSession: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.urlSession = urlSession
        self.userDefaults = userDefaults
    }

    /// Fetch the CNY → TWD exchange rate.
    /// - Parameter force: When `true`, ignores cache validity and fetches from network.
    /// - Returns: The exchange rate result, from network or cache.
    func fetchRate(force: Bool = false) async throws -> ExchangeRateResult {
        // Return in-memory cached result if still valid and not forced
        if !force, let cached = lastFetchedResult,
           Date().timeIntervalSince(cached.updatedAt) < Self.cacheValiditySeconds {
            return cached
        }

        // Check disk cache validity when not forced
        if !force, let diskResult = loadCachedRate(),
           Date().timeIntervalSince(diskResult.updatedAt) < Self.cacheValiditySeconds {
            lastFetchedResult = diskResult
            return diskResult
        }

        // Attempt network fetch
        do {
            let result = try await fetchFromNetwork()
            lastFetchedResult = result
            persistRate(result)
            return result
        } catch {
            // Fallback to disk cache on network failure
            if let cached = loadCachedRate() {
                lastFetchedResult = cached
                return cached
            }
            throw error
        }
    }

    // MARK: - Network

    private func fetchFromNetwork() async throws -> ExchangeRateResult {
        var request = URLRequest(url: Self.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExchangeRateError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: data)

        guard decoded.result == "success" else {
            throw ExchangeRateError.apiError(decoded.result)
        }

        guard let twdRate = decoded.rates["TWD"] else {
            throw ExchangeRateError.missingRate("TWD")
        }

        return ExchangeRateResult(
            rate: twdRate,
            updatedAt: Date(),
            source: .network
        )
    }

    // MARK: - Cache

    private func persistRate(_ result: ExchangeRateResult) {
        userDefaults.set(result.rate, forKey: Self.cacheRateKey)
        userDefaults.set(result.updatedAt.timeIntervalSince1970, forKey: Self.cacheDateKey)
    }

    private func loadCachedRate() -> ExchangeRateResult? {
        let rate = userDefaults.double(forKey: Self.cacheRateKey)
        let timestamp = userDefaults.double(forKey: Self.cacheDateKey)
        guard rate > 0, timestamp > 0 else { return nil }

        return ExchangeRateResult(
            rate: rate,
            updatedAt: Date(timeIntervalSince1970: timestamp),
            source: .cache
        )
    }
}

// MARK: - API Response

private struct ExchangeRateAPIResponse: Decodable {
    let result: String
    let rates: [String: Double]
}

// MARK: - Errors

enum ExchangeRateError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case missingRate(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无效响应"
        case .apiError(let status):
            return "API 返回错误状态: \(status)"
        case .missingRate(let currency):
            return "未找到 \(currency) 汇率数据"
        }
    }
}

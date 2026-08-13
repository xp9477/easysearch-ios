import Foundation

// MARK: - Currency

enum ConverterCurrency: String, CaseIterable, Identifiable, Codable, Hashable {
    case cny = "CNY"
    case twd = "TWD"
    case hkd = "HKD"
    case mop = "MOP"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case krw = "KRW"
    case aud = "AUD"
    case nzd = "NZD"
    case cad = "CAD"
    case chf = "CHF"
    case sgd = "SGD"
    case myr = "MYR"
    case thb = "THB"
    case vnd = "VND"
    case idr = "IDR"
    case php = "PHP"
    case tryLira = "TRY"
    case inr = "INR"
    case aed = "AED"
    case sar = "SAR"
    case ils = "ILS"
    case sek = "SEK"
    case nok = "NOK"
    case dkk = "DKK"
    case pln = "PLN"
    case rub = "RUB"
    case brl = "BRL"
    case mxn = "MXN"
    case zar = "ZAR"

    var id: String { rawValue }

    var code: String { rawValue }

    var label: String {
        switch self {
        case .cny: return "人民币"
        case .twd: return "新台币"
        case .hkd: return "港币"
        case .mop: return "澳门元"
        case .usd: return "美元"
        case .eur: return "欧元"
        case .gbp: return "英镑"
        case .jpy: return "日元"
        case .krw: return "韩元"
        case .aud: return "澳大利亚元"
        case .nzd: return "新西兰元"
        case .cad: return "加拿大元"
        case .chf: return "瑞士法郎"
        case .sgd: return "新加坡元"
        case .myr: return "马来西亚林吉特"
        case .thb: return "泰铢"
        case .vnd: return "越南盾"
        case .idr: return "印度尼西亚盾"
        case .php: return "菲律宾比索"
        case .tryLira: return "土耳其里拉"
        case .inr: return "印度卢比"
        case .aed: return "阿联酋迪拉姆"
        case .sar: return "沙特里亚尔"
        case .ils: return "以色列新谢克尔"
        case .sek: return "瑞典克朗"
        case .nok: return "挪威克朗"
        case .dkk: return "丹麦克朗"
        case .pln: return "波兰兹罗提"
        case .rub: return "俄罗斯卢布"
        case .brl: return "巴西雷亚尔"
        case .mxn: return "墨西哥比索"
        case .zar: return "南非兰特"
        }
    }

    /// Currencies quoted against CNY by the remote API (CNY itself is always 1).
    static var remoteQuotedCurrencies: [ConverterCurrency] {
        allCases.filter { $0 != .cny }
    }
}

// MARK: - Models

enum ExchangeRateSource: String, Codable {
    case network
    case cache
}

struct ExchangeRateResult {
    /// Units of each currency per 1 CNY. Always includes `CNY: 1`.
    let ratesAgainstCNY: [ConverterCurrency: Double]
    let updatedAt: Date
    let source: ExchangeRateSource

    /// Convenience for CNY → TWD (legacy call sites / tests).
    var rate: Double? {
        ratesAgainstCNY[.twd]
    }

    func rate(of currency: ConverterCurrency) -> Double? {
        ratesAgainstCNY[currency]
    }

    /// Convert `amount` from `from` into `to` using CNY-based rates.
    func convert(amount: Double, from: ConverterCurrency, to: ConverterCurrency) -> Double? {
        guard let fromRate = ratesAgainstCNY[from], fromRate > 0,
              let toRate = ratesAgainstCNY[to] else {
            return nil
        }
        // amount_from / fromRate = CNY, * toRate = amount_to
        return amount / fromRate * toRate
    }
}

// MARK: - Service

actor ExchangeRateService {
    static let shared = ExchangeRateService()

    private let urlSession: URLSession
    private let userDefaults: UserDefaults

    private static let apiURL = URL(string: "https://open.er-api.com/v6/latest/CNY")!
    private static let cacheRatesKey = "currencyConverter.cachedRates.v2"
    private static let cacheDateKey = "currencyConverter.cachedDate.v2"
    /// Legacy single-rate cache (TWD only).
    private static let legacyCacheRateKey = "currencyConverter.cachedRate"
    private static let legacyCacheDateKey = "currencyConverter.cachedDate"
    private static let cacheValiditySeconds: TimeInterval = 30 * 60 // 30 minutes

    private var lastFetchedResult: ExchangeRateResult?

    init(urlSession: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.urlSession = urlSession
        self.userDefaults = userDefaults
    }

    /// Fetch CNY-based rates for all supported currencies.
    func fetchRate(force: Bool = false) async throws -> ExchangeRateResult {
        if !force, let cached = lastFetchedResult,
           Date().timeIntervalSince(cached.updatedAt) < Self.cacheValiditySeconds {
            return cached
        }

        if !force, let diskResult = loadCachedRates(requireAllSupportedCurrencies: true),
           Date().timeIntervalSince(diskResult.updatedAt) < Self.cacheValiditySeconds {
            lastFetchedResult = diskResult
            return diskResult
        }

        do {
            let result = try await fetchFromNetwork()
            lastFetchedResult = result
            persistRates(result)
            return result
        } catch {
            if let cached = loadCachedRates() {
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

        var rates: [ConverterCurrency: Double] = [.cny: 1]
        for currency in ConverterCurrency.remoteQuotedCurrencies {
            guard let value = decoded.rates[currency.rawValue], value > 0 else {
                throw ExchangeRateError.missingRate(currency.rawValue)
            }
            rates[currency] = value
        }

        return ExchangeRateResult(
            ratesAgainstCNY: rates,
            updatedAt: Date(),
            source: .network
        )
    }

    // MARK: - Cache

    private func persistRates(_ result: ExchangeRateResult) {
        let payload = result.ratesAgainstCNY.reduce(into: [String: Double]()) { dict, pair in
            dict[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(payload) {
            userDefaults.set(data, forKey: Self.cacheRatesKey)
        }
        userDefaults.set(result.updatedAt.timeIntervalSince1970, forKey: Self.cacheDateKey)

        // Keep legacy TWD key warm for older builds / tests that only check it.
        if let twd = result.ratesAgainstCNY[.twd] {
            userDefaults.set(twd, forKey: Self.legacyCacheRateKey)
            userDefaults.set(result.updatedAt.timeIntervalSince1970, forKey: Self.legacyCacheDateKey)
        }
    }

    private func loadCachedRates(requireAllSupportedCurrencies: Bool = false) -> ExchangeRateResult? {
        if let data = userDefaults.data(forKey: Self.cacheRatesKey),
           let payload = try? JSONDecoder().decode([String: Double].self, from: data) {
            var rates: [ConverterCurrency: Double] = [:]
            for currency in ConverterCurrency.allCases {
                if let value = payload[currency.rawValue], value > 0 {
                    rates[currency] = value
                }
            }
            rates[.cny] = 1
            let timestamp = userDefaults.double(forKey: Self.cacheDateKey)
            let hasRequiredRates = !requireAllSupportedCurrencies
                || rates.count == ConverterCurrency.allCases.count
            if hasRequiredRates, timestamp > 0 {
                return ExchangeRateResult(
                    ratesAgainstCNY: rates,
                    updatedAt: Date(timeIntervalSince1970: timestamp),
                    source: .cache
                )
            }
        }

        // Migrate legacy TWD-only cache if present.
        let legacyRate = userDefaults.double(forKey: Self.legacyCacheRateKey)
        let legacyTimestamp = userDefaults.double(forKey: Self.legacyCacheDateKey)
        if legacyRate > 0, legacyTimestamp > 0 {
            return ExchangeRateResult(
                ratesAgainstCNY: [.cny: 1, .twd: legacyRate],
                updatedAt: Date(timeIntervalSince1970: legacyTimestamp),
                source: .cache
            )
        }

        return nil
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

import Foundation
import SwiftUI

protocol SearchEngineRemoteConfigClient {
    func fetchLastModified(from url: URL) async throws -> String?
    func downloadConfig(from url: URL) async throws -> (data: Data, lastModified: String?)
}

struct URLSessionSearchEngineRemoteConfigClient: SearchEngineRemoteConfigClient {
    func fetchLastModified(from url: URL) async throws -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "SearchViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "远程配置 HEAD 请求失败"]
            )
        }

        return lastModifiedValue(from: httpResponse)
    }

    func downloadConfig(from url: URL) async throws -> (data: Data, lastModified: String?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "SearchViewModel",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "远程配置下载失败"]
            )
        }

        return (data, lastModifiedValue(from: httpResponse))
    }

    private func lastModifiedValue(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "Last-Modified")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 配置管理器 - 负责搜索引擎配置的加载、缓存和刷新
@MainActor
class SearchViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var searchEngines: [SearchEngine] = []
    @Published var searchQuery: String = ""
    @Published var selectedCategory: SearchCategory = .search
    @Published private(set) var preferredPlatformNames: [String: String] = [:]

    // MARK: - Constants

    private let configKey = "cached_search_engines"
    private let remoteLastModifiedKey = "search_engines.remote_last_modified"
    private let userDefaults: UserDefaults
    private let bundle: Bundle
    private let remoteConfigURL: URL?
    private let remoteConfigClient: any SearchEngineRemoteConfigClient
    private let usageStore: SearchEngineUsageStore
    private var didCheckRemoteConfig = false

    // MARK: - Computed Properties

    var filteredEngines: [SearchEngine] {
        searchEngines.filter { $0.searchCategory == selectedCategory }
    }

    var hasValidQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Return and the visible search button always use the same platform in this category.
    var defaultSearchEngine: SearchEngine? {
        let engines = filteredEngines
        let preferred = preferredPlatformNames[selectedCategory.rawValue]
        return engines.first { $0.name == preferred }
            ?? engines.first { $0.name == usageStore.lastUsedEngineName }
            ?? engines.first
    }

    func selectPlatform(_ engine: SearchEngine) {
        guard filteredEngines.contains(engine) else { return }
        preferredPlatformNames[selectedCategory.rawValue] = engine.name
    }

    // MARK: - Initialization

    init(
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        remoteConfigURL: URL? = URL(string: "https://raw.githubusercontent.com/xp9477/easy-search/main/data/search-engines.json"),
        remoteConfigClient: any SearchEngineRemoteConfigClient = URLSessionSearchEngineRemoteConfigClient(),
        usageStore: SearchEngineUsageStore = SearchEngineUsageStore()
    ) {
        self.userDefaults = userDefaults
        self.bundle = bundle
        self.remoteConfigURL = remoteConfigURL
        self.remoteConfigClient = remoteConfigClient
        self.usageStore = usageStore
        loadConfig()
    }

    // MARK: - Config Loading

    /// 加载配置：优先从 UserDefaults 读取，否则使用 Bundle 内置默认配置
    func loadConfig() {
        if let cachedData = userDefaults.data(forKey: configKey),
           let engines = try? JSONDecoder().decode([SearchEngine].self, from: cachedData) {
            self.searchEngines = engines
            print("✅ 从本地缓存加载了 \(engines.count) 个搜索引擎")
        } else {
            loadDefaultConfig()
        }
    }

    /// 从 Bundle 内置 JSON 文件加载默认配置
    private func loadDefaultConfig() {
        guard let url = bundle.url(forResource: "search-engines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let engines = try? JSONDecoder().decode([SearchEngine].self, from: data) else {
            print("❌ 无法加载默认配置文件")
            return
        }
        self.searchEngines = engines
        // 同时存入 UserDefaults 作为缓存
        saveToCache(data: data)
        print("✅ 从 Bundle 默认配置加载了 \(engines.count) 个搜索引擎")
    }

    // MARK: - Remote Refresh

    /// 启动后在后台检查 GitHub 配置是否更新
    func refreshConfigIfNeededOnLaunch() async {
        guard !didCheckRemoteConfig else { return }
        didCheckRemoteConfig = true
        await refreshRemoteConfigIfNeeded()
    }

    // MARK: - Search Action

    /// Try the app first, then the browser. Keep the query if neither opens.
    func performSearch(engine: SearchEngine) async -> Bool {
        guard hasValidQuery else { return false }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = UIApplication.shared
        if let scheme = engine.urlScheme,
           let url = SearchEngine.searchURL(template: scheme, query: query),
           app.canOpenURL(url), await app.open(url) {
            usageStore.recordUse(engineName: engine.name)
            return true
        }

        guard let url = SearchEngine.searchURL(template: engine.url, query: query),
              await app.open(url) else { return false }
        usageStore.recordUse(engineName: engine.name)
        return true
    }

    // MARK: - Private Helpers

    private func saveToCache(data: Data) {
        userDefaults.set(data, forKey: configKey)
    }

    private func refreshRemoteConfigIfNeeded() async {
        guard let url = remoteConfigURL else {
            return
        }

        do {
            let remoteLastModified = try await remoteConfigClient.fetchLastModified(from: url)
            let cachedLastModified = userDefaults.string(forKey: remoteLastModifiedKey)

            if let remoteLastModified, remoteLastModified == cachedLastModified {
                print("ℹ️ 远程配置没有变化，继续使用本地缓存")
                return
            }

            try await downloadAndApplyRemoteConfig(from: url, remoteLastModified: remoteLastModified)
        } catch {
            print("❌ 后台检查远程配置失败: \(error)")
        }
    }

    private func downloadAndApplyRemoteConfig(from url: URL, remoteLastModified: String?) async throws {
        let response = try await remoteConfigClient.downloadConfig(from: url)
        let data = response.data

        let engines = try JSONDecoder().decode([SearchEngine].self, from: data)
        if engines != searchEngines {
            searchEngines = engines
            print("✅ 检测到远程配置更新，已切换为最新配置，共 \(engines.count) 个搜索引擎")
        } else {
            print("ℹ️ 远程配置时间已变化，但内容未发生变化")
        }

        saveToCache(data: data)
        if let lastModified = remoteLastModified ?? response.lastModified {
            userDefaults.set(lastModified, forKey: remoteLastModifiedKey)
        }
    }
}

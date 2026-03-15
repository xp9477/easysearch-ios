import Foundation
import SwiftUI

/// 配置管理器 - 负责搜索引擎配置的加载、缓存和刷新
@MainActor
class SearchViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var searchEngines: [SearchEngine] = []
    @Published var searchQuery: String = ""
    @Published var selectedCategory: SearchCategory = .search

    // MARK: - Constants

    private let configKey = "cached_search_engines"
    private let remoteLastModifiedKey = "search_engines.remote_last_modified"
    private let remoteConfigURL = "https://raw.githubusercontent.com/xp9477/easy-search/main/data/search-engines.json"
    private var didCheckRemoteConfig = false

    // MARK: - Computed Properties

    /// 按当前选中分类过滤后的搜索引擎列表
    var filteredEngines: [SearchEngine] {
        searchEngines.filter { engine in
            engine.category == selectedCategory.rawValue ||
            (engine.category == nil && selectedCategory == .search)
        }
    }

    /// 搜索框是否有有效内容
    var hasValidQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var defaultSearchEngine: SearchEngine? {
        filteredEngines.first
    }

    // MARK: - Initialization

    init() {
        loadConfig()
        Task {
            await refreshConfigIfNeededOnLaunch()
        }
    }

    // MARK: - Config Loading

    /// 加载配置：优先从 UserDefaults 读取，否则使用 Bundle 内置默认配置
    func loadConfig() {
        if let cachedData = UserDefaults.standard.data(forKey: configKey),
           let engines = try? JSONDecoder().decode([SearchEngine].self, from: cachedData) {
            self.searchEngines = engines
            print("✅ 从本地缓存加载了 \(engines.count) 个搜索引擎")
        } else {
            loadDefaultConfig()
        }
    }

    /// 从 Bundle 内置 JSON 文件加载默认配置
    private func loadDefaultConfig() {
        guard let url = Bundle.main.url(forResource: "search-engines", withExtension: "json"),
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

    /// 执行搜索 - 在对应平台打开搜索结果
    func performSearch(engine: SearchEngine) {
        guard hasValidQuery else { return }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

        // iOS 上优先尝试 url_scheme（深度链接打开原生 App）
        if let scheme = engine.urlScheme {
            let schemeURL = scheme.replacingOccurrences(of: "{query}", with: encodedQuery)
            if let url = URL(string: schemeURL), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        // 降级到浏览器 URL
        let webURL = engine.url.replacingOccurrences(of: "{query}", with: encodedQuery)
        if let url = URL(string: webURL) {
            UIApplication.shared.open(url)
        }
    }

    @discardableResult
    func performDefaultSearch() -> Bool {
        guard let engine = defaultSearchEngine, hasValidQuery else {
            return false
        }

        performSearch(engine: engine)
        return true
    }

    // MARK: - Private Helpers

    private func saveToCache(data: Data) {
        UserDefaults.standard.set(data, forKey: configKey)
    }

    private func refreshRemoteConfigIfNeeded() async {
        guard let url = URL(string: remoteConfigURL) else {
            return
        }

        do {
            let remoteLastModified = try await fetchRemoteLastModified(from: url)
            let cachedLastModified = UserDefaults.standard.string(forKey: remoteLastModifiedKey)

            if let remoteLastModified, remoteLastModified == cachedLastModified {
                print("ℹ️ 远程配置没有变化，继续使用本地缓存")
                return
            }

            try await downloadAndApplyRemoteConfig(from: url, remoteLastModified: remoteLastModified)
        } catch {
            print("❌ 后台检查远程配置失败: \(error)")
        }
    }

    private func fetchRemoteLastModified(from url: URL) async throws -> String? {
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

    private func downloadAndApplyRemoteConfig(from url: URL, remoteLastModified: String?) async throws {
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

        let engines = try JSONDecoder().decode([SearchEngine].self, from: data)
        if engines != searchEngines {
            searchEngines = engines
            print("✅ 检测到远程配置更新，已切换为最新配置，共 \(engines.count) 个搜索引擎")
        } else {
            print("ℹ️ 远程配置时间已变化，但内容未发生变化")
        }

        saveToCache(data: data)
        if let lastModified = remoteLastModified ?? lastModifiedValue(from: httpResponse) {
            UserDefaults.standard.set(lastModified, forKey: remoteLastModifiedKey)
        }
    }

    private func lastModifiedValue(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "Last-Modified")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation
import SwiftUI

/// 配置管理器 - 负责搜索引擎配置的加载、缓存和刷新
@MainActor
class SearchViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var searchEngines: [SearchEngine] = []
    @Published var searchQuery: String = ""
    @Published var selectedCategory: SearchCategory = .search
    @Published var isRefreshing: Bool = false
    @Published var refreshError: String?
    @Published var refreshSuccess: Bool = false
    @Published var lastRefreshDate: Date?

    // MARK: - Constants

    private let configKey = "cached_search_engines"
    private let lastRefreshKey = "last_refresh_date"
    private let remoteConfigURL = "https://raw.githubusercontent.com/xp9477/easy-search/main/data/search-engines.json"

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

    // MARK: - Initialization

    init() {
        loadConfig()
        loadLastRefreshDate()
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

    /// 从 GitHub 远程拉取最新配置
    func refreshConfig() async {
        isRefreshing = true
        refreshError = nil
        refreshSuccess = false

        defer { isRefreshing = false }

        guard let url = URL(string: remoteConfigURL) else {
            refreshError = "配置 URL 无效"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                refreshError = "服务器返回错误"
                return
            }

            let engines = try JSONDecoder().decode([SearchEngine].self, from: data)
            self.searchEngines = engines
            saveToCache(data: data)
            lastRefreshDate = Date()
            UserDefaults.standard.set(lastRefreshDate, forKey: lastRefreshKey)
            refreshSuccess = true
            print("✅ 从远程刷新了 \(engines.count) 个搜索引擎配置")
        } catch {
            refreshError = "刷新失败: \(error.localizedDescription)"
            print("❌ 远程刷新失败: \(error)")
        }
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

    // MARK: - Private Helpers

    private func saveToCache(data: Data) {
        UserDefaults.standard.set(data, forKey: configKey)
    }

    private func loadLastRefreshDate() {
        lastRefreshDate = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date
    }
}

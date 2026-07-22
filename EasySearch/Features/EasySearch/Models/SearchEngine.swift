import Foundation

/// 搜索引擎数据模型
struct SearchEngine: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: String
    let urlScheme: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case urlScheme = "url_scheme"
        case category
    }

    var websiteHost: String? {
        URL(string: url.replacingOccurrences(of: "{query}", with: ""))?.host?.lowercased()
    }

    var displayHost: String {
        guard let websiteHost else { return "" }
        return websiteHost.hasPrefix("www.") ? String(websiteHost.dropFirst(4)) : websiteHost
    }

    var faviconURL: URL? {
        guard let websiteHost else { return nil }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain_url", value: "https://\(websiteHost)"),
            URLQueryItem(name: "sz", value: "128")
        ]
        return components?.url
    }
}

/// 搜索引擎分类
enum SearchCategory: String, CaseIterable {
    case search = "搜索"
    case ai = "AI"
    case entertainment = "娱乐"
    case shopping = "购物"

    var displayName: String {
        return rawValue
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .ai: return "brain"
        case .entertainment: return "film"
        case .shopping: return "cart"
        }
    }
}

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

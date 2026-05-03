import Foundation

enum HiddenJavDBRandomMode: String, CaseIterable, Identifiable {
    case single
    case nine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return "随机 1 部"
        case .nine:
            return "随机 9 部"
        }
    }

    var requestCount: Int {
        switch self {
        case .single:
            return 1
        case .nine:
            return 9
        }
    }

    var loadingText: String {
        switch self {
        case .single:
            return "正在抓取随机影片..."
        case .nine:
            return "正在抓取随机 9 部..."
        }
    }
}

struct HiddenSpaceSettings: Equatable {
    var fourKHDRandomMode: HiddenRandomMode
    var javDBRandomMode: HiddenJavDBRandomMode
    var showJavDBDetailsByDefault: Bool
    var missAVDomain: String
}

extension Notification.Name {
    static let hiddenSpaceSettingsDidChange = Notification.Name("hiddenSpaceSettingsDidChange")
}

final class HiddenSpaceSettingsStore {
    static let shared = HiddenSpaceSettingsStore()

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let fourKHDRandomModeKey = "hiddenSpace.4khd.randomMode"
    private let javDBRandomModeKey = "hiddenSpace.javdb.randomMode"
    private let showJavDBDetailsByDefaultKey = "hiddenSpace.javdb.showDetailsByDefault"
    private let missAVDomainKey = "hiddenSpace.missav.domain"
    private let legacyMissAVDomainKey = "hiddenSpace.javdb.missDomain"

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    func load() -> HiddenSpaceSettings {
        let fourKHDRawValue = userDefaults.string(forKey: fourKHDRandomModeKey)
        let javDBRawValue = userDefaults.string(forKey: javDBRandomModeKey)
        let missAVDomain = migratedMissAVDomain()

        return HiddenSpaceSettings(
            fourKHDRandomMode: fourKHDRawValue.flatMap(HiddenRandomMode.init(rawValue:)) ?? .single,
            javDBRandomMode: javDBRawValue.flatMap(HiddenJavDBRandomMode.init(rawValue:)) ?? .single,
            showJavDBDetailsByDefault: userDefaults.object(forKey: showJavDBDetailsByDefaultKey) as? Bool ?? false,
            missAVDomain: missAVDomain
        )
    }

    func save(_ settings: HiddenSpaceSettings) {
        userDefaults.set(settings.fourKHDRandomMode.rawValue, forKey: fourKHDRandomModeKey)
        userDefaults.set(settings.javDBRandomMode.rawValue, forKey: javDBRandomModeKey)
        userDefaults.set(settings.showJavDBDetailsByDefault, forKey: showJavDBDetailsByDefaultKey)
        userDefaults.set(settings.missAVDomain, forKey: missAVDomainKey)
        userDefaults.removeObject(forKey: legacyMissAVDomainKey)
        notificationCenter.post(name: .hiddenSpaceSettingsDidChange, object: nil)
    }

    private func migratedMissAVDomain() -> String {
        if let currentValue = userDefaults.string(forKey: missAVDomainKey) {
            return currentValue
        }

        guard let legacyValue = userDefaults.string(forKey: legacyMissAVDomainKey) else {
            return ""
        }

        userDefaults.set(legacyValue, forKey: missAVDomainKey)
        userDefaults.removeObject(forKey: legacyMissAVDomainKey)
        return legacyValue
    }
}

enum HiddenMissAVDomainConfiguration {
    static let defaultHost = "missav.ws"
    static let fallbackHosts = [
        "missav.ws",
        "missav.live",
        "missav123.com",
        "missav888.com",
        "missav.ai"
    ]
    private static let legacyDefaultHosts: Set<String> = ["missav.ai"]

    static func currentHost() -> String {
        resolvedHost(from: HiddenSpaceSettingsStore.shared.load().missAVDomain)
    }

    static func currentBaseURL() -> URL {
        URL(string: "https://\(currentHost())")!
    }

    static func currentMovieTemplate() -> String {
        "\(currentBaseURL().absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/cn/{{code}}"
    }

    static func playbackCandidateURLs(for url: URL) -> [URL] {
        let hosts = deduplicatedHosts([
            url.host,
            currentHost(),
            defaultHost
        ] + fallbackHosts.map(Optional.some))

        let candidates = hosts.compactMap { replacingHost(of: url, with: $0) }
        return candidates.isEmpty ? [url] : candidates
    }

    static func resolvedHost(from rawValue: String?) -> String {
        guard let host = normalizedHost(from: rawValue) else {
            return defaultHost
        }
        return legacyDefaultHosts.contains(host) ? defaultHost : host
    }

    static func normalizedHost(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        if let port = components.port {
            return "\(host.lowercased()):\(port)"
        }

        return host.lowercased()
    }

    private static func deduplicatedHosts(_ hosts: [String?]) -> [String] {
        var deduplicated: [String] = []
        var seen = Set<String>()

        for host in hosts {
            guard let normalized = normalizedHost(from: host),
                  seen.insert(normalized).inserted else {
                continue
            }
            deduplicated.append(normalized)
        }

        return deduplicated
    }

    private static func replacingHost(of url: URL, with host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parts = host.split(separator: ":", maxSplits: 1).map(String.init)
        guard let hostname = parts.first, !hostname.isEmpty else {
            return nil
        }

        components.scheme = components.scheme ?? "https"
        components.host = hostname
        components.port = parts.dropFirst().first.flatMap(Int.init)
        return components.url
    }
}

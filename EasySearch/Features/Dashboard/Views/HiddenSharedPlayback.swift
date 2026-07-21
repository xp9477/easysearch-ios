import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit
import Foundation

struct HiddenSharedPlayerItem: Identifiable, Hashable {
    let resourceID: String
    let title: String
    let code: String
    let coverURL: URL?
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let startPositionSeconds: Double
    let markerPositions: [Double]
    let id = UUID()
}

struct HiddenPlaybackSaveResult {
    let savedPositionSeconds: Double
    let markerPositions: [Double]
    let undo: () -> [Double]
}

struct HiddenSharedWebPageItem: Identifiable, Hashable {
    let title: String
    let url: URL
    let id = UUID()
}

struct HiddenSharedSeekThumbnailConfiguration: Sendable {
    let pageURL: URL
    let durationSeconds: Double
    let picNum: Int
    let width: Int
    let height: Int
    let col: Int
    let row: Int
    let offsetX: Int
    let offsetY: Int
    let urls: [URL]
}

enum HiddenMissAVPlaybackTarget {
    case stream(URL, URL)
}

enum HiddenPlaybackIssueKind: Equatable {
    case javDBAgeConfirmation
    case missAVUnavailable
    case parsing
    case network
    case unknown
}

struct HiddenPlaybackIssuePresentation: Equatable {
    let kind: HiddenPlaybackIssueKind
    let title: String
    let message: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let systemImage: String
    let tone: ESStatusPill.Tone

    init(error: Error) {
        let nsError = error as NSError
        self = Self(
            message: error.localizedDescription,
            errorCode: nsError.code,
            userInfo: nsError.userInfo
        )
    }

    init(message: String, errorCode: Int? = nil, userInfo: [String: Any] = [:]) {
        let statusCode = userInfo["HTTPStatusCode"] as? Int
        let normalized = message.uppercased()

        if errorCode == -35 || message.contains("年龄确认") || message.contains("18+") {
            kind = .javDBAgeConfirmation
            title = "需要年龄确认"
            self.message = "完成网页确认后，返回这里重试即可继续。"
            primaryActionTitle = "已确认，重试"
            secondaryActionTitle = "打开确认页"
            systemImage = "checkmark.shield"
            tone = .accent
        } else if statusCode == 451 || normalized.contains("451") || normalized.contains("MISSAV 页面请求失败") {
            kind = .missAVUnavailable
            title = "当前域名不可用"
            self.message = "已尝试备用域名。仍失败时可切换 MissAV 域名后重试。"
            primaryActionTitle = "重试"
            secondaryActionTitle = "修改域名"
            systemImage = "network.slash"
            tone = .warning
        } else if message.contains("解析") || message.contains("未解析") {
            kind = .parsing
            title = "页面解析失败"
            self.message = "页面结构可能已变化，请稍后重试。"
            primaryActionTitle = "重试"
            secondaryActionTitle = nil
            systemImage = "doc.text.magnifyingglass"
            tone = .warning
        } else if message.contains("网络") || message.contains("请求") || message.contains("连接") || errorCode == NSURLErrorNotConnectedToInternet {
            kind = .network
            title = "页面请求失败"
            self.message = message
            primaryActionTitle = "重试"
            secondaryActionTitle = nil
            systemImage = "wifi.exclamationmark"
            tone = .warning
        } else {
            kind = .unknown
            title = "播放准备失败"
            self.message = message
            primaryActionTitle = "重试"
            secondaryActionTitle = nil
            systemImage = "exclamationmark.triangle"
            tone = .warning
        }
    }
}

extension HiddenMissAVDomainConfiguration {
    static func currentLocalizedBaseURL(locale: String = "cn") -> URL {
        currentBaseURL().appendingPathComponent(locale)
    }

    static func currentMovieURL(forCode rawCode: String) -> URL? {
        let normalizedCode = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedCode.isEmpty else { return nil }
        return currentLocalizedBaseURL().appendingPathComponent(normalizedCode)
    }

    static func currentURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        let sanitized = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return currentBaseURL().appendingPathComponent(sanitized)
    }
}

enum HiddenMissAVHTMLParser {
    static func cleanTitle(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return text
    }

    static func regexFirstCapture(pattern: String, in text: String, dotMatchesLine: Bool) -> String? {
        regexCaptureAll(pattern: pattern, in: text, dotMatchesLine: dotMatchesLine).first
    }

    static func regexCaptureAll(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    static func regexCapturePairs(pattern: String, in text: String, dotMatchesLine: Bool) -> [(String, String)] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            return (String(text[firstRange]), String(text[secondRange]))
        }
    }

    static func regexFirstGroups(pattern: String, in text: String, dotMatchesLine: Bool) -> [String]? {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    static func regexFullMatches(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let captureRange = Range(match.range, in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    static func normalizedExternalURL(from raw: String, relativeTo baseURL: URL) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if decoded.hasPrefix("//") {
            return URL(string: "https:" + decoded)
        }
        if decoded.hasPrefix("/") {
            return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: decoded)
    }
}

enum HiddenMissAVPlaybackResolver {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: configuration)
    }()

    static func resolvePlaybackTarget(pageURL: URL) async throws -> HiddenMissAVPlaybackTarget {
        let resolvedStream = try await resolvePrimaryStream(pageURL: pageURL)
        return .stream(resolvedStream.streamURL, resolvedStream.refererURL)
    }

    static func resolvePrimaryStreamURL(pageURL: URL) async throws -> URL {
        try await resolvePrimaryStream(pageURL: pageURL).streamURL
    }

    static func resolveSeekThumbnailConfiguration(pageURL: URL) async -> HiddenSharedSeekThumbnailConfiguration? {
        for candidateURL in HiddenMissAVDomainConfiguration.playbackCandidateURLs(for: pageURL) {
            guard let html = try? await fetchHTML(from: candidateURL),
                  let configuration = extractSeekThumbnailConfiguration(from: html, pageURL: candidateURL) else {
                continue
            }
            return configuration
        }
        return nil
    }

    static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = true
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "HiddenMissAVPlaybackResolver",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "请求返回异常"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "HiddenMissAVPlaybackResolver",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: missAVRequestErrorMessage(for: httpResponse.statusCode),
                    "HTTPStatusCode": httpResponse.statusCode
                ]
            )
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? ""
        guard !html.isEmpty else {
            throw NSError(
                domain: "HiddenMissAVPlaybackResolver",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "页面解析失败"]
            )
        }

        return html
    }

    private static func resolvePrimaryStream(pageURL: URL) async throws -> (streamURL: URL, refererURL: URL) {
        var lastError: Error?

        for candidateURL in HiddenMissAVDomainConfiguration.playbackCandidateURLs(for: pageURL) {
            do {
                let html = try await fetchHTML(from: candidateURL)
                if let streamURL = extractPrimaryStreamURL(from: html, pageURL: candidateURL) {
                    return (streamURL, candidateURL)
                }

                lastError = NSError(
                    domain: "HiddenMissAVPlaybackResolver",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "未解析到 MISSAV 视频流"]
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "HiddenMissAVPlaybackResolver",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "MISSAV 页面请求失败"]
        )
    }

    private static func missAVRequestErrorMessage(for statusCode: Int) -> String {
        if statusCode == 451 {
            return "当前 MISSAV 域名不可用（451），已尝试备用域名"
        }
        return "页面请求失败（\(statusCode)）"
    }

    private static func extractSeekThumbnailConfiguration(
        from html: String,
        pageURL: URL
    ) -> HiddenSharedSeekThumbnailConfiguration? {
        guard let block = HiddenMissAVHTMLParser.regexFirstCapture(
            pattern: #"thumbnail:\s*\{(.*?)\}\s*,\s*keyboard:"#,
            in: html,
            dotMatchesLine: true
        ) else {
            return nil
        }

        if let enabled = HiddenMissAVHTMLParser.regexFirstCapture(
            pattern: #"\benabled:\s*(true|false)"#,
            in: block,
            dotMatchesLine: false
        )?.lowercased(), enabled == "false" {
            return nil
        }

        guard let picNum = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\bpic_num:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let width = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\bwidth:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let height = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\bheight:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let col = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\bcol:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let row = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\brow:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let durationSeconds = Double(
                HiddenMissAVHTMLParser.regexFirstCapture(
                    pattern: #"<meta\s+property=["']og:video:duration["']\s+content=["'](\d+(?:\.\d+)?)["']"#,
                    in: html,
                    dotMatchesLine: true
                ) ?? ""
              ) else {
            return nil
        }

        let offsetX = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\boffsetX:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? "") ?? 0
        let offsetY = Int(HiddenMissAVHTMLParser.regexFirstCapture(pattern: #"\boffsetY:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? "") ?? 0
        let rawURLs = HiddenMissAVHTMLParser.regexCaptureAll(
            pattern: #""(https?:\\?/\\?/[^"]+)""#,
            in: block,
            dotMatchesLine: true
        )

        let urls = rawURLs
            .map {
                $0
                    .replacingOccurrences(of: #"\/"#, with: "/")
                    .replacingOccurrences(of: #"\\u0026"#, with: "&")
            }
            .compactMap { HiddenMissAVHTMLParser.normalizedExternalURL(from: $0, relativeTo: pageURL) }

        guard picNum > 0,
              width > 0,
              height > 0,
              col > 0,
              row > 0,
              durationSeconds > 0,
              !urls.isEmpty else {
            return nil
        }

        return HiddenSharedSeekThumbnailConfiguration(
            pageURL: pageURL,
            durationSeconds: durationSeconds,
            picNum: picNum,
            width: width,
            height: height,
            col: col,
            row: row,
            offsetX: offsetX,
            offsetY: offsetY,
            urls: urls
        )
    }

    private static func extractPrimaryStreamURL(from html: String, pageURL: URL) -> URL? {
        var candidates: [String] = []

        let direct = HiddenMissAVHTMLParser.regexCaptureAll(
            pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
            in: html,
            dotMatchesLine: true
        )
        candidates.append(contentsOf: direct)

        let decodedBlocks = decodeEvalBlocks(from: html)
        for block in decodedBlocks {
            let urls = HiddenMissAVHTMLParser.regexCaptureAll(
                pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
                in: block,
                dotMatchesLine: true
            )
            candidates.append(contentsOf: urls)
        }

        let normalized = candidates.compactMap { HiddenMissAVHTMLParser.normalizedExternalURL(from: $0, relativeTo: pageURL) }
        return prioritizedStreamCandidates(normalized).first
    }

    private static func decodeEvalBlocks(from html: String) -> [String] {
        let payloads = HiddenMissAVHTMLParser.regexFirstGroups(
            pattern: #"eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.+?)',(\d+),(\d+),'(.+?)'\.split\('\|'\),0,\{\}\)\)"#,
            in: html,
            dotMatchesLine: true
        )

        guard let payloads, payloads.count == 4,
              let base = Int(payloads[1]),
              let count = Int(payloads[2]) else {
            return []
        }

        let dictionary = payloads[3].split(separator: "|").map(String.init)
        return [unpackPAckerPayload(payloads[0], base: base, count: count, dictionary: dictionary)]
    }

    private static func unpackPAckerPayload(_ payload: String, base: Int, count: Int, dictionary: [String]) -> String {
        guard base >= 2 else { return payload }

        var result = payload
        if count > 0 {
            for index in stride(from: count - 1, through: 0, by: -1) {
                guard index < dictionary.count else { continue }
                let replacement = dictionary[index]
                if replacement.isEmpty {
                    continue
                }
                let token = toBaseString(index, base: base)
                let escapedToken = NSRegularExpression.escapedPattern(for: token)
                result = result.replacingOccurrences(
                    of: "\\b\(escapedToken)\\b",
                    with: replacement,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        return result.replacingOccurrences(of: #"\'"#, with: "'")
    }

    private static func toBaseString(_ value: Int, base: Int) -> String {
        guard base >= 2, base <= 36 else {
            return "\(value)"
        }
        if value == 0 {
            return "0"
        }

        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var number = value
        var output = ""
        while number > 0 {
            let remainder = number % base
            output = String(digits[remainder]) + output
            number /= base
        }
        return output
    }

    private static func prioritizedStreamCandidates(_ urls: [URL]) -> [URL] {
        var unique: [URL] = []
        var seen = Set<String>()
        for url in urls {
            if seen.insert(url.absoluteString).inserted {
                unique.append(url)
            }
        }

        let filtered = unique.filter { url in
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            guard path.hasSuffix(".m3u8") else { return false }
            return host.contains("surrit.com") || path.contains("/playlist")
        }

        let playlistFirst = filtered.sorted { lhs, rhs in
            let lhsPath = lhs.path.lowercased()
            let rhsPath = rhs.path.lowercased()
            let lhsScore = (lhsPath.contains("/playlist") ? 3 : 0) + (lhsPath.contains("/video/") ? 1 : 0)
            let rhsScore = (rhsPath.contains("/playlist") ? 3 : 0) + (rhsPath.contains("/video/") ? 1 : 0)
            return lhsScore > rhsScore
        }

        return playlistFirst.isEmpty ? unique : playlistFirst
    }
}

private enum HiddenSharedPlaybackTimeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct HiddenSharedVideoPlayerView: View {
    private enum SurfaceInteractionMode {
        case undecided
        case brightnessAdjusting
    }

    let item: HiddenSharedPlayerItem
    let onSavePlaybackPosition: (HiddenSharedPlayerItem, Double) -> HiddenPlaybackSaveResult
    var onPlaybackClosed: ((HiddenSharedPlayerItem, Double) -> Void)? = nil
    var showsPlaybackSaveControls = true

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var appliedPlaybackRate: Float = 1.0
    @State private var isMuted = true
    @State private var showUnmuteConfirm = false
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var isProgrammaticSeeking = false
    @State private var controlsVisible = true
    @State private var controlsAutoHideTask: Task<Void, Never>?
    @State private var seekTask: Task<Void, Never>?
    @State private var favoriteSaveResetTask: Task<Void, Never>?
    @State private var recentlySavedResult: HiddenPlaybackSaveResult?
    @State private var recentlySavedPosition: Double?
    @State private var favoriteUndoCountdown = 0
    @State private var isTemporaryBoostActive = false
    @State private var pendingBoostActivationTask: Task<Void, Never>?
    @State private var activeTouchStartedAt: Date?
    @State private var activeTouchStartLocation: CGPoint?
    @State private var didActivateTouchBoost = false
    @State private var surfaceInteractionMode: SurfaceInteractionMode = .undecided
    @State private var touchStartBrightness: CGFloat?
    @State private var displayedBrightness: CGFloat?
    @State private var didApplyInitialStartPosition = false
    @State private var markerPositions: [Double]

    private let normalPlaybackRate: Float = 1.0
    private let temporaryBoostRate: Float = 2.0
    private let boostActivationDelay: TimeInterval = 1.0
    private let boostActivationMaximumDistance: CGFloat = 36
    private let tapMaximumDistance: CGFloat = 12
    private let brightnessGestureLeadingRegionRatio: CGFloat = 0.42
    private let brightnessActivationMinimumDistance: CGFloat = 14

    init(
        item: HiddenSharedPlayerItem,
        onSavePlaybackPosition: @escaping (HiddenSharedPlayerItem, Double) -> HiddenPlaybackSaveResult,
        onPlaybackClosed: ((HiddenSharedPlayerItem, Double) -> Void)? = nil,
        showsPlaybackSaveControls: Bool = true
    ) {
        self.item = item
        self.onSavePlaybackPosition = onSavePlaybackPosition
        self.onPlaybackClosed = onPlaybackClosed
        self.showsPlaybackSaveControls = showsPlaybackSaveControls

        let headers: [String: String] = [
            "Referer": item.refererURL.absoluteString,
            "Origin": "\(item.refererURL.scheme ?? "https")://\(item.refererURL.host ?? HiddenMissAVDomainConfiguration.currentHost())",
            "User-Agent": HiddenMissAVPlaybackResolver.userAgent
        ]
        let asset = AVURLAsset(
            url: item.streamURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ]
        )
        let playerItem = AVPlayerItem(asset: asset)
        _player = State(initialValue: AVPlayer(playerItem: playerItem))
        _markerPositions = State(initialValue: Self.normalizedMarkerPositions(item.markerPositions))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HiddenSharedAVPlayerContainerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            GeometryReader { proxy in
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(videoSurfaceGesture(in: proxy.size))
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topOverlay
                Spacer()
                centerControls
                Spacer()
                bottomOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            if shouldShowPlaybackRateHUD {
                playbackRateHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if shouldShowBrightnessHUD {
                brightnessHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowPlaybackRateHUD)
        .animation(.easeInOut(duration: 0.18), value: shouldShowBrightnessHUD)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            configureAudioSession()
            player.isMuted = true
            applyPlayerRateImmediately(normalPlaybackRate)
            player.playImmediately(atRate: appliedPlaybackRate)
            syncPlaybackState()
            scheduleControlsAutoHide()
        }
        .onDisappear {
            onPlaybackClosed?(item, resolvedCurrentPlaybackTime)
            seekTask?.cancel()
            controlsAutoHideTask?.cancel()
            favoriteSaveResetTask?.cancel()
            pendingBoostActivationTask?.cancel()
            isTemporaryBoostActive = false
            displayedBrightness = nil
            player.pause()
        }
        .task(id: item.id) {
            await applyInitialStartPositionIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            syncPlaybackState()
        }
        .alert("开启声音", isPresented: $showUnmuteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认") {
                isMuted = false
                player.isMuted = false
                scheduleControlsAutoHide()
            }
        } message: {
            Text("播放器默认静音。确认后将开启声音。")
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            playerBadge(text: item.sourceName)
                            if !item.code.isEmpty {
                                playerBadge(text: item.code)
                            }
                            playerBadge(text: formattedRate(appliedPlaybackRate))
                            if showsPlaybackSaveControls, !markerPositions.isEmpty {
                                playerBadge(text: "\(markerPositions.count) 个点")
                            }
                            if isMuted {
                                playerBadge(text: "静音")
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, ESUI.Space.md)
                .padding(.top, ESUI.Space.md)
            }
        }
        .allowsHitTesting(true)
    }

    private var centerControls: some View {
        HStack(spacing: 26) {
            largeCircleButton(systemImage: "gobackward.15") {
                seek(by: -15)
            }

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
            }
            .buttonStyle(.plain)

            largeCircleButton(systemImage: "goforward.15") {
                seek(by: 15)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.2), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 248)
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(formattedDuration(isScrubbing ? scrubPosition : currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text(formattedDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubPosition : currentTime },
                                set: { scrubPosition = $0 }
                            ),
                            in: 0...max(duration, 1),
                            onEditingChanged: handleScrub(editing:)
                        )
                        .tint(.white)
                        .overlay {
                            HiddenSharedPlaybackMarkerTrackView(
                                markerPositions: markerPositions,
                                duration: duration
                            )
                            .padding(.horizontal, ESUI.Space.sm)
                            .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 10) {
                        compactSeekButton(title: "-1m", systemImage: "backward.fill") {
                            seek(by: -60)
                        }
                        compactSeekButton(title: "+1m", systemImage: "forward.fill") {
                            seek(by: 60)
                        }
                    }

                    HStack(spacing: 10) {
                        if showsPlaybackSaveControls {
                            Button {
                                saveFavoritePlaybackPosition()
                            } label: {
                                Label(recentlySavedResult == nil ? "喜欢此处" : "已记录", systemImage: recentlySavedResult == nil ? "heart.fill" : "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            toggleMute()
                        } label: {
                            Label(isMuted ? "开启声音" : "静音", systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, ESUI.Space.md)
                                .padding(.vertical, ESUI.Space.sm)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if showsPlaybackSaveControls, let recentlySavedPosition, recentlySavedResult != nil {
                        HStack(spacing: 10) {
                            Text("已记录 \(HiddenSharedPlaybackTimeFormatter.string(from: recentlySavedPosition))，\(max(favoriteUndoCountdown, 1)) 秒内可撤回")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.76))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("撤回") {
                                undoFavoritePlaybackSave()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, ESUI.Space.sm)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func playerBadge(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, ESUI.Space.xs)
            .padding(.vertical, ESUI.Space.xxs)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func largeCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var shouldShowPlaybackRateHUD: Bool {
        abs(appliedPlaybackRate - normalPlaybackRate) > 0.05
    }

    private var playbackRateHUD: some View {
        VStack {
            Text(formattedRate(appliedPlaybackRate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isTemporaryBoostActive ? Color.orange.opacity(0.86) : Color.black.opacity(0.56))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            Spacer()
        }
        .padding(.top, controlsVisible ? 94 : 54)
        .allowsHitTesting(false)
    }

    private var shouldShowBrightnessHUD: Bool {
        displayedBrightness != nil
    }

    private var brightnessHUD: some View {
        VStack {
            Spacer()

            HStack {
                VStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(formattedBrightness(displayedBrightness ?? UIScreen.main.brightness))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)

                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))

                            Capsule()
                                .fill(Color.white)
                                .frame(height: max(12, proxy.size.height * (displayedBrightness ?? UIScreen.main.brightness)))
                        }
                    }
                    .frame(width: 8, height: 88)
                }
                .padding(.horizontal, ESUI.Space.md)
                .padding(.vertical, ESUI.Space.md)
                .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: ESUI.Space.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ESUI.Space.lg, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.leading, ESUI.Space.lg)
            .padding(.bottom, controlsVisible ? 168 : 84)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func compactSeekButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            controlsAutoHideTask?.cancel()
        } else {
            player.playImmediately(atRate: appliedPlaybackRate)
            isPlaying = true
            scheduleControlsAutoHide()
        }
    }

    private func toggleMute() {
        if isMuted {
            showUnmuteConfirm = true
        } else {
            isMuted = true
            player.isMuted = true
            scheduleControlsAutoHide()
        }
    }

    private func seek(by seconds: Double) {
        let baseTime = resolvedCurrentPlaybackTime
        guard baseTime.isFinite else { return }

        var target = max(0, baseTime + seconds)
        if duration.isFinite, duration > 0 {
            target = min(target, duration)
        }

        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
        showControlsTemporarily()
    }

    private func formattedRate(_ value: Float) -> String {
        let roundedValue = round(value)
        if abs(value - roundedValue) < 0.05 {
            return "\(Int(roundedValue))x"
        }
        return String(format: "%.1fx", value)
    }

    private func formattedBrightness(_ value: CGFloat) -> String {
        "\(Int(round(value * 100)))%"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        HiddenSharedPlaybackTimeFormatter.string(from: seconds)
    }

    private func handleScrub(editing: Bool) {
        isScrubbing = editing

        if editing {
            seekTask?.cancel()
            isProgrammaticSeeking = false
            controlsAutoHideTask?.cancel()
            scrubPosition = currentTime
            return
        }

        let target = normalizedPlaybackTime(scrubPosition)
        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
    }

    private func syncPlaybackState() {
        let latestDuration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        if latestDuration.isFinite, latestDuration > 0 {
            duration = latestDuration
        }

        let latestTime = CMTimeGetSeconds(player.currentTime())
        if latestTime.isFinite, !isProgrammaticSeeking {
            let normalizedTime = normalizedPlaybackTime(latestTime)
            currentTime = normalizedTime
            if !isScrubbing {
                scrubPosition = normalizedTime
            }
        }

        isPlaying = player.timeControlStatus == .playing
    }

    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }

        if controlsVisible {
            scheduleControlsAutoHide()
        } else {
            controlsAutoHideTask?.cancel()
        }
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        guard isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }

        controlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    @MainActor
    private func applyInitialStartPositionIfNeeded() async {
        guard !didApplyInitialStartPosition, item.startPositionSeconds > 0.5 else { return }
        didApplyInitialStartPosition = true

        let targetTime = CMTime(seconds: item.startPositionSeconds, preferredTimescale: 600)
        isProgrammaticSeeking = true
        for _ in 0..<20 {
            if Task.isCancelled {
                isProgrammaticSeeking = false
                return
            }

            if player.currentItem?.status == .readyToPlay {
                await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
                isProgrammaticSeeking = false
                return
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
        isProgrammaticSeeking = false
    }

    private func saveFavoritePlaybackPosition() {
        let latestTime = isScrubbing ? scrubPosition : currentTime
        let positionSeconds = max(0, latestTime.isFinite ? latestTime : CMTimeGetSeconds(player.currentTime()))
        let saveResult = onSavePlaybackPosition(item, positionSeconds)
        markerPositions = Self.normalizedMarkerPositions(saveResult.markerPositions)
        recentlySavedResult = saveResult
        recentlySavedPosition = saveResult.savedPositionSeconds
        scheduleFavoriteUndoCountdown()
        showControlsTemporarily()
    }

    private var targetPlaybackRate: Float {
        isTemporaryBoostActive ? temporaryBoostRate : normalPlaybackRate
    }

    private var resolvedCurrentPlaybackTime: Double {
        let candidate = isScrubbing ? scrubPosition : currentTime
        if candidate.isFinite {
            return normalizedPlaybackTime(candidate)
        }
        return normalizedPlaybackTime(CMTimeGetSeconds(player.currentTime()))
    }

    private func normalizedPlaybackTime(_ value: Double) -> Double {
        let nonNegativeValue = max(0, value.isFinite ? value : 0)
        guard duration.isFinite, duration > 0 else { return nonNegativeValue }
        return min(nonNegativeValue, duration)
    }

    private func updateDisplayedPlaybackPosition(to value: Double) {
        let normalizedValue = normalizedPlaybackTime(value)
        currentTime = normalizedValue
        scrubPosition = normalizedValue
    }

    private func seekPlayer(to target: Double) {
        seekTask?.cancel()
        isProgrammaticSeeking = true

        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        let resumePlayback = isPlaying
        let rateAfterSeek = appliedPlaybackRate

        seekTask = Task { @MainActor in
            await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }

            updateDisplayedPlaybackPosition(to: target)
            isProgrammaticSeeking = false

            if resumePlayback {
                player.playImmediately(atRate: rateAfterSeek)
            }
            scheduleControlsAutoHide()
        }
    }

    private func videoSurfaceGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleVideoSurfaceTouchChanged(value, in: size)
            }
            .onEnded { value in
                handleVideoSurfaceTouchEnded(value)
            }
    }

    private func applyPlayerRateImmediately(_ rate: Float) {
        let normalizedRate = max(0.25, rate)
        appliedPlaybackRate = normalizedRate
        player.defaultRate = normalizedRate
        if player.timeControlStatus == .playing {
            player.rate = normalizedRate
        }
    }

    private func beginTemporarySpeedBoost() {
        guard !isTemporaryBoostActive else { return }
        isTemporaryBoostActive = true
        applyPlayerRateImmediately(targetPlaybackRate)
    }

    private func endTemporarySpeedBoostIfNeeded() {
        guard isTemporaryBoostActive else { return }
        isTemporaryBoostActive = false
        applyPlayerRateImmediately(targetPlaybackRate)
    }

    private func handleVideoSurfaceTouchChanged(_ value: DragGesture.Value, in size: CGSize) {
        if activeTouchStartedAt == nil {
            activeTouchStartedAt = Date()
            activeTouchStartLocation = value.startLocation
            surfaceInteractionMode = .undecided
            touchStartBrightness = UIScreen.main.brightness
            displayedBrightness = nil
            didActivateTouchBoost = false
            schedulePendingBoostActivation()
            return
        }

        guard let touchStartLocation = activeTouchStartLocation else { return }
        let horizontalDistance = abs(value.location.x - touchStartLocation.x)
        let verticalDistance = abs(value.location.y - touchStartLocation.y)

        if shouldBeginBrightnessAdjustment(
            from: touchStartLocation,
            in: size,
            horizontalDistance: horizontalDistance,
            verticalDistance: verticalDistance
        ) {
            beginBrightnessAdjustment()
        }

        if surfaceInteractionMode == .brightnessAdjusting {
            updateBrightness(with: value, in: size)
            return
        }

        let travelDistance = distanceBetween(value.location, and: touchStartLocation)

        if travelDistance > boostActivationMaximumDistance {
            pendingBoostActivationTask?.cancel()
            if isTemporaryBoostActive {
                endTemporarySpeedBoostIfNeeded()
            }
        }
    }

    private func handleVideoSurfaceTouchEnded(_ value: DragGesture.Value) {
        let touchStartedAt = activeTouchStartedAt
        let touchStartLocation = activeTouchStartLocation ?? value.startLocation
        let pressDuration = touchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let travelDistance = distanceBetween(value.location, and: touchStartLocation)
        let shouldToggleControls = surfaceInteractionMode == .undecided && !didActivateTouchBoost && pressDuration < boostActivationDelay && travelDistance <= tapMaximumDistance

        pendingBoostActivationTask?.cancel()
        activeTouchStartedAt = nil
        activeTouchStartLocation = nil
        touchStartBrightness = nil
        displayedBrightness = nil
        surfaceInteractionMode = .undecided
        didActivateTouchBoost = false

        endTemporarySpeedBoostIfNeeded()

        if shouldToggleControls {
            toggleControlsVisibility()
        }
    }

    private func schedulePendingBoostActivation() {
        pendingBoostActivationTask?.cancel()
        pendingBoostActivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(boostActivationDelay * 1_000_000_000))
            guard !Task.isCancelled, activeTouchStartedAt != nil, !didActivateTouchBoost else { return }
            didActivateTouchBoost = true
            beginTemporarySpeedBoost()
        }
    }

    private func distanceBetween(_ lhs: CGPoint, and rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func shouldBeginBrightnessAdjustment(
        from startLocation: CGPoint,
        in size: CGSize,
        horizontalDistance: CGFloat,
        verticalDistance: CGFloat
    ) -> Bool {
        guard surfaceInteractionMode == .undecided else { return false }
        guard startLocation.x <= size.width * brightnessGestureLeadingRegionRatio else { return false }
        guard verticalDistance >= brightnessActivationMinimumDistance else { return false }
        return verticalDistance > horizontalDistance * 1.2
    }

    private func beginBrightnessAdjustment() {
        pendingBoostActivationTask?.cancel()
        endTemporarySpeedBoostIfNeeded()
        surfaceInteractionMode = .brightnessAdjusting
    }

    private func updateBrightness(with value: DragGesture.Value, in size: CGSize) {
        guard let startLocation = activeTouchStartLocation, let startBrightness = touchStartBrightness else { return }
        let height = max(size.height, 1)
        let delta = (startLocation.y - value.location.y) / height
        let nextBrightness = min(max(startBrightness + delta, 0), 1)
        UIScreen.main.brightness = nextBrightness
        displayedBrightness = nextBrightness
    }

    private func scheduleFavoriteUndoCountdown() {
        favoriteSaveResetTask?.cancel()
        favoriteUndoCountdown = 3

        favoriteSaveResetTask = Task { @MainActor in
            for remaining in stride(from: 3, through: 1, by: -1) {
                favoriteUndoCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            recentlySavedResult = nil
            recentlySavedPosition = nil
            favoriteUndoCountdown = 0
        }
    }

    private func undoFavoritePlaybackSave() {
        guard let saveResult = recentlySavedResult else { return }
        markerPositions = Self.normalizedMarkerPositions(saveResult.undo())
        recentlySavedResult = nil
        recentlySavedPosition = nil
        favoriteUndoCountdown = 0
        favoriteSaveResetTask?.cancel()
        showControlsTemporarily()
    }

    private static func normalizedMarkerPositions(_ positions: [Double]) -> [Double] {
        let sorted = positions
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        var normalized: [Double] = []
        normalized.reserveCapacity(sorted.count)

        for position in sorted {
            if let last = normalized.last, abs(last - position) < 2 {
                continue
            }
            normalized.append(position)
        }

        return normalized
    }
}

private struct HiddenSharedPlaybackMarkerTrackView: View {
    let markerPositions: [Double]
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            if duration.isFinite, duration > 0 {
                ForEach(Array(normalizedFractions.enumerated()), id: \.offset) { _, fraction in
                    Capsule(style: .continuous)
                        .fill(Color.pink.opacity(0.95))
                        .frame(width: 3, height: 10)
                        .shadow(color: Color.black.opacity(0.32), radius: 2, y: 1)
                        .position(
                            x: max(1.5, min(geometry.size.width - 1.5, geometry.size.width * fraction)),
                            y: geometry.size.height / 2
                        )
                }
            }
        }
    }

    private var normalizedFractions: [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return markerPositions.compactMap { position in
            guard position.isFinite, position >= 0 else { return nil }
            return min(max(position / duration, 0), 1)
        }
    }
}

private final class HiddenSharedWebViewState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading = true
    @Published var pageTitle = ""
    @Published var currentURL: URL?
    @Published var reloadToken = UUID()
}

struct HiddenSharedWebPageView: View {
    let item: HiddenSharedWebPageItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var webState = HiddenSharedWebViewState()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            HiddenSharedWebBrowserView(url: item.url, state: webState)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 136)
                .overlay(alignment: .top) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(webState.pageTitle.nonEmpty ?? webState.currentURL?.host ?? item.url.host ?? item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                webState.reloadToken = UUID()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            Link(destination: webState.currentURL ?? item.url) {
                                Image(systemName: "safari")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, ESUI.Space.md)
                        .padding(.top, ESUI.Space.md)

                        if webState.isLoading {
                            ProgressView(value: webState.progress)
                                .tint(.white)
                                .padding(.horizontal, ESUI.Space.md)
                        }
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

private struct HiddenSharedWebBrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: HiddenSharedWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = HiddenMissAVPlaybackResolver.userAgent
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.attachObservers(to: webView)
        context.coordinator.load(url: url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURLString != url.absoluteString {
            context.coordinator.load(url: url, in: webView)
        }

        if context.coordinator.reloadToken != state.reloadToken {
            context.coordinator.reloadToken = state.reloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: HiddenSharedWebViewState
        var loadedURLString: String?
        var reloadToken = UUID()
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(state: HiddenSharedWebViewState) {
            self.state = state
        }

        func attachObservers(to webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.progress = webView.estimatedProgress
                }
            }
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.pageTitle = webView.title ?? ""
                }
            }
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.currentURL = webView.url
                }
            }
        }

        func load(url: URL, in webView: WKWebView) {
            loadedURLString = url.absoluteString
            state.isLoading = true
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue(HiddenMissAVPlaybackResolver.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            webView.load(request)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.progress = 1
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }
    }
}

private struct HiddenSharedAVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

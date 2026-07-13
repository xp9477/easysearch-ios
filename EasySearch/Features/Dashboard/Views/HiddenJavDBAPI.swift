import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

struct HiddenJavDBMovieDetail: Hashable {
    let code: String
    let title: String
    let actresses: [String]
    let releaseDate: String?
    let durationMinutes: Int?
    let studio: String?
    let otherActressMovies: [HiddenJavDBMovie]
    let recommendedMovies: [HiddenJavDBMovie]

    var actressesText: String {
        actresses.isEmpty ? "未知" : actresses.joined(separator: " / ")
    }

    var durationText: String {
        guard let durationMinutes else { return "未知" }
        return "\(durationMinutes) 分钟"
    }
}

enum HiddenPlaybackTimeFormatter {
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

struct HiddenJavDBPreviewImage: Identifiable, Hashable {
    let index: Int
    let urls: [URL]

    var id: String {
        guard !urls.isEmpty else { return "empty-\(index)" }
        let safeIndex = min(max(index, 0), urls.count - 1)
        return "\(safeIndex)-\(urls[safeIndex].absoluteString)"
    }
}

struct HiddenJavDBSeekThumbnailConfiguration: Sendable {
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

enum HiddenJavDBWatchPlaybackTarget {
    case stream(URL, URL)
    case webPage(URL)
}

enum HiddenJavDBAPI {
    private static let listingURL = URL(string: "https://javdb.com/?vft=1&vst=1")!
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: configuration)
    }()

    static func fetchRandomMovie(knownTotalPages: Int?) async throws -> (movie: HiddenJavDBMovie, totalPages: Int) {
        let totalPages = try await resolveTotalPages(knownTotalPages: knownTotalPages)

        var attempts = 0
        while attempts < 8 {
            attempts += 1
            let randomPage = Int.random(in: 1...max(totalPages, 1))
            let pageURL = listURL(page: randomPage)
            let html = try await fetchHTML(from: pageURL)
            let movies = parseMovies(from: html, baseURL: pageURL)
            if let movie = movies.randomElement() {
                return (movie, totalPages)
            }
        }

        throw NSError(
            domain: "HiddenJavDBAPI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "没有解析到可用影片，请重试"]
        )
    }

    static func fetchMovieImages(movieURL: URL) async throws -> [URL] {
        let html = try await fetchHTML(from: movieURL)
        let imageURLs = parseMovieImages(from: html)
        guard !imageURLs.isEmpty else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "没有拿到截图列表"]
            )
        }
        return imageURLs
    }

    static func fetchMovieDetail(for movie: HiddenJavDBMovie) async throws -> HiddenJavDBMovieDetail {
        let html = try await fetchHTML(from: movie.url)

        let parsedTitle = firstNonEmpty([
            regexFirstCapture(pattern: #"<strong[^>]*class="[^"]*current-title[^"]*"[^>]*>(.*?)</strong>"#, in: html, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<h2[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)</h2>"#, in: html, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<title>(.*?)</title>"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let parsedCode = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["番號", "番号", "Code", "ID"], in: html),
            regexFirstCapture(pattern: #"<span[^>]*class="[^"]*video-id[^"]*"[^>]*>(.*?)</span>"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let actresses = parseActorNames(from: html)
        let releaseDate = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["日期", "発行日", "Release Date"], in: html),
            regexFirstCapture(pattern: #"(20\d{2}[-/\.]\d{1,2}[-/\.]\d{1,2})"#, in: html, dotMatchesLine: false)
        ]).map(cleanTitle)

        let durationRaw = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["片長", "长度", "Duration", "Length"], in: html),
            regexFirstCapture(pattern: #"(\d{2,3})\s*(?:分鐘|分钟|min)"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let durationMinutes: Int?
        if let durationRaw {
            durationMinutes = Int(regexFirstCapture(pattern: #"(\d{2,3})"#, in: durationRaw, dotMatchesLine: false) ?? "")
        } else {
            durationMinutes = nil
        }

        let studio = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["片商", "メーカー", "Studio", "Maker"], in: html),
            extractMetadataValue(labelKeywords: ["发行", "Publisher", "Label"], in: html)
        ]).map(cleanTitle)
        let otherActressMovies = parseRelatedMovies(
            from: html,
            titleKeywords: [
                "TA(們)還出演過",
                "TA(们)还出演过",
                "TA(們)還演過",
                "TA(们)还演过",
                "她們還演出過",
                "她们还演出过",
                "她還演出過",
                "她还演出过",
                "她們還演過",
                "她们还演过",
                "她還演過",
                "她还演过"
            ],
            excluding: movie,
            baseURL: movie.url
        )
        let recommendedMovies = parseRelatedMovies(
            from: html,
            titleKeywords: ["你可能也喜歡", "你可能也喜欢", "可能你也喜歡", "可能你也喜欢", "猜你喜歡", "猜你喜欢", "you may also like"],
            excluding: movie,
            baseURL: movie.url
        )

        return HiddenJavDBMovieDetail(
            code: parsedCode?.nonEmpty ?? movie.code,
            title: parsedTitle?.nonEmpty ?? movie.displayTitle,
            actresses: actresses.isEmpty ? movie.actresses : actresses,
            releaseDate: releaseDate?.nonEmpty,
            durationMinutes: durationMinutes,
            studio: studio?.nonEmpty,
            otherActressMovies: otherActressMovies,
            recommendedMovies: recommendedMovies
        )
    }

    static func searchMovies(query: String) async throws -> [HiddenJavDBMovie] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let url = searchURL(query: normalizedQuery)
        let html = try await fetchHTML(from: url)
        return parseMovies(from: html, baseURL: url)
    }

    static func resolveSeekThumbnailConfig(
        for playback: HiddenJavDBFavoritePlayback
    ) async -> HiddenJavDBSeekThumbnailConfiguration? {
        for site in preferredPlayableSites(for: playback) {
            guard site.name == HiddenJavDBWatchSite.missAV.name,
                  let pageURL = site.url(for: playback.movie.code),
                  let configuration = await HiddenMissAVPlaybackResolver.resolveSeekThumbnailConfiguration(pageURL: pageURL) else {
                continue
            }
            return HiddenJavDBSeekThumbnailConfiguration(
                pageURL: configuration.pageURL,
                durationSeconds: configuration.durationSeconds,
                picNum: configuration.picNum,
                width: configuration.width,
                height: configuration.height,
                col: configuration.col,
                row: configuration.row,
                offsetX: configuration.offsetX,
                offsetY: configuration.offsetY,
                urls: configuration.urls
            )
        }

        return nil
    }

    static func resolvePlayableStream(for playback: HiddenJavDBFavoritePlayback) async throws -> (streamURL: URL, refererURL: URL) {
        for site in preferredPlayableSites(for: playback) {
            guard let pageURL = site.url(for: playback.movie.code) else { continue }

            do {
                let target = try await resolveWatchPlaybackTarget(for: site, pageURL: pageURL)
                if case let .stream(streamURL, refererURL) = target {
                    return (streamURL, refererURL)
                }
            } catch {
                continue
            }
        }

        return (playback.streamURL, playback.refererURL)
    }

    static func fetchBinaryData(from url: URL, refererURL: URL? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = true
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        if let refererURL {
            request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")
            if let scheme = refererURL.scheme, let host = refererURL.host {
                request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
            }
        }

        if let cookieField = cookieHeader(for: [url, refererURL].compactMap { $0 }) {
            request.setValue(cookieField, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -33,
                userInfo: [NSLocalizedDescriptionKey: "二进制资源返回异常"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -34,
                userInfo: [NSLocalizedDescriptionKey: "资源请求失败（\(httpResponse.statusCode)）"]
            )
        }

        return data
    }

    static func fetchMissAVPrimaryStreamURL(pageURL: URL) async throws -> URL {
        try await HiddenMissAVPlaybackResolver.resolvePrimaryStreamURL(pageURL: pageURL)
    }

    private static func fetchMissAVSeekThumbnailConfiguration(
        pageURL: URL
    ) async throws -> HiddenJavDBSeekThumbnailConfiguration? {
        guard let configuration = await HiddenMissAVPlaybackResolver.resolveSeekThumbnailConfiguration(pageURL: pageURL) else {
            return nil
        }
        return HiddenJavDBSeekThumbnailConfiguration(
            pageURL: configuration.pageURL,
            durationSeconds: configuration.durationSeconds,
            picNum: configuration.picNum,
            width: configuration.width,
            height: configuration.height,
            col: configuration.col,
            row: configuration.row,
            offsetX: configuration.offsetX,
            offsetY: configuration.offsetY,
            urls: configuration.urls
        )
    }

    static func resolveWatchPlaybackTarget(for site: HiddenJavDBWatchSite, pageURL: URL) async throws -> HiddenJavDBWatchPlaybackTarget {
        switch site.launchMode {
        case .nativeStream:
            switch site.name {
            case "MISSAV":
                let target = try await HiddenMissAVPlaybackResolver.resolvePlaybackTarget(pageURL: pageURL)
                switch target {
                case let .stream(streamURL, refererURL):
                    return .stream(streamURL, refererURL)
                }
            default:
                throw NSError(
                    domain: "HiddenJavDBAPI",
                    code: -31,
                    userInfo: [NSLocalizedDescriptionKey: "暂不支持该站点的原生播放"]
                )
            }
        case .embeddedWeb:
            switch site.name {
            case "Jav.Guru":
                return .webPage(try await fetchJavGuruPreferredWebURL(searchPageURL: pageURL))
            default:
                return .webPage(pageURL)
            }
        case .external:
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -32,
                userInfo: [NSLocalizedDescriptionKey: "该站点仅支持外部打开"]
            )
        }
    }

    private static func resolveTotalPages(knownTotalPages: Int?) async throws -> Int {
        if let knownTotalPages, knownTotalPages > 0 {
            return knownTotalPages
        }

        let html = try await fetchHTML(from: listingURL)
        let queryPages = regexCaptureAll(pattern: #"(?:\?|&)page=(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxQueryPage = queryPages.max(), maxQueryPage > 0 {
            return maxQueryPage
        }

        let normalPages = regexCaptureAll(pattern: #"/page/(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxNormalPage = normalPages.max(), maxNormalPage > 0 {
            return maxNormalPage
        }

        return 400
    }

    private static func fetchJavGuruPreferredWebURL(searchPageURL: URL) async throws -> URL {
        let searchHTML = try await fetchHTML(from: searchPageURL)
        let articleURL = extractJavGuruArticleURL(from: searchHTML) ?? searchPageURL

        let articleHTML = try await fetchHTML(from: articleURL)
        if let playerURL = extractJavGuruEmbeddedURL(from: articleHTML) {
            return playerURL
        }

        return articleURL
    }

    private static func listURL(page: Int) -> URL {
        guard page > 1 else { return listingURL }
        var components = URLComponents(url: listingURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "page" }
        items.append(URLQueryItem(name: "page", value: "\(page)"))
        components?.queryItems = items
        return components?.url ?? listingURL
    }

    private static func searchURL(query: String) -> URL {
        var components = URLComponents(string: "https://javdb.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "f", value: "all")
        ]
        return components?.url ?? listingURL
    }

    private static func preferredPlayableSites(for playback: HiddenJavDBFavoritePlayback) -> [HiddenJavDBWatchSite] {
        let nativeSites = HiddenJavDBWatchSite.defaultSites.filter { $0.launchMode == .nativeStream }
        guard let preferredSite = nativeSites.first(where: { $0.name == playback.sourceName }) else {
            return nativeSites
        }

        return [preferredSite] + nativeSites.filter { $0.id != preferredSite.id }
    }

    private static func fetchHTML(from url: URL) async throws -> String {
        try await fetchHTML(from: url, allowAgeConfirmationBypass: true)
    }

    private static func fetchHTML(from url: URL, allowAgeConfirmationBypass: Bool) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = true
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        if let cookieField = cookieHeader(for: [url]) {
            request.setValue(cookieField, forHTTPHeaderField: "Cookie")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let markdown = try? await fetchJinaMarkdown(for: url) {
                return markdown
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "请求返回异常"]
            )
        }
        let finalURL = httpResponse.url ?? url

        guard (200...299).contains(httpResponse.statusCode) else {
            if let markdown = try? await fetchJinaMarkdown(for: url) {
                return markdown
            }

            if httpResponse.statusCode == 403 || httpResponse.statusCode == 503 {
                if let webHTML = try? await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: url),
                   !isCloudflareChallengeHTML(webHTML) {
                    return try await resolveFetchedHTML(
                        webHTML,
                        requestURL: url,
                        finalURL: url,
                        allowAgeConfirmationBypass: allowAgeConfirmationBypass
                    )
                }

                throw NSError(
                    domain: "HiddenJavDBAPI",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "请求遇到验证页，请稍后重试"]
                )
            }

            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "页面请求失败（\(httpResponse.statusCode)）"]
            )
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? ""

        if html.isEmpty {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "页面解析失败"]
            )
        }

        return try await resolveFetchedHTML(
            html,
            requestURL: url,
            finalURL: finalURL,
            allowAgeConfirmationBypass: allowAgeConfirmationBypass
        )
    }

    static func parseMovies(from html: String, baseURL: URL) -> [HiddenJavDBMovie] {
        if html.contains("Markdown Content:") {
            return parseMoviesFromMarkdown(html)
        }

        let resolvedBaseURL = preferredBaseURL(from: html, fallbackURL: baseURL)
        let blocks = regexCapturePairs(
            pattern: #"<a[^>]+href=["'](/v/[^"'?#]+)["'][^>]*>(.*?)</a>"#,
            in: html,
            dotMatchesLine: true
        )

        var movies: [HiddenJavDBMovie] = []
        var seen = Set<String>()

        for (rawLink, block) in blocks {
            guard block.range(of: "<img", options: .caseInsensitive) != nil,
                  let rawMovieURL = normalizedURL(from: rawLink, relativeTo: resolvedBaseURL) else {
                continue
            }

            let movieURL = normalizeMovieURL(rawMovieURL)
            guard seen.insert(movieURL.absoluteString).inserted else {
                continue
            }

            let coverRaw = firstNonEmpty([
                regexFirstCapture(pattern: #"<img[^>]+data-src=["']([^"']+)["']"#, in: block, dotMatchesLine: true),
                regexFirstCapture(pattern: #"<img[^>]+src=["']([^"']+)["']"#, in: block, dotMatchesLine: true)
            ])

            guard let coverRaw,
                  let coverURL = normalizedURL(from: coverRaw, relativeTo: resolvedBaseURL) else {
                continue
            }

            let code = extractMovieCode(from: block) ?? movieURL.lastPathComponent.uppercased()

            let title = extractMovieTitle(from: block, code: code) ?? code

            let actresses = parseActorNames(from: block)

            movies.append(
                HiddenJavDBMovie(
                    url: movieURL,
                    code: code,
                    title: title,
                    coverURL: normalizeImageURL(coverURL),
                    actresses: actresses
                )
            )
        }

        return movies
    }

    private static func fetchJinaMarkdown(for sourceURL: URL) async throws -> String {
        guard sourceURL.host?.lowercased().contains("javdb.com") == true else {
            throw URLError(.unsupportedURL)
        }

        let escapedSource = sourceURL.absoluteString.replacingOccurrences(of: "&", with: "%26")
        guard let proxyURL = URL(string: "https://r.jina.ai/\(escapedSource)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: proxyURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let markdown = String(data: data, encoding: .utf8),
              markdown.contains("Markdown Content:") else {
            throw URLError(.badServerResponse)
        }
        return markdown
    }

    private static func parseMoviesFromMarkdown(_ markdown: String) -> [HiddenJavDBMovie] {
        let pattern = #"!\[Image[^\]]*\]\((https?://[^)\s]+)\)\s+\*\*([^*]+)\*\*.*?\]\((https?://javdb\.com/v/[^)\s\"]+)(?:\s+\"([^\"]*)\")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        var movies: [HiddenJavDBMovie] = []
        var seen = Set<String>()

        for match in regex.matches(in: markdown, options: [], range: range) {
            guard match.numberOfRanges >= 4,
                  let coverRange = Range(match.range(at: 1), in: markdown),
                  let codeRange = Range(match.range(at: 2), in: markdown),
                  let movieRange = Range(match.range(at: 3), in: markdown),
                  let coverURL = URL(string: String(markdown[coverRange])),
                  let rawMovieURL = URL(string: String(markdown[movieRange])) else {
                continue
            }

            let movieURL = normalizeMovieURL(rawMovieURL)
            guard seen.insert(movieURL.absoluteString).inserted else { continue }

            let code = cleanTitle(String(markdown[codeRange]))
            let title: String
            if match.numberOfRanges > 4,
               match.range(at: 4).location != NSNotFound,
               let titleRange = Range(match.range(at: 4), in: markdown) {
                title = cleanTitle(String(markdown[titleRange]))
            } else {
                title = code
            }

            movies.append(
                HiddenJavDBMovie(
                    url: movieURL,
                    code: code,
                    title: title,
                    coverURL: normalizeImageURL(coverURL),
                    actresses: []
                )
            )
        }

        return movies
    }

    private static func extractMovieCode(from block: String) -> String? {
        let explicitCandidates = [
            regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*uid[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<span[^>]*class=["'][^"']*(?:uid|video-id)[^"']*["'][^>]*>(.*?)</span>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<strong[^>]*>(.*?)</strong>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*video-title[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"title=["']([^"']+)["']"#, in: block, dotMatchesLine: true)
        ]

        for candidate in explicitCandidates {
            if let code = extractLikelyMovieCode(from: candidate) {
                return code
            }
        }

        return extractLikelyMovieCode(from: cleanTitle(block))
    }

    private static func extractMovieTitle(from block: String, code: String) -> String? {
        let candidates = [
            regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*video-title[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*title[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"title=["']([^"']+)["']"#, in: block, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<strong[^>]*>(.*?)</strong>"#, in: block, dotMatchesLine: true)
        ]

        for candidate in candidates {
            guard let candidate else { continue }

            let cleanedTitle = strippingLeadingMovieCode(cleanTitle(candidate), code: code)
            if let normalizedTitle = cleanedTitle.nonEmpty, normalizedTitle.uppercased() != code.uppercased() {
                return normalizedTitle
            }
        }

        return nil
    }

    private static func extractLikelyMovieCode(from raw: String?) -> String? {
        guard let raw else { return nil }

        let cleaned = cleanTitle(raw)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")

        let patterns = [
            #"\b(FC2[-\s]*PPV[-\s]*\d{5,8})\b"#,
            #"\b((?:\d{2,4})?[A-Z]{2,10}[-\s]?\d{2,6}[A-Z]?)\b"#
        ]

        for pattern in patterns {
            if let match = regexFirstCapture(pattern: pattern, in: cleaned.uppercased(), dotMatchesLine: false) {
                return canonicalMovieCode(match)
            }
        }

        return nil
    }

    private static func canonicalMovieCode(_ rawCode: String) -> String {
        let compact = rawCode
            .uppercased()
            .replacingOccurrences(of: #"[‐‑–—_]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if let digits = regexFirstCapture(pattern: #"^FC2-?PPV-?(\d{5,8})$"#, in: compact, dotMatchesLine: false) {
            return "FC2-PPV-\(digits)"
        }

        if let groups = regexFirstGroups(
            pattern: #"^((?:\d{2,4})?[A-Z]{2,10})-?(\d{2,6}[A-Z]?)$"#,
            in: compact,
            dotMatchesLine: false
        ), groups.count == 2 {
            return "\(groups[0])-\(groups[1])"
        }

        return compact
    }

    private static func strippingLeadingMovieCode(_ title: String, code: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let variants = [
            code.uppercased(),
            code.uppercased().replacingOccurrences(of: "-", with: ""),
            code.uppercased().replacingOccurrences(of: "-", with: " ")
        ].sorted { $0.count > $1.count }

        let uppercaseTitle = trimmedTitle.uppercased()
        for variant in variants where uppercaseTitle.hasPrefix(variant) {
            let index = trimmedTitle.index(trimmedTitle.startIndex, offsetBy: variant.count)
            let remainder = trimmedTitle[index...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -:|/·").union(.whitespacesAndNewlines))
            if !remainder.isEmpty {
                return String(remainder)
            }
        }

        return trimmedTitle
    }

    private static func parseRelatedMovies(
        from html: String,
        titleKeywords: [String],
        excluding currentMovie: HiddenJavDBMovie,
        baseURL: URL
    ) -> [HiddenJavDBMovie] {
        let normalizedKeywords = titleKeywords.map(normalizedSectionTitle)

        for block in regexFullMatches(pattern: #"<section\b[^>]*>.*?</section>"#, in: html, dotMatchesLine: true) {
            let normalizedBlock = normalizedSectionTitle(cleanTitle(block))
            guard normalizedKeywords.contains(where: { normalizedBlock.contains($0) }) else { continue }

            let movies = dedupedRelatedMovies(
                parseMovies(from: block, baseURL: baseURL).filter { $0.id != currentMovie.id }
            )
            if !movies.isEmpty {
                return movies
            }
        }

        for section in extractMessagePanelSections(from: html) {
            let normalizedTitle = normalizedSectionTitle(section.title)
            guard normalizedKeywords.contains(where: { normalizedTitle.contains($0) }) else { continue }

            let movies = dedupedRelatedMovies(
                parseMovies(from: section.body, baseURL: baseURL).filter { $0.id != currentMovie.id }
            )
            if !movies.isEmpty {
                return movies
            }
        }

        for section in extractHeadingAnchoredSections(from: html) {
            let normalizedTitle = normalizedSectionTitle(section.title)
            guard normalizedKeywords.contains(where: { normalizedTitle.contains($0) }) else { continue }

            let movies = dedupedRelatedMovies(
                parseMovies(from: section.body, baseURL: baseURL).filter { $0.id != currentMovie.id }
            )
            if !movies.isEmpty {
                return movies
            }
        }

        return []
    }

    static func parseMovieImages(from html: String) -> [URL] {
        let anchoredImages = dedupePreferredMovieSampleImages(
            extractAnchoredPreviewImageCandidates(from: html)
                .compactMap(normalizedURL(from:))
                .filter(isLikelyMovieSampleImageURL)
        )
        if !anchoredImages.isEmpty {
            return anchoredImages
        }

        let previewScopes = extractPreviewScopes(from: html)
        let scopedCandidates = previewScopes.flatMap(extractImageCandidates)
        let scopedImages = dedupePreferredMovieSampleImages(
            scopedCandidates.compactMap(normalizedURL(from:)).filter(isLikelyMovieSampleImageURL)
        )
        if !scopedImages.isEmpty {
            return scopedImages
        }

        let allCandidates = extractImageCandidates(from: html)
        let strictAll = dedupePreferredMovieSampleImages(
            allCandidates.compactMap(normalizedURL(from:)).filter(isLikelyMovieSampleImageURL)
        )
        if !strictAll.isEmpty {
            return strictAll
        }

        return dedupePreferredMovieSampleImages(
            allCandidates
                .compactMap(normalizedURL(from:))
                .filter(isLikelyImageURL)
                .filter { !isClearlyNonSampleImageURL($0) }
        )
    }

    private static func extractAnchoredPreviewImageCandidates(from html: String) -> [String] {
        let scopes = extractPreviewScopes(from: html)
        let scopedCandidates = scopes.flatMap { scope in
            regexCaptureAll(
                pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<img"#,
                in: scope,
                dotMatchesLine: true
            )
        }

        let pageLevelCandidates = regexCaptureAll(
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<img"#,
            in: html,
            dotMatchesLine: true
        )

        return scopedCandidates + pageLevelCandidates
    }

    private static func extractPreviewScopes(from html: String) -> [String] {
        var scopes: [String] = []

        let panelBlocks = regexCaptureAll(
            pattern: #"<(?:section|div)[^>]+class=["'][^"']*(?:preview-images|tile-images|samples|sample-waterfall)[^"']*["'][^>]*>(.*?)</(?:section|div)>"#,
            in: html,
            dotMatchesLine: true
        )
        scopes.append(contentsOf: panelBlocks)

        let idBlocks = regexCaptureAll(
            pattern: #"<(?:section|div)[^>]+id=["'][^"']*(?:preview|sample|screenshot)[^"']*["'][^>]*>(.*?)</(?:section|div)>"#,
            in: html,
            dotMatchesLine: true
        )
        scopes.append(contentsOf: idBlocks)

        return scopes
    }

    private static func extractImageCandidates(from html: String) -> [String] {
        let directURLs = regexCaptureAll(
            pattern: #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        )
        let srcsetValues = regexCaptureAll(
            pattern: #"(?:srcset|data-srcset)=["']([^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        )
        return directURLs + srcsetValues.flatMap(extractURLsFromSrcset)
    }

    private static func dedupeImageURLs(_ urls: [URL]) -> [URL] {
        var deduped: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let normalized = normalizeImageURL(url)
            if seen.insert(normalized.absoluteString).inserted {
                deduped.append(normalized)
            }
        }
        return deduped
    }

    private static func dedupePreferredMovieSampleImages(_ urls: [URL]) -> [URL] {
        struct Candidate {
            let url: URL
            let score: Int
        }

        var order: [String] = []
        var bestByKey: [String: Candidate] = [:]

        for rawURL in urls {
            let normalized = normalizeImageURL(rawURL)
            let key = canonicalMovieSampleImageKey(for: normalized)
            let score = movieSampleImageQualityScore(for: normalized)

            if let existing = bestByKey[key] {
                if score > existing.score {
                    bestByKey[key] = Candidate(url: normalized, score: score)
                }
            } else {
                order.append(key)
                bestByKey[key] = Candidate(url: normalized, score: score)
            }
        }

        return order.compactMap { bestByKey[$0]?.url }
    }

    private static func canonicalMovieSampleImageKey(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        var base = fileName
        base = base.replacingOccurrences(
            of: #"(?:[_-](?:blur|blurry|thumb|thumbnail|small|sm|mini|preview|low|lq|mq|sd|hd|orig|original|large|xl|xlarge))+$"#,
            with: "",
            options: .regularExpression
        )
        base = base.replacingOccurrences(
            of: #"(?:[_-]\d{2,4}x\d{2,4})+$"#,
            with: "",
            options: .regularExpression
        )

        if base.isEmpty {
            base = fileName
        }
        return "\(host)|\(base)"
    }

    private static func movieSampleImageQualityScore(for url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        var score = 0

        if value.contains("/sample/") || value.contains("/samples/") || value.contains("/screenshots/") {
            score += 8
        }
        if value.contains("/thumb/") || value.contains("/thumbs/") {
            score -= 8
        }

        let positiveKeywords = [
            "original",
            "orig",
            "full",
            "large",
            "hq"
        ]
        for keyword in positiveKeywords where value.contains(keyword) {
            score += 2
        }

        let negativeKeywords = [
            "blur",
            "blurry",
            "thumb",
            "thumbnail",
            "small",
            "preview",
            "low",
            "lq",
            "placeholder",
            "sprite"
        ]
        for keyword in negativeKeywords where value.contains(keyword) {
            score -= 4
        }

        score += min(value.count / 40, 8)
        return score
    }

    private static func parseActorNames(from text: String) -> [String] {
        let names = regexCaptureAll(
            pattern: #"<a[^>]+href=["']/actors/[^"']+["'][^>]*>(.*?)</a>"#,
            in: text,
            dotMatchesLine: true
        ).map(cleanTitle).filter { !$0.isEmpty }

        var deduped: [String] = []
        var seen = Set<String>()
        for name in names where seen.insert(name).inserted {
            deduped.append(name)
        }
        return deduped
    }

    private static func extractMissAVSeekThumbnailConfiguration(
        from html: String,
        pageURL: URL
    ) -> HiddenJavDBSeekThumbnailConfiguration? {
        guard let block = regexFirstCapture(
            pattern: #"thumbnail:\s*\{(.*?)\}\s*,\s*keyboard:"#,
            in: html,
            dotMatchesLine: true
        ) else {
            return nil
        }

        if let enabled = regexFirstCapture(
            pattern: #"\benabled:\s*(true|false)"#,
            in: block,
            dotMatchesLine: false
        )?.lowercased(), enabled == "false" {
            return nil
        }

        guard let picNum = Int(regexFirstCapture(pattern: #"\bpic_num:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let width = Int(regexFirstCapture(pattern: #"\bwidth:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let height = Int(regexFirstCapture(pattern: #"\bheight:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let col = Int(regexFirstCapture(pattern: #"\bcol:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let row = Int(regexFirstCapture(pattern: #"\brow:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? ""),
              let durationSeconds = Double(
                regexFirstCapture(
                    pattern: #"<meta\s+property=["']og:video:duration["']\s+content=["'](\d+(?:\.\d+)?)["']"#,
                    in: html,
                    dotMatchesLine: true
                ) ?? ""
              ) else {
            return nil
        }

        let offsetX = Int(regexFirstCapture(pattern: #"\boffsetX:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? "") ?? 0
        let offsetY = Int(regexFirstCapture(pattern: #"\boffsetY:\s*(\d+)"#, in: block, dotMatchesLine: false) ?? "") ?? 0
        let rawURLs = regexCaptureAll(
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
            .compactMap { normalizedExternalURL(from: $0, relativeTo: pageURL) }

        guard picNum > 0,
              width > 0,
              height > 0,
              col > 0,
              row > 0,
              durationSeconds > 0,
              !urls.isEmpty else {
            return nil
        }

        return HiddenJavDBSeekThumbnailConfiguration(
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

    private static func extractMissAVStreamURL(from html: String) -> URL? {
        var candidates: [String] = []

        // Try direct URLs first.
        let direct = regexCaptureAll(
            pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
            in: html,
            dotMatchesLine: true
        )
        candidates.append(contentsOf: direct)

        // MissAV often stores source URLs in P.A.C.K.E.R eval blocks.
        let decodedBlocks = decodeMissAVEvalBlocks(from: html)
        for block in decodedBlocks {
            let urls = regexCaptureAll(
                pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
                in: block,
                dotMatchesLine: true
            )
            candidates.append(contentsOf: urls)
        }

        let normalized = candidates.compactMap(normalizedURL(from:))
        let prioritized = prioritizedMissAVStreamCandidates(normalized)
        return prioritized.first
    }

    private static func extractJavGuruArticleURL(from html: String) -> URL? {
        let candidates = regexCaptureAll(
            pattern: #"href=["'](https://jav\.guru/\d+/[^"'?#]+/?)["']"#,
            in: html,
            dotMatchesLine: true
        )

        return candidates.compactMap(normalizedURL(from:)).first
    }

    private static func extractJavGuruEmbeddedURL(from html: String) -> URL? {
        guard let encoded = regexFirstCapture(
            pattern: #""iframe_url":"([^"]+)""#,
            in: html,
            dotMatchesLine: true
        )?.nonEmpty else {
            return nil
        }

        let decoded = decodeBase64String(encoded)
        return decoded.flatMap(normalizedURL(from:))
    }

    private static func decodeMissAVEvalBlocks(from html: String) -> [String] {
        let pattern = #"eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.+?)',(\d+),(\d+),'(.+?)'\.split\('\|'\),0,\{\}\)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        var decoded: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 5,
                  let payloadRange = Range(match.range(at: 1), in: html),
                  let baseRange = Range(match.range(at: 2), in: html),
                  let countRange = Range(match.range(at: 3), in: html),
                  let dictRange = Range(match.range(at: 4), in: html),
                  let base = Int(html[baseRange]),
                  let count = Int(html[countRange]) else {
                continue
            }
            guard base >= 2, base <= 36 else {
                continue
            }

            let payloadRaw = String(html[payloadRange])
            let payload = payloadRaw
                .replacingOccurrences(of: #"\'"#, with: "'")
                .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
            let dictionary = String(html[dictRange]).split(separator: "|").map(String.init)
            decoded.append(unpackPAckerPayload(payload, base: base, count: count, dictionary: dictionary))
        }

        return decoded
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

    private static func prioritizedMissAVStreamCandidates(_ urls: [URL]) -> [URL] {
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
            let lPath = lhs.path.lowercased()
            let rPath = rhs.path.lowercased()
            let lScore = (lPath.contains("/playlist") ? 3 : 0) + (lPath.contains("/video/") ? 1 : 0)
            let rScore = (rPath.contains("/playlist") ? 3 : 0) + (rPath.contains("/video/") ? 1 : 0)
            return lScore > rScore
        }

        return playlistFirst.isEmpty ? unique : playlistFirst
    }

    private static func cookieHeader(for urls: [URL]) -> String? {
        var cookies: [HTTPCookie] = []
        var seen = Set<String>()

        for url in urls {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                let key = "\(cookie.domain)|\(cookie.path)|\(cookie.name)|\(cookie.value)"
                guard seen.insert(key).inserted else { continue }
                cookies.append(cookie)
            }
        }

        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private static func resolveFetchedHTML(
        _ html: String,
        requestURL: URL,
        finalURL: URL,
        allowAgeConfirmationBypass: Bool
    ) async throws -> String {
        if allowAgeConfirmationBypass,
           let confirmationURL = ageConfirmationContinueURLIfNeeded(from: html, finalURL: finalURL) {
            _ = try await fetchHTML(from: confirmationURL, allowAgeConfirmationBypass: false)
            let confirmedHTML = try await fetchHTML(from: requestURL, allowAgeConfirmationBypass: false)

            if ageConfirmationContinueURLIfNeeded(from: confirmedHTML, finalURL: requestURL) != nil {
                throw ageConfirmationError()
            }

            return confirmedHTML
        }

        if ageConfirmationContinueURLIfNeeded(from: html, finalURL: finalURL) != nil {
            throw ageConfirmationError()
        }

        if isCloudflareChallengeHTML(html) {
            if let webHTML = try? await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: requestURL),
               !isCloudflareChallengeHTML(webHTML) {
                return try await resolveFetchedHTML(
                    webHTML,
                    requestURL: requestURL,
                    finalURL: requestURL,
                    allowAgeConfirmationBypass: allowAgeConfirmationBypass
                )
            }

            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "检测到验证页，请稍后重试"]
            )
        }

        return html
    }

    private static func ageConfirmationError() -> NSError {
        NSError(
            domain: "HiddenJavDBAPI",
            code: -35,
            userInfo: [NSLocalizedDescriptionKey: "需要先完成 18+ 年龄确认，请在网页中确认后重试"]
        )
    }

    private static func ageConfirmationContinueURLIfNeeded(from html: String, finalURL: URL) -> URL? {
        guard containsAgeConfirmationModal(in: html) else {
            return nil
        }

        let candidates = [
            regexFirstCapture(
                pattern: #"<a[^>]*class=["'][^"']*button[^"']*is-success[^"']*is-large[^"']*["'][^>]*href=["']([^"']+/over18\?respond=1[^"']*)["']"#,
                in: html,
                dotMatchesLine: true
            ),
            regexFirstCapture(
                pattern: #"<a[^>]+href=["']([^"']*/over18\?respond=1[^"']*)["'][^>]*>"#,
                in: html,
                dotMatchesLine: true
            ),
            regexFirstCapture(
                pattern: #"(/over18\?respond=1[^"'\s<]*)"#,
                in: html,
                dotMatchesLine: true
            )
        ]

        for candidate in candidates {
            guard let raw = candidate?.nonEmpty,
                  let url = normalizedExternalURL(from: raw, relativeTo: finalURL) else {
                continue
            }
            return url
        }

        return nil
    }

    private static func containsAgeConfirmationModal(in html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("over18-modal")
            || lowered.contains("/over18?respond=1")
            || lowered.contains("是,我已滿18歲".lowercased())
            || lowered.contains("是,我已满18岁")
            || lowered.contains("您的年齡為18歲以上嗎？".lowercased())
            || lowered.contains("您的年龄为18岁以上吗？")
    }

    private static func extractMetadataValue(labelKeywords: [String], in html: String) -> String? {
        for keyword in labelKeywords {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            let patterns = [
                #"<strong[^>]*>[^<]*\#(escaped)[^<]*</strong>\s*<span[^>]*class="[^"]*value[^"]*"[^>]*>(.*?)</span>"#,
                #"<span[^>]*class="[^"]*meta[^"]*"[^>]*>[^<]*\#(escaped)[^<]*</span>\s*<span[^>]*class="[^"]*value[^"]*"[^>]*>(.*?)</span>"#,
                #"\#(escaped)[^<:：]{0,12}[:：]\s*</?[^>]*>\s*([^<]+)"#
            ]

            for pattern in patterns {
                if let value = regexFirstCapture(pattern: pattern, in: html, dotMatchesLine: true) {
                    let cleaned = cleanTitle(value)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }

    static func normalizedURL(from raw: String) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let url: URL?
        if decoded.hasPrefix("//") {
            url = URL(string: "https:" + decoded)
        } else if decoded.hasPrefix("/") {
            url = URL(string: "https://javdb.com" + decoded)
        } else {
            url = URL(string: decoded)
        }
        return url
    }

    static func normalizedURL(from raw: String, relativeTo baseURL: URL) -> URL? {
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

    private static func normalizedExternalURL(from raw: String, relativeTo baseURL: URL) -> URL? {
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

    private static func preferredBaseURL(from html: String, fallbackURL: URL) -> URL {
        if let raw = regexFirstCapture(
            pattern: #"<body[^>]+data-domain=["'](https?://[^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        ),
           let url = URL(string: raw) {
            return url
        }

        if var components = URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false),
           components.scheme != nil,
           components.host != nil {
            components.path = "/"
            components.query = nil
            components.fragment = nil
            return components.url ?? fallbackURL
        }

        return fallbackURL
    }

    static func normalizeMovieURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.host == nil {
            components.scheme = "https"
            components.host = "javdb.com"
        }

        if let movieID = regexFirstCapture(pattern: #"^/v/([^/?#]+)"#, in: components.path, dotMatchesLine: false) {
            components.path = "/v/\(movieID)"
        }

        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    static func normalizeImageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.host == nil {
            components.scheme = "https"
            components.host = "javdb.com"
        }

        return components.url ?? url
    }

    fileprivate static func isCloudflareChallengeHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        if lowered.contains("<title>just a moment") {
            return true
        }
        if lowered.contains("enable javascript and cookies to continue") {
            return true
        }
        if lowered.contains("cf_chl_opt") {
            return true
        }
        return lowered.contains("challenge-platform") && lowered.contains("cf-ray")
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) {
            return true
        }

        if path.contains("/samples/") || path.contains("/covers/") || path.contains("/thumbs/") {
            return true
        }

        return false
    }

    private static func isLikelyMovieSampleImageURL(_ url: URL) -> Bool {
        guard isLikelyImageURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.lowercased()
        if isClearlyNonSampleImageURL(url) {
            return false
        }

        let positiveKeywords = [
            "/sample/",
            "/samples/",
            "/screenshot/",
            "/screenshots/",
            "/preview/",
            "/digital/video/",
            "/litevideo/freepv/",
            "sample-",
            "screenshot",
            "preview",
            "jp-"
        ]
        if positiveKeywords.contains(where: { path.contains($0) }) {
            return true
        }

        if regexFirstCapture(pattern: #"(?:-|_)(\d{1,2})\.(?:jpe?g|png|webp|avif|gif)$"#, in: path, dotMatchesLine: false) != nil {
            return true
        }

        return false
    }

    private static func isClearlyNonSampleImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let path = components.path.lowercased()

        let blockedKeywords = [
            "/actors/",
            "/actor/",
            "/avatars/",
            "/avatar/",
            "/logo",
            "/icon",
            "/favicon",
            "/poster",
            "/cover",
            "/thumb",
            "/banner",
            "/ads/",
            "/emoji/"
        ]
        return blockedKeywords.contains(where: { path.contains($0) })
    }

    private static func extractURLsFromSrcset(_ srcset: String) -> [String] {
        srcset
            .split(separator: ",")
            .compactMap { candidate in
                candidate
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }
    }

    private static func cleanTitle(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
        let normalized = decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasSuffix(" - JavDB") {
            return String(normalized.dropLast(" - JavDB".count))
        }
        return normalized
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
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

    private static func decodeBase64String(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }

    private static func regexFirstCapture(pattern: String, in text: String, dotMatchesLine: Bool) -> String? {
        regexCaptureAll(pattern: pattern, in: text, dotMatchesLine: dotMatchesLine).first
    }

    private static func regexCaptureAll(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
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

    private static func regexCapturePairs(pattern: String, in text: String, dotMatchesLine: Bool) -> [(String, String)] {
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
            guard match.numberOfRanges > 2,
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            return (String(text[firstRange]), String(text[secondRange]))
        }
    }

    private static func regexFullMatches(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let fullRange = Range(match.range(at: 0), in: text) else {
                return nil
            }
            return String(text[fullRange])
        }
    }

    private static func regexFirstGroups(pattern: String, in text: String, dotMatchesLine: Bool) -> [String]? {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    private static func extractHeadingAnchoredSections(from html: String) -> [(title: String, body: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])[^>]*>(.*?)</h\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        var sections: [(title: String, body: String)] = []
        for index in matches.indices {
            guard let titleRange = Range(matches[index].range(at: 2), in: html),
                  let fullRange = Range(matches[index].range(at: 0), in: html) else {
                continue
            }

            let title = cleanTitle(String(html[titleRange]))
            guard !title.isEmpty else { continue }

            let bodyStart = fullRange.upperBound
            let bodyEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range(at: 0), in: html) {
                bodyEnd = nextRange.lowerBound
            } else {
                bodyEnd = html.endIndex
            }

            sections.append((title: title, body: String(html[bodyStart..<bodyEnd])))
        }

        return sections
    }

    private static func extractMessagePanelSections(from html: String) -> [(title: String, body: String)] {
        let blocks = regexFullMatches(
            pattern: #"<article\b[^>]*class=["'][^"']*message[^"']*video-panel[^"']*["'][^>]*>.*?</article>"#,
            in: html,
            dotMatchesLine: true
        )

        return blocks.compactMap { block in
            guard let title = firstNonEmpty([
                regexFirstCapture(
                    pattern: #"<div[^>]*class=["'][^"']*message-header[^"']*["'][^>]*>\s*<p[^>]*>(.*?)</p>"#,
                    in: block,
                    dotMatchesLine: true
                ),
                regexFirstCapture(
                    pattern: #"<header[^>]*>\s*<p[^>]*>(.*?)</p>"#,
                    in: block,
                    dotMatchesLine: true
                )
            ]).map(cleanTitle)?.nonEmpty else {
                return nil
            }

            return (title: title, body: block)
        }
    }

    private static func normalizedSectionTitle(_ value: String) -> String {
        cleanTitle(value)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private static func dedupedRelatedMovies(_ movies: [HiddenJavDBMovie]) -> [HiddenJavDBMovie] {
        var deduped: [HiddenJavDBMovie] = []
        var seen = Set<String>()

        for movie in movies where seen.insert(movie.id).inserted {
            deduped.append(movie)
            if deduped.count >= 18 {
                break
            }
        }

        return deduped
    }
}

@MainActor
final class HiddenJavDBWebHTMLFetcher: NSObject, WKNavigationDelegate {
    static let shared = HiddenJavDBWebHTMLFetcher()

    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = HiddenJavDBAPI.userAgent
        webView.scrollView.isScrollEnabled = false
        super.init()
        webView.navigationDelegate = self
    }

    func fetchHTML(from url: URL) async throws -> String {
        if continuation != nil {
            throw NSError(
                domain: "HiddenJavDBWebHTMLFetcher",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "页面加载中，请稍后重试"]
            )
        }

        await syncSharedCookiesToWebView(for: url)
        captureTask?.cancel()
        captureTask = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue(HiddenJavDBAPI.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            webView.load(request)

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.failIfPending(message: "WebView 请求超时，请重试")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            await self?.captureResolvedHTML(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failIfPending(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failIfPending(error: error)
    }

    private func finishIfPending(html: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        captureTask?.cancel()
        captureTask = nil
        continuation?.resume(returning: html)
        continuation = nil
    }

    private func failIfPending(error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        captureTask?.cancel()
        captureTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func failIfPending(message: String) {
        failIfPending(
            error: NSError(
                domain: "HiddenJavDBWebHTMLFetcher",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        )
    }

    private func syncSharedCookiesToWebView(for url: URL) async {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            await cookieStore.setCookieAsync(cookie)
        }
    }

    private func syncWebViewCookiesToSharedStore() async {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in await cookieStore.allCookiesAsync() {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func captureResolvedHTML(from webView: WKWebView) async {
        do {
            while continuation != nil {
                try Task.checkCancellation()

                let html = try await resolvedHTML(from: webView)
                if html.isEmpty {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                await syncWebViewCookiesToSharedStore()
                if !HiddenJavDBAPI.isCloudflareChallengeHTML(html) {
                    finishIfPending(html: html)
                    return
                }

                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch is CancellationError {
        } catch {
            failIfPending(error: error)
        }
    }

    private func resolvedHTML(from webView: WKWebView) async throws -> String {
        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        return (html as? String) ?? ""
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
private extension WKHTTPCookieStore {
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}

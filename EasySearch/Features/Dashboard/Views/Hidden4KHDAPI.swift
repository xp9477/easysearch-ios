import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

enum HiddenSpaceAPI {
    private static let baseURL = URL(string: "https://www.4khd.com/")!
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile"

    static func fetchRandomAlbum(knownTotalPages: Int?) async throws -> (album: HiddenAlbum, totalPages: Int) {
        let totalPages = try await resolveTotalPages(knownTotalPages: knownTotalPages)

        var attempts = 0
        while attempts < 8 {
            attempts += 1

            let randomPage = Int.random(in: 1...max(totalPages, 1))
            let html = try await fetchHTML(from: listURL(page: randomPage))
            let albums = parseAlbums(from: html)

            if let album = albums.randomElement() {
                return (album, totalPages)
            }
        }

        throw NSError(domain: "HiddenSpaceAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有解析到可用封面，请稍后重试"])
    }

    static func fetchAlbumImageURLs(albumURL: URL) async throws -> [URL] {
        let firstHTML = try await fetchHTML(from: albumURL)

        var pageURLs = [albumURL]
        let extraPageURLs = parseAlbumPageLinks(from: firstHTML)
        for url in extraPageURLs where !pageURLs.contains(url) {
            pageURLs.append(url)
        }

        var allImages: [URL] = []
        var seen = Set<String>()

        for pageURL in pageURLs {
            let html = pageURL == albumURL ? firstHTML : (try await fetchHTML(from: pageURL))
            let pageImages = parseAlbumImages(from: html)
            for imageURL in pageImages where seen.insert(imageURL.absoluteString).inserted {
                allImages.append(imageURL)
            }
        }

        guard !allImages.isEmpty else {
            throw NSError(domain: "HiddenSpaceAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "没有拿到图片列表"])
        }

        return allImages
    }

    static func searchAlbums(query: String) async throws -> [HiddenAlbum] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let html = try await fetchHTML(from: searchURL(query: normalizedQuery))
        return parseAlbums(from: html)
    }

    private static func resolveTotalPages(knownTotalPages: Int?) async throws -> Int {
        if let knownTotalPages, knownTotalPages > 0 {
            return knownTotalPages
        }

        let html = try await fetchHTML(from: baseURL)
        let queryPages = regexCaptureAll(pattern: #"\?query-3-page=(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxQueryPage = queryPages.max(), maxQueryPage > 0 {
            return maxQueryPage
        }

        let standardPages = regexCaptureAll(pattern: #"/page/(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxStandardPage = standardPages.max(), maxStandardPage > 0 {
            return maxStandardPage
        }

        return 2800
    }

    private static func listURL(page: Int) -> URL {
        guard page > 1 else { return baseURL }
        return URL(string: "https://www.4khd.com/?query-3-page=\(page)") ?? baseURL
    }

    private static func searchURL(query: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "s", value: query)]
        return components?.url ?? baseURL
    }

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "HiddenSpaceAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "页面请求失败"])
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "HiddenSpaceAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "页面解析失败"])
        }
        return html
    }

    static func parseAlbums(from html: String) -> [HiddenAlbum] {
        let blocks = regexCaptureAll(
            pattern: #"<li class="wp-block-post[^"]*"[^>]*>(.*?)</li>"#,
            in: html,
            dotMatchesLine: true
        )

        var albums: [HiddenAlbum] = []
        var seen = Set<String>()

        for block in blocks {
            guard let rawLink = regexFirstCapture(pattern: #"href="(https://www\.4khd\.com/content/[^"]+?\.html)""#, in: block, dotMatchesLine: true),
                  let albumURL = normalizedURL(from: rawLink),
                  let rawCover = regexFirstCapture(pattern: #"<img[^>]+src="([^"]+)""#, in: block, dotMatchesLine: true),
                  let coverURL = normalizedURL(from: rawCover) else {
                continue
            }

            let rawTitle = regexFirstCapture(pattern: #"<h2[^>]*>\s*<a[^>]*>(.*?)</a>"#, in: block, dotMatchesLine: true)
            let title = cleanTitle(rawTitle ?? albumURL.lastPathComponent)

            if seen.insert(albumURL.absoluteString).inserted {
                albums.append(HiddenAlbum(url: albumURL, title: title, coverURL: coverURL))
            }
        }

        return albums
    }

    static func parseAlbumPageLinks(from html: String) -> [URL] {
        let rawLinks = regexCaptureAll(
            pattern: #"<a[^>]+class="[^"]*page-numbers[^"]*"[^>]+href="([^"]+)""#,
            in: html,
            dotMatchesLine: true
        ) + regexCaptureAll(
            pattern: #"<a[^>]+href="([^"]+)"[^>]+class="[^"]*page-numbers[^"]*""#,
            in: html,
            dotMatchesLine: true
        )
        var urls: [URL] = []
        var seen = Set<String>()

        for rawLink in rawLinks {
            guard let url = normalizedURL(from: rawLink),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    static func parseAlbumImages(from html: String) -> [URL] {
        let contentSlice = sliceEntryContent(from: html)

        let directURLs = regexCaptureAll(
            pattern: #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#,
            in: contentSlice,
            dotMatchesLine: true
        )
        let srcsetValues = regexCaptureAll(
            pattern: #"(?:srcset|data-srcset)=["']([^"']+)["']"#,
            in: contentSlice,
            dotMatchesLine: true
        )
        let srcsetURLs = srcsetValues.flatMap(extractURLsFromSrcset)
        let candidateURLs = directURLs + srcsetURLs

        var images: [URL] = []
        var seen = Set<String>()

        for rawURL in candidateURLs {
            guard let url = normalizedURL(from: rawURL),
                  isLikelyImageURL(url),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            images.append(url)
        }

        return images
    }

    private static func sliceEntryContent(from html: String) -> String {
        guard let startRange = html.range(of: "entry-content wp-block-post-content") else {
            return html
        }

        let tail = html[startRange.lowerBound...]
        if let endRange = tail.range(of: "page-link-box") {
            return String(tail[..<endRange.lowerBound])
        }
        return String(tail)
    }

    static func normalizedURL(from raw: String) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawURL: URL?
        if decoded.hasPrefix("//") {
            rawURL = URL(string: "https:" + decoded)
        } else if decoded.hasPrefix("/") {
            rawURL = URL(string: "https://www.4khd.com" + decoded)
        } else {
            rawURL = URL(string: decoded)
        }

        guard let rawURL else { return nil }

        if isLikelyImageURL(rawURL) {
            return normalizeImageURL(rawURL)
        }
        return normalizeAlbumURL(rawURL)
    }

    static func normalizeImageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let host = components.host?.lowercased() ?? ""

        // Site HTML often uses i0.wp.com/pic.4khd.com/... which returns 400 directly.
        // Rewrite it to img.4khd.com/... first, then follow redirects.
        if host == "i0.wp.com" && components.path.hasPrefix("/pic.4khd.com/") {
            components.host = "img.4khd.com"
            components.path = components.path.replacingOccurrences(of: "/pic.4khd.com", with: "", options: .anchored)
            return components.url ?? url
        }

        if host == "pic.4khd.com" {
            components.host = "img.4khd.com"
            return components.url ?? url
        }

        return url
    }

    static func normalizeAlbumURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.host == nil {
            components.host = "www.4khd.com"
            components.scheme = "https"
        }
        return components.url ?? url
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        if host == "img.4khd.com" || host == "pic.4khd.com" {
            return true
        }
        if host.hasSuffix(".wp.com") && path.contains("/pic.4khd.com/") {
            return true
        }

        return ext == "jpg"
            || ext == "jpeg"
            || ext == "png"
            || ext == "webp"
            || ext == "gif"
            || ext == "avif"
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
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}

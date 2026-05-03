import Foundation
import XCTest
@testable import EasySearch

final class DashboardParserTests: XCTestCase {
    func test4KHDAlbumParserNormalizesAndDeduplicatesAlbums() {
        let html = """
        <li class="wp-block-post">
          <a href="https://www.4khd.com/content/sample-album.html"><img src="https://pic.4khd.com/sample.jpg"></a>
          <h2><a>Sample &amp; Album</a></h2>
        </li>
        <li class="wp-block-post">
          <a href="https://www.4khd.com/content/sample-album.html"><img src="https://pic.4khd.com/sample.jpg"></a>
          <h2><a>Duplicate</a></h2>
        </li>
        """

        let albums = HiddenSpaceAPI.parseAlbums(from: html)

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].title, "Sample & Album")
        XCTAssertEqual(albums[0].url.absoluteString, "https://www.4khd.com/content/sample-album.html")
        XCTAssertEqual(albums[0].coverURL.host, "img.4khd.com")
    }

    func test4KHDImageParserDeduplicatesLikelyImageURLs() {
        let html = """
        <div class="entry-content wp-block-post-content">
          <a href="https://img.4khd.com/a.jpg">A</a>
          <img src="https://pic.4khd.com/a.jpg">
          <img data-src="//pic.4khd.com/b.webp">
          <img srcset="https://img.4khd.com/c.jpg 1x, https://img.4khd.com/c-large.jpg 2x">
          <a href="https://www.4khd.com/content/not-image.html">Ignore</a>
        </div>
        <div class="page-link-box">pagination</div>
        """

        let urls = HiddenSpaceAPI.parseAlbumImages(from: html).map(\.absoluteString)

        XCTAssertEqual(
            urls,
            [
                "https://img.4khd.com/a.jpg",
                "https://img.4khd.com/b.webp",
                "https://img.4khd.com/c.jpg",
                "https://img.4khd.com/c-large.jpg"
            ]
        )
    }

    func testJavDBMovieParserNormalizesAndDeduplicatesMovies() throws {
        let html = """
        <a href="/v/abc123">
          <img data-src="/covers/abc123.jpg">
          <div class="uid">ABC-123</div>
          <div class="video-title">ABC-123 Sample Movie</div>
          <span class="value">Alice / Bob</span>
        </a>
        <a href="/v/abc123">
          <img src="/covers/abc123.jpg">
          <div class="uid">ABC-123</div>
          <div class="video-title">Duplicate</div>
        </a>
        """
        let baseURL = URL(string: "https://javdb.com/")!

        let movies = HiddenJavDBAPI.parseMovies(from: html, baseURL: baseURL)

        XCTAssertEqual(movies.count, 1)
        let movie = try XCTUnwrap(movies.first)
        XCTAssertEqual(movie.code, "ABC-123")
        XCTAssertEqual(movie.title, "Sample Movie")
        XCTAssertEqual(movie.url.absoluteString, "https://javdb.com/v/abc123")
        XCTAssertEqual(movie.coverURL.absoluteString, "https://javdb.com/covers/abc123.jpg")
    }

    func testJavDBRelativeURLNormalization() {
        let baseURL = URL(string: "https://javdb.com/search?q=abc")!

        let url = HiddenJavDBAPI.normalizedURL(from: "/v/abc123?locale=zh", relativeTo: baseURL)

        XCTAssertEqual(url?.absoluteString, "https://javdb.com/v/abc123?locale=zh")
        XCTAssertEqual(
            url.map(HiddenJavDBAPI.normalizeMovieURL)?.absoluteString,
            "https://javdb.com/v/abc123"
        )
    }

    func testMissAVDefaultHostUsesReachableMirror() {
        XCTAssertEqual(HiddenMissAVDomainConfiguration.defaultHost, "missav.ws")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: nil), "missav.ws")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: "https://missav.ai/cn"), "missav.ws")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: "https://missav.live/cn"), "missav.live")
    }

    func testMissAVPlaybackCandidatesKeepOriginalURLAndAddFallbackHosts() throws {
        let url = try XCTUnwrap(URL(string: "https://missav.ai/cn/abc-123"))

        let candidates = HiddenMissAVDomainConfiguration.playbackCandidateURLs(for: url)
        let candidateStrings = candidates.map(\.absoluteString)

        XCTAssertEqual(candidateStrings.first, "https://missav.ai/cn/abc-123")
        XCTAssertTrue(candidateStrings.contains("https://missav.ws/cn/abc-123"))
        XCTAssertTrue(candidateStrings.contains("https://missav.live/cn/abc-123"))
    }
}

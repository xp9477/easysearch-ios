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

    func testJavDBMarkdownFallbackParsesMovieAndCover() throws {
        let markdown = #"""
        Title: JavDB
        Markdown Content:
        [![Image 2](https://c0.jdbstatic.com/covers/yw/YwzwPz.jpg) **DLDSS-507** sample](https://javdb.com/v/YwzwPz "Sample Movie")
        """#

        let movies = HiddenJavDBAPI.parseMovies(
            from: markdown,
            baseURL: try XCTUnwrap(URL(string: "https://javdb.com/"))
        )

        let movie = try XCTUnwrap(movies.first)
        XCTAssertEqual(movie.code, "DLDSS-507")
        XCTAssertEqual(movie.title, "Sample Movie")
        XCTAssertEqual(movie.url.absoluteString, "https://javdb.com/v/YwzwPz")
        XCTAssertEqual(movie.coverURL.absoluteString, "https://c0.jdbstatic.com/covers/yw/YwzwPz.jpg")
    }

    func testJavDBMarkdownDetailParsesScreenshotsAndRelatedMovies() throws {
        let markdown = #"""
        Title: ABC-123 Sample Title | JavDB, Online information source
        Markdown Content:
        ## **ABC-123****Sample Title**
        **Released Date:**2026-07-01
        **Duration:**120 minute(s)
        **Maker:**[Sample Studio](https://javdb.com/makers/123)
        **Actor(s):**[Alice](https://javdb.com/actors/alice)**female**
        [![Image 1](https://c0.jdbstatic.com/samples/ab/ABC_s_0.jpg)](https://c0.jdbstatic.com/samples/ab/ABC_l_0.jpg)
        They are also starred
        [![Image 2](https://c0.jdbstatic.com/thumbs/de/DEF.jpg) DEF-456 Other Movie](https://javdb.com/v/def456 "Other Movie")
        You may also like
        [![Image 3](https://c0.jdbstatic.com/thumbs/gh/GHI.jpg) GHI-789 Recommended](https://javdb.com/v/ghi789 "Recommended")
        Review rules and regulations
        """#
        let movie = HiddenJavDBMovie(
            url: try XCTUnwrap(URL(string: "https://javdb.com/v/abc123")),
            code: "ABC-123",
            title: "Fallback",
            coverURL: try XCTUnwrap(URL(string: "https://c0.jdbstatic.com/covers/ab/ABC.jpg")),
            actresses: []
        )

        let images = HiddenJavDBAPI.parseMovieImages(from: markdown)
        let detail = HiddenJavDBAPI.parseMovieDetail(from: markdown, movie: movie)

        XCTAssertEqual(images.map(\.absoluteString), ["https://c0.jdbstatic.com/samples/ab/ABC_l_0.jpg"])
        XCTAssertEqual(detail.code, "ABC-123")
        XCTAssertEqual(detail.title, "Sample Title")
        XCTAssertEqual(detail.actresses, ["Alice"])
        XCTAssertEqual(detail.releaseDate, "2026-07-01")
        XCTAssertEqual(detail.durationMinutes, 120)
        XCTAssertEqual(detail.studio, "Sample Studio")
        XCTAssertEqual(detail.otherActressMovies.first?.code, "DEF-456")
        XCTAssertEqual(detail.recommendedMovies.first?.code, "GHI-789")
    }

    func testMissAVDefaultHostUsesReachableMirror() {
        XCTAssertEqual(HiddenMissAVDomainConfiguration.defaultHost, "missav123.com")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: nil), "missav123.com")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: "https://missav.ai/cn"), "missav123.com")
        XCTAssertEqual(HiddenMissAVDomainConfiguration.resolvedHost(from: "https://missav.live/cn"), "missav123.com")
    }

    func testMissAVPlaybackCandidatesKeepOriginalURLAndAddFallbackHosts() throws {
        let url = try XCTUnwrap(URL(string: "https://missav.ai/cn/abc-123"))

        let candidates = HiddenMissAVDomainConfiguration.playbackCandidateURLs(for: url)
        let candidateStrings = candidates.map(\.absoluteString)

        XCTAssertEqual(candidateStrings.first, "https://missav123.com/cn/abc-123")
        XCTAssertTrue(candidateStrings.contains("https://missav888.com/cn/abc-123"))
        XCTAssertFalse(candidateStrings.contains("https://missav.ai/cn/abc-123"))
    }

    func testMissAVPackedScriptExtractsPrimaryStream() throws {
        let html = #"""
        <script>
        eval(function(p,a,c,k,e,d){e=function(c){return c.toString(36)};if(!''.replace(/^/,String)){while(c--){d[c.toString(a)]=k[c]||c.toString(a)}k=[function(e){return d[e]}];e=function(){return'\\w+'};c=1};while(c--){if(k[c]){p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c])}}return p}('f=\'8://7.6/5-4-3-2-1/e.0\';d=\'8://7.6/5-4-3-2-1/c/9.0\';b=\'8://7.6/5-4-3-2-1/a/9.0\';',16,16,'m3u8|d20308920041|9c38|411c|45a1|0c73d32d|com|surrit|https|video|1280x720|source1280|842x480|source842|playlist|source'.split('|'),0,{}))
        </script>
        """#
        let pageURL = try XCTUnwrap(URL(string: "https://missav123.com/cn/ssis-001"))

        let streamURL = HiddenMissAVPlaybackResolver.extractPrimaryStreamURL(from: html, pageURL: pageURL)

        XCTAssertEqual(
            streamURL?.absoluteString,
            "https://surrit.com/0c73d32d-45a1-411c-9c38-d20308920041/842x480/video.m3u8"
        )
    }

    func testPlaybackIssuePresentationHandlesAgeConfirmation() {
        let issue = HiddenPlaybackIssuePresentation(
            message: "需要先完成 18+ 年龄确认，请在网页中确认后重试",
            errorCode: -35
        )

        XCTAssertEqual(issue.kind, .javDBAgeConfirmation)
        XCTAssertEqual(issue.primaryActionTitle, "已确认，重试")
        XCTAssertEqual(issue.secondaryActionTitle, "打开确认页")
    }

    func testPlaybackIssuePresentationHandlesMissAV451() {
        let issue = HiddenPlaybackIssuePresentation(
            message: "当前 MISSAV 域名不可用（451）",
            userInfo: ["HTTPStatusCode": 451]
        )

        XCTAssertEqual(issue.kind, .missAVUnavailable)
        XCTAssertEqual(issue.primaryActionTitle, "重试")
        XCTAssertEqual(issue.secondaryActionTitle, "修改域名")
    }

    func testPlaybackIssuePresentationDoesNotTreatJavDB451AsMissAV() {
        let issue = HiddenPlaybackIssuePresentation(message: "页面请求失败（451）")

        XCTAssertEqual(issue.kind, .network)
        XCTAssertNil(issue.secondaryActionTitle)
    }

    func testPlaybackIssuePresentationHandlesMissAVFallbackFailure() {
        let issue = HiddenPlaybackIssuePresentation(message: "MISSAV 页面请求失败")

        XCTAssertEqual(issue.kind, .missAVUnavailable)
    }

    func testPlaybackIssuePresentationHandlesNetworkFailure() {
        let issue = HiddenPlaybackIssuePresentation(message: "页面请求失败（500）")

        XCTAssertEqual(issue.kind, .network)
    }

    func testPlaybackIssuePresentationHandlesParsingFailure() {
        let issue = HiddenPlaybackIssuePresentation(message: "未解析到 MISSAV 视频流")

        XCTAssertEqual(issue.kind, .parsing)
    }
}

import Foundation

struct HiddenMissAVMoviePage: Hashable {
    let movies: [HiddenMissAVMovie]
    let nextPageURL: URL?
}

struct HiddenMissAVSection: Identifiable, Hashable {
    let title: String
    let moreURL: URL?
    let movies: [HiddenMissAVMovie]

    var id: String { title }
}

struct HiddenMissAVMovie: Identifiable, Codable, Hashable {
    let url: URL
    let code: String
    let title: String
    let coverURL: URL
    let previewVideoURL: URL?
    let durationText: String?
    let hasChineseSubtitle: Bool
    let hasEnglishSubtitle: Bool
    let isUncensored: Bool

    var id: String { url.absoluteString }

    var cloudMovieID: String {
        code.uppercased()
    }

    var displayCode: String {
        Self.normalizedDisplayCode(from: code)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return displayCode }

        let uppercaseTitle = trimmed.uppercased()
        let variants = Self.codeVariants(for: code) + Self.codeVariants(for: displayCode)

        for variant in variants where !variant.isEmpty && uppercaseTitle.hasPrefix(variant) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: variant.count)
            let remainder = trimmed[index...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -_:|/·").union(.whitespacesAndNewlines))
            if !remainder.isEmpty {
                return String(remainder)
            }
        }

        return trimmed
    }

    private static func normalizedDisplayCode(from rawCode: String) -> String {
        rawCode
            .uppercased()
            .replacingOccurrences(of: "-UNCENSORED-LEAK", with: "")
            .replacingOccurrences(of: "-CHINESE-SUBTITLE", with: "")
            .replacingOccurrences(of: "-ENGLISH-SUBTITLE", with: "")
    }

    private static func codeVariants(for rawCode: String) -> [String] {
        let normalizedCode = rawCode.uppercased()
        return [
            normalizedCode,
            normalizedCode.replacingOccurrences(of: "_", with: "-"),
            normalizedCode.replacingOccurrences(of: "-", with: "_"),
            normalizedCode.replacingOccurrences(of: "_", with: " "),
            normalizedCode.replacingOccurrences(of: "-", with: " "),
            normalizedCode.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        ]
        .filter { !$0.isEmpty }
        .sorted { $0.count > $1.count }
    }
}

struct HiddenMissAVFavoriteMarker: Identifiable, Codable, Hashable {
    let movieCode: String
    let positionSeconds: Double
    let createdAt: Date

    var id: String {
        Self.markerID(movieCode: movieCode, positionSeconds: positionSeconds)
    }

    var normalizedMovieCode: String {
        movieCode.uppercased()
    }

    func matchesSameMarker(as other: HiddenMissAVFavoriteMarker) -> Bool {
        normalizedMovieCode == other.normalizedMovieCode && abs(positionSeconds - other.positionSeconds) < 1
    }

    static func markerID(movieCode: String, positionSeconds: Double) -> String {
        "\(movieCode.uppercased())@\(String(format: "%.3f", positionSeconds))"
    }
}

struct HiddenMissAVMovieDetail: Hashable {
    let movie: HiddenMissAVMovie
    let releaseDate: String?
    let actresses: [String]
    let actors: [String]
    let tags: [String]
    let studio: String?
    let director: String?
    let label: String?
    let screenshots: [URL]
    let relatedMovies: [HiddenMissAVMovie]

    var actressesText: String {
        actresses.isEmpty ? "未知" : actresses.joined(separator: " / ")
    }

    var actorsText: String {
        actors.isEmpty ? "未知" : actors.joined(separator: " / ")
    }

    var tagsText: String {
        tags.isEmpty ? "暂无" : tags.joined(separator: " / ")
    }
}

struct HiddenMissAVWatchHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let movie: HiddenMissAVMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let positionSeconds: Double
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        movie: HiddenMissAVMovie,
        sourceName: String,
        streamURL: URL,
        refererURL: URL,
        positionSeconds: Double,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.movie = movie
        self.sourceName = sourceName
        self.streamURL = streamURL
        self.refererURL = refererURL
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
    }
}

import Foundation

struct HiddenAlbum: Identifiable, Codable, Hashable {
    let url: URL
    let title: String
    let coverURL: URL

    var id: String { url.absoluteString }
}

struct HiddenJavDBMovie: Identifiable, Codable, Hashable {
    let url: URL
    let code: String
    let title: String
    let coverURL: URL
    let actresses: [String]

    var id: String { url.absoluteString }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? code : trimmed
    }

    var actressesText: String {
        actresses.isEmpty ? "未知" : actresses.joined(separator: " / ")
    }
}

struct HiddenJavDBFavoritePlayback: Identifiable, Codable, Hashable {
    let id: UUID
    let movie: HiddenJavDBMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let positionSeconds: Double
    let createdAt: Date

    init(
        id: UUID = UUID(),
        movie: HiddenJavDBMovie,
        sourceName: String,
        streamURL: URL,
        refererURL: URL,
        positionSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.movie = movie
        self.sourceName = sourceName
        self.streamURL = streamURL
        self.refererURL = refererURL
        self.positionSeconds = positionSeconds
        self.createdAt = createdAt
    }
}

struct HiddenJavDBFavoritePlaybackSaveContext {
    let savedPlayback: HiddenJavDBFavoritePlayback
    let replacedPlayback: HiddenJavDBFavoritePlayback?
    let markerPositions: [Double]
}

extension HiddenJavDBFavoritePlayback {
    func matchesSamePlayback(as other: HiddenJavDBFavoritePlayback) -> Bool {
        movie.id == other.movie.id &&
        sourceName == other.sourceName &&
        streamURL.absoluteString == other.streamURL.absoluteString &&
        abs(positionSeconds - other.positionSeconds) < 2
    }
}

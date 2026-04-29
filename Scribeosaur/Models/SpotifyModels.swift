import Foundation

// MARK: - API Response Types

struct SpotifyUser: Decodable {
    let id: String
    let displayName: String?
    let email: String?
    let country: String?
    let images: [SpotifyImage]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case country
        case images
    }
}

struct SpotifyImage: Decodable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyShow: Decodable, Identifiable {
    let id: String
    let name: String
    let publisher: String
    let description: String
    let images: [SpotifyImage]
    let totalEpisodes: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, publisher, description, images
        case totalEpisodes = "total_episodes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
        totalEpisodes = try container.decodeIfPresent(Int.self, forKey: .totalEpisodes)
    }

    var bestImageURL: URL? {
        guard let urlString = images.first(where: { ($0.width ?? 0) <= 300 })?.url
                ?? images.last?.url else { return nil }
        return URL(string: urlString)
    }
}

struct SpotifyEpisode: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let durationMs: Int
    let releaseDate: String
    let images: [SpotifyImage]
    let resumePoint: SpotifyResumePoint?
    var show: SpotifyShow?
    let externalUrls: ExternalURLs?

    enum CodingKeys: String, CodingKey {
        case id, name, description, images, show
        case durationMs = "duration_ms"
        case releaseDate = "release_date"
        case resumePoint = "resume_point"
        case externalUrls = "external_urls"
    }

    struct ExternalURLs: Decodable {
        let spotify: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
        resumePoint = try container.decodeIfPresent(SpotifyResumePoint.self, forKey: .resumePoint)
        show = try container.decodeIfPresent(SpotifyShow.self, forKey: .show)
        externalUrls = try container.decodeIfPresent(ExternalURLs.self, forKey: .externalUrls)
    }

    var durationSeconds: Double {
        Double(durationMs) / 1000.0
    }

    var formattedDuration: String {
        let totalSeconds = Int(durationSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var isFullyPlayed: Bool {
        if resumePoint?.fullyPlayed == true { return true }
        guard let resumeMs = resumePoint?.resumePositionMs,
              resumeMs > 0, durationMs > 0 else { return false }
        return Double(resumeMs) / Double(durationMs) >= 0.9
    }

    var bestImageURL: URL? {
        let episodeImage = images.first(where: { ($0.width ?? 0) <= 300 })?.url
            ?? images.last?.url
        let showImage = show?.bestImageURL?.absoluteString
        guard let urlString = episodeImage ?? showImage else { return nil }
        return URL(string: urlString)
    }
}

struct SpotifyResumePoint: Decodable {
    let fullyPlayed: Bool
    let resumePositionMs: Int

    enum CodingKeys: String, CodingKey {
        case fullyPlayed = "fully_played"
        case resumePositionMs = "resume_position_ms"
    }
}

struct SpotifyPaginatedResponse<T: Decodable>: Decodable {
    let items: [T]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?

    var hasMore: Bool { next != nil }

    enum CodingKeys: String, CodingKey {
        case items, total, limit, offset, next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([T].self, forKey: .items) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 50
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
}

// Wrapper for saved shows which nests the show inside a "show" key
struct SpotifySavedShow: Decodable {
    let show: SpotifyShow
}

// Wrapper for saved episodes which nests the episode inside an "episode" key
struct SpotifySavedEpisode: Decodable {
    let episode: SpotifyEpisode
}

// Response from GET /v1/episodes?ids=...
struct SpotifyBatchEpisodesResponse: Decodable {
    let episodes: [SpotifyEpisode]
}

// MARK: - RSS Types

struct RSSEpisode {
    let title: String
    let audioURL: URL
    let durationSeconds: Double?
    let publishDate: Date?
    let guid: String?
}

// MARK: - URL Parsing

enum SpotifyURLTarget {
    case episode(id: String)
    case show(id: String)

    static func parse(from urlString: String) -> SpotifyURLTarget? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              host.contains("spotify.com") else { return nil }

        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3 else { return nil }

        let type = pathComponents[1]
        let id = pathComponents[2]

        switch type {
        case "episode":
            return .episode(id: id)
        case "show":
            return .show(id: id)
        default:
            return nil
        }
    }
}

// MARK: - Error Types

enum SpotifyServiceError: LocalizedError {
    case notAuthenticated
    case clientIDMissing
    case authorizationFailed(String)
    case tokenRefreshFailed
    case apiError(Int, String)
    case noRSSFeedFound(String)
    case spotifyExclusive(String)
    case episodeNotFoundInRSS(String)
    case downloadFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not signed in to Spotify"
        case .clientIDMissing:
            "Spotify Client ID not configured. Add it in Settings."
        case .authorizationFailed(let detail):
            "Spotify authorization failed: \(detail)"
        case .tokenRefreshFailed:
            "Failed to refresh Spotify access token"
        case .apiError(let code, let message):
            "Spotify API error (\(code)): \(message)"
        case .noRSSFeedFound(let showName):
            "No public RSS feed found for \"\(showName)\""
        case .spotifyExclusive(let showName):
            "Cannot download \"\(showName)\" — Spotify Exclusive content has no public RSS feed"
        case .episodeNotFoundInRSS(let title):
            "Could not match episode \"\(title)\" in the RSS feed"
        case .downloadFailed(let detail):
            "Download failed: \(detail)"
        case .invalidURL:
            "Invalid Spotify URL"
        }
    }
}

// MARK: - Queue Metadata

struct SpotifyQueueMetadata {
    let episodeID: String
    let showID: String
    let showName: String
    let publisherName: String
    let episodeDurationMs: Int
}

// MARK: - Auth Token Types

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

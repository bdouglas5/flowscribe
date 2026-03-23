import Foundation

enum SpotifyAPIService {
    private static let baseURL = "https://api.spotify.com/v1"

    // MARK: - Shows (Podcasts)

    static func getSavedShows(
        accessToken: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPaginatedResponse<SpotifySavedShow> {
        let url = "\(baseURL)/me/shows?limit=\(limit)&offset=\(offset)"
        return try await get(url: url, accessToken: accessToken)
    }

    static func getShow(
        id: String,
        accessToken: String
    ) async throws -> SpotifyShow {
        let url = "\(baseURL)/shows/\(id)"
        return try await get(url: url, accessToken: accessToken)
    }

    static func getShowEpisodes(
        showID: String,
        accessToken: String,
        market: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPaginatedResponse<SpotifyEpisode> {
        var url = "\(baseURL)/shows/\(showID)/episodes?limit=\(limit)&offset=\(offset)"
        if let market {
            url += "&market=\(market)"
        }
        return try await get(url: url, accessToken: accessToken)
    }

    // MARK: - Episodes

    static func getEpisode(
        id: String,
        accessToken: String
    ) async throws -> SpotifyEpisode {
        let url = "\(baseURL)/episodes/\(id)"
        return try await get(url: url, accessToken: accessToken)
    }

    static func getEpisodes(
        ids: [String],
        accessToken: String,
        market: String? = nil
    ) async throws -> [SpotifyEpisode] {
        guard !ids.isEmpty else { return [] }
        let joined = ids.prefix(50).joined(separator: ",")
        var url = "\(baseURL)/episodes?ids=\(joined)"
        if let market {
            url += "&market=\(market)"
        }
        let response: SpotifyBatchEpisodesResponse = try await get(url: url, accessToken: accessToken)
        return response.episodes
    }

    static func getSavedEpisodes(
        accessToken: String,
        market: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SpotifyPaginatedResponse<SpotifySavedEpisode> {
        var url = "\(baseURL)/me/episodes?limit=\(limit)&offset=\(offset)"
        if let market {
            url += "&market=\(market)"
        }
        return try await get(url: url, accessToken: accessToken)
    }

    // MARK: - Search

    static func searchShows(
        query: String,
        accessToken: String,
        limit: Int = 10
    ) async throws -> [SpotifyShow] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let url = "\(baseURL)/search?q=\(encoded)&type=show&limit=\(limit)"

        struct SearchResponse: Decodable {
            let shows: SpotifyPaginatedResponse<SpotifyShow>
        }

        let response: SearchResponse = try await get(url: url, accessToken: accessToken)
        return response.shows.items
    }

    // MARK: - URL Detection

    static func isSpotifyURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let host = url.host?.lowercased() else { return false }
        return host.contains("spotify.com")
    }

    static func firstSpotifyURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSpotifyURL(trimmed) {
            return trimmed
        }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            let candidate = String(trimmed[matchRange])
            if isSpotifyURL(candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Pagination

    static func getAllPages<T: Decodable>(
        firstPage: SpotifyPaginatedResponse<T>,
        accessToken: String
    ) async throws -> [T] {
        var allItems = firstPage.items
        var nextURL = firstPage.next

        while let urlString = nextURL {
            let page: SpotifyPaginatedResponse<T> = try await get(url: urlString, accessToken: accessToken)
            allItems.append(contentsOf: page.items)
            nextURL = page.next
        }

        return allItems
    }

    // MARK: - Generic Request

    private static func get<T: Decodable>(url: String, accessToken: String, maxRetries: Int = 3) async throws -> T {
        guard let requestURL = URL(string: url) else {
            throw SpotifyServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        for attempt in 0..<maxRetries {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpotifyServiceError.apiError(0, "Invalid response")
            }

            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 2.0
                let delay = max(retryAfter, 1.0)
                AppLogger.info("SpotifyAPI", "Rate limited (429), retry \(attempt + 1)/\(maxRetries) after \(delay)s for \(url)")
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw SpotifyServiceError.apiError(httpResponse.statusCode, body)
            }

            return try decodeResponse(data: data, url: url)
        }

        throw SpotifyServiceError.apiError(429, "Rate limited after \(maxRetries) retries")

    }

    private static func decodeResponse<T: Decodable>(data: Data, url: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let detail = "Missing key '\(key.stringValue)' at path '\(path)'"
            AppLogger.error("SpotifyAPI", "Decoding failed for \(url): \(detail)")
            throw SpotifyServiceError.apiError(200, detail)
        } catch let DecodingError.typeMismatch(type, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let detail = "Type mismatch for \(type) at path '\(path)'"
            AppLogger.error("SpotifyAPI", "Decoding failed for \(url): \(detail)")
            throw SpotifyServiceError.apiError(200, detail)
        } catch let DecodingError.valueNotFound(type, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let detail = "Null value for \(type) at path '\(path)'"
            AppLogger.error("SpotifyAPI", "Decoding failed for \(url): \(detail)")
            throw SpotifyServiceError.apiError(200, detail)
        } catch {
            AppLogger.error("SpotifyAPI", "Decoding failed for \(url): \(error)")
            throw error
        }
    }
}

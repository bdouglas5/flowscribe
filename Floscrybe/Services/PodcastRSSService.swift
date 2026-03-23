import Foundation

enum PodcastRSSService {

    // MARK: - RSS Feed Resolution via iTunes Search API

    static func resolveRSSFeed(showName: String, publisher: String? = nil) async throws -> URL {
        AppLogger.info("RSS", "Resolving RSS feed for \"\(showName)\" (publisher: \(publisher ?? "nil"))")

        // Strategy 1: show name only
        if let result = try? await searchiTunes(query: showName, publisher: publisher), result.score > 0.5 {
            AppLogger.info("RSS", "Strategy 1 (show name) matched: \(result.url) (score: \(String(format: "%.2f", result.score)))")
            return result.url
        }
        AppLogger.info("RSS", "Strategy 1 (show name) failed for \"\(showName)\"")

        // Strategy 2: show name + publisher
        if let pub = publisher {
            if let result = try? await searchiTunes(query: "\(showName) \(pub)", publisher: publisher), result.score > 0.5 {
                AppLogger.info("RSS", "Strategy 2 (name+publisher) matched: \(result.url) (score: \(String(format: "%.2f", result.score)))")
                return result.url
            }
            AppLogger.info("RSS", "Strategy 2 (name+publisher) failed for \"\(showName) \(pub)\"")
        }

        // Strategy 3: stripped name (remove "Podcast", "Show", etc.)
        let stripped = showName
            .replacingOccurrences(of: "(?i)\\s*(podcast|show|radio|pod)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if stripped != showName, !stripped.isEmpty {
            if let result = try? await searchiTunes(query: stripped, publisher: publisher), result.score > 0.5 {
                AppLogger.info("RSS", "Strategy 3 (stripped name) matched: \(result.url) (score: \(String(format: "%.2f", result.score)))")
                return result.url
            }
            AppLogger.info("RSS", "Strategy 3 (stripped name) failed for \"\(stripped)\"")
        }

        // Strategy 4: lower threshold (0.3) as last resort with original name
        if let result = try? await searchiTunes(query: showName, publisher: publisher), result.score > 0.3 {
            AppLogger.info("RSS", "Strategy 4 (low threshold) matched: \(result.url) (score: \(String(format: "%.2f", result.score)))")
            return result.url
        }

        AppLogger.error("RSS", "All strategies failed to resolve RSS feed for \"\(showName)\"")
        throw SpotifyServiceError.noRSSFeedFound(showName)
    }

    private static func searchiTunes(
        query: String,
        publisher: String?
    ) async throws -> (url: URL, score: Double)? {
        let searchTerm = query
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let searchURL = URL(
            string: "https://itunes.apple.com/search?term=\(searchTerm)&media=podcast&entity=podcast&limit=10"
        )!

        let (data, _) = try await URLSession.shared.data(from: searchURL)

        struct ITunesResult: Decodable {
            let collectionName: String?
            let artistName: String?
            let feedUrl: String?
        }

        struct ITunesResponse: Decodable {
            let resultCount: Int
            let results: [ITunesResult]
        }

        let response = try JSONDecoder().decode(ITunesResponse.self, from: data)
        guard !response.results.isEmpty else { return nil }

        let normalizedQuery = normalize(query)
        let normalizedPublisher = publisher.map { normalize($0) }

        var bestURL: URL?
        var bestScore = 0.0

        for result in response.results {
            guard let feedUrl = result.feedUrl, !feedUrl.isEmpty,
                  let url = URL(string: feedUrl) else { continue }

            var score = 0.0
            if let collectionName = result.collectionName {
                score += similarity(normalize(collectionName), normalizedQuery)
            }
            if let normalizedPublisher, let artistName = result.artistName {
                score += similarity(normalize(artistName), normalizedPublisher) * 0.5
            }

            if score > bestScore {
                bestScore = score
                bestURL = url
            }
        }

        guard let url = bestURL else { return nil }
        return (url: url, score: bestScore)
    }

    // MARK: - RSS Feed Parsing

    static func fetchEpisodes(feedURL: URL) async throws -> [RSSEpisode] {
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let parser = RSSXMLParser(data: data)
        return parser.parse()
    }

    // MARK: - Episode Matching

    static func matchEpisode(
        spotifyTitle: String,
        spotifyDurationSeconds: Double,
        in rssEpisodes: [RSSEpisode]
    ) -> RSSEpisode? {
        let normalizedTarget = normalize(spotifyTitle)
        AppLogger.info("RSS", "Matching episode \"\(spotifyTitle)\" (duration: \(Int(spotifyDurationSeconds))s) against \(rssEpisodes.count) RSS episodes")

        var bestMatch: RSSEpisode?
        var bestScore = 0.0

        for episode in rssEpisodes {
            let normalizedRSS = normalize(episode.title)
            var score = 0.0

            // Exact normalized title match
            if normalizedRSS == normalizedTarget {
                score = 1.0
            }
            // Contains match — one title contains the other
            else if normalizedRSS.contains(normalizedTarget) || normalizedTarget.contains(normalizedRSS) {
                let shorter = min(normalizedRSS.count, normalizedTarget.count)
                let longer = max(normalizedRSS.count, normalizedTarget.count)
                score = longer > 0 ? Double(shorter) / Double(longer) : 0.0
                score = max(score, 0.6) // contains match gets at least 0.6
            }
            // Fallback: Jaccard similarity on words
            else {
                score = similarity(normalizedRSS, normalizedTarget)
            }

            // Duration bonus
            if let rssDuration = episode.durationSeconds, rssDuration > 0 {
                let diff = abs(rssDuration - spotifyDurationSeconds)
                if diff < 60 {
                    score += 0.3
                } else if diff < 300 {
                    score += 0.1
                }
            }

            if score > bestScore {
                bestScore = score
                bestMatch = episode
            }
        }

        if let match = bestMatch, bestScore > 0.4 {
            AppLogger.info("RSS", "Matched episode: \"\(match.title)\" (score: \(String(format: "%.2f", bestScore)))")
            return match
        }

        AppLogger.error("RSS", "No match found for \"\(spotifyTitle)\" (best score: \(String(format: "%.2f", bestScore)))")
        return nil
    }

    // MARK: - Audio Download

    static func downloadAudio(
        episodeAudioURL: URL,
        fileName: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        AppLogger.info("RSS", "Downloading podcast audio from \(episodeAudioURL.absoluteString)")

        let outputURL = StoragePaths.temp.appendingPathComponent(
            sanitizedFileName(from: fileName) + "." + (episodeAudioURL.pathExtension.isEmpty ? "mp3" : episodeAudioURL.pathExtension)
        )

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempURL, response) = try await session.download(from: episodeAudioURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw SpotifyServiceError.downloadFailed(
                "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            )
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.moveItem(at: tempURL, to: outputURL)

        AppLogger.info("RSS", "Downloaded podcast audio to \(outputURL.path)")
        return outputURL
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        // Check containment
        if a.contains(b) || b.contains(a) {
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            return Double(shorter) / Double(longer)
        }

        // Jaccard similarity on words
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    private static func sanitizedFileName(from title: String) -> String {
        String(
            title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )
    }
}

// MARK: - RSS XML Parser

private final class RSSXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var episodes: [RSSEpisode] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentAudioURL: String?
    private var currentDuration: String?
    private var currentPubDate: String?
    private var currentGUID = ""
    private var isInsideItem = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [RSSEpisode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return episodes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentAudioURL = nil
            currentDuration = nil
            currentPubDate = nil
            currentGUID = ""
        }
        if isInsideItem, elementName == "enclosure" {
            if let url = attributeDict["url"],
               attributeDict["type"]?.hasPrefix("audio") == true || url.hasSuffix(".mp3") || url.hasSuffix(".m4a") {
                currentAudioURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "itunes:duration":
            currentDuration = (currentDuration ?? "") + string
        case "pubDate":
            currentPubDate = (currentPubDate ?? "") + string
        case "guid":
            currentGUID += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", isInsideItem {
            if let audioURLString = currentAudioURL, let audioURL = URL(string: audioURLString) {
                episodes.append(RSSEpisode(
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    audioURL: audioURL,
                    durationSeconds: parseDuration(currentDuration),
                    publishDate: parseDate(currentPubDate),
                    guid: currentGUID.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            isInsideItem = false
        }
        if elementName == currentElement {
            currentElement = ""
        }
    }

    private func parseDuration(_ string: String?) -> Double? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }

        // Format: seconds (e.g., "3600")
        if let seconds = Double(string) {
            return seconds
        }

        // Format: HH:MM:SS or MM:SS
        let parts = string.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:
            return parts[0] * 60 + parts[1]
        default:
            return nil
        }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // RFC 2822 format used in RSS
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string)
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled in the async call
    }
}

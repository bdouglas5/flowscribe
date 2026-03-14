import Foundation

enum YTDLPError: LocalizedError {
    case invalidURL
    case unsupportedRemoteSource
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .unsupportedRemoteSource: "Unsupported remote source"
        case .downloadFailed(let msg): "Download failed: \(msg)"
        }
    }
}

enum YTDLPService {
    private struct YTDLPMetadata: Decodable {
        let title: String?
        let entries: [Entry]?

        struct Entry: Decodable {
            let id: String?
            let url: String?
            let title: String?
            let webpageURL: String?

            enum CodingKeys: String, CodingKey {
                case id
                case url
                case title
                case webpageURL = "webpage_url"
            }
        }
    }

    static func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let host = url.host?.lowercased() else { return false }
        return isYouTubeHost(host)
    }

    static func firstSupportedURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidURL(trimmed) {
            return trimmed
        }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            let candidate = String(trimmed[matchRange])
            if isValidURL(candidate) {
                return candidate
            }
        }

        return nil
    }

    static func resolveQueueItems(
        url: String,
        speakerDetection: Bool,
        speakerNames: [String],
        dateRange: AppSettings.YouTubeDateRange = .allTime
    ) async throws -> [QueueItem] {
        AppLogger.info("YTDLP", "Resolving remote URL \(url)")
        guard
            let sourceURL = URL(string: url),
            let remoteSource = remoteSource(for: sourceURL)
        else {
            throw YTDLPError.invalidURL
        }

        switch remoteSource {
        case .youtube:
            if let collection = try await resolveYouTubeCollection(
                url: sourceURL,
                speakerDetection: speakerDetection,
                speakerNames: speakerNames,
                dateRange: dateRange
            ) {
                return collection
            }

            return [
                QueueItem(
                    title: url,
                    sourceURL: sourceURL,
                    sourceType: .url,
                    remoteSource: .youtube,
                    speakerDetection: speakerDetection,
                    speakerNames: speakerNames
                )
            ]
        case .spotify:
            throw YTDLPError.unsupportedRemoteSource
        }
    }

    static func downloadAudio(for item: QueueItem) async throws -> (audioFile: URL, title: String) {
        guard let sourceURL = item.sourceURL else {
            throw YTDLPError.invalidURL
        }

        AppLogger.info("YTDLP", "Downloading audio for \(sourceURL.absoluteString)")
        let remoteSource = item.remoteSource ?? remoteSource(for: sourceURL)
        switch remoteSource {
        case .youtube?:
            return try await downloadYouTubeAudio(url: sourceURL.absoluteString)
        case .spotify?, nil:
            throw YTDLPError.unsupportedRemoteSource
        }
    }

    static func fetchTitle(url: String) async throws -> String {
        let output = try await SubprocessRunner.runChecked(
            executable: StoragePaths.ytdlpBinary,
            arguments: ["--get-title", "--no-playlist", url]
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveYouTubeCollection(
        url: URL,
        speakerDetection: Bool,
        speakerNames: [String],
        dateRange: AppSettings.YouTubeDateRange = .allTime
    ) async throws -> [QueueItem]? {
        guard isLikelyYouTubeCollection(url) else { return nil }
        AppLogger.info("YTDLP", "Resolving YouTube collection \(url.absoluteString)")

        var arguments: [String]
        if dateRange == .allTime {
            arguments = ["--flat-playlist", "--dump-single-json", "--no-warnings", url.absoluteString]
        } else {
            arguments = [
                "--dateafter", dateRange.ytdlpDateString,
                "--dump-single-json", "--no-download", "--no-warnings",
                url.absoluteString
            ]
        }

        let output = try await SubprocessRunner.runChecked(
            executable: StoragePaths.ytdlpBinary,
            arguments: arguments
        )

        guard let data = output.data(using: .utf8) else {
            throw YTDLPError.downloadFailed("Invalid collection metadata")
        }

        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: data)
        let entries = (metadata.entries ?? []).compactMap { entry -> QueueItem? in
            guard let itemURL = youtubeEntryURL(from: entry), let sourceURL = URL(string: itemURL) else {
                return nil
            }

            return QueueItem(
                title: entry.title ?? itemURL,
                sourceURL: sourceURL,
                sourceType: .url,
                remoteSource: .youtube,
                collectionID: UUID().uuidString,
                collectionTitle: metadata.title ?? fallbackCollectionTitle(for: url),
                collectionType: collectionType(for: url),
                collectionItemIndex: nil,
                speakerDetection: speakerDetection,
                speakerNames: speakerNames
            )
        }

        guard !entries.isEmpty else { return nil }
        AppLogger.info("YTDLP", "Resolved \(entries.count) entries for collection \(url.absoluteString)")

        let collectionID = UUID().uuidString
        let title = metadata.title ?? fallbackCollectionTitle(for: url)
        let type = collectionType(for: url)

        return entries.enumerated().map { index, item in
            QueueItem(
                title: item.title,
                sourceURL: item.sourceURL,
                sourceType: item.sourceType,
                remoteSource: item.remoteSource,
                collectionID: collectionID,
                collectionTitle: title,
                collectionType: type,
                collectionItemIndex: index + 1,
                speakerDetection: item.speakerDetection,
                speakerNames: item.speakerNames
            )
        }
    }

    private static func downloadYouTubeAudio(url: String) async throws -> (audioFile: URL, title: String) {
        AppLogger.info("YTDLP", "Downloading YouTube audio \(url)")
        let title = try await fetchTitle(url: url)
        let sanitizedTitle = sanitizedOutputName(from: title)

        let outputTemplate = StoragePaths.temp
            .appendingPathComponent("\(sanitizedTitle).%(ext)s").path

        _ = try await SubprocessRunner.runChecked(
            executable: StoragePaths.ytdlpBinary,
            arguments: [
                "-x",
                "--audio-format", "wav",
                "--no-playlist",
                "-o", outputTemplate,
                "--ffmpeg-location", StoragePaths.bin.path,
                url
            ]
        )

        if let audioFile = latestDownloadedAudio(preferredBaseName: sanitizedTitle) {
            AppLogger.info("YTDLP", "Downloaded YouTube audio to \(audioFile.path)")
            return (audioFile, title)
        }

        throw YTDLPError.downloadFailed("No audio file found after download")
    }

    private static func currentAudioFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: StoragePaths.temp,
            includingPropertiesForKeys: [.creationDateKey]
        ).filter {
            FFmpegService.allSupportedExtensions.contains($0.pathExtension.lowercased())
        }) ?? []
    }

    private static func latestDownloadedAudio(preferredBaseName: String?) -> URL? {
        let audioFiles = currentAudioFiles()
        if let preferredBaseName,
           let exactMatch = audioFiles.first(where: { $0.deletingPathExtension().lastPathComponent == preferredBaseName }) {
            return exactMatch
        }

        return audioFiles.sorted(by: compareByCreationDate).first
    }

    private static func compareByCreationDate(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return lhsDate > rhsDate
    }

    private static func remoteSource(for url: URL) -> Transcript.RemoteSource? {
        guard let host = url.host?.lowercased() else { return nil }
        if isYouTubeHost(host) { return .youtube }
        return nil
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        let supportedHosts = [
            "youtube.com", "www.youtube.com", "youtu.be",
            "m.youtube.com", "music.youtube.com"
        ]
        return supportedHosts.contains(where: { host.contains($0) })
    }

    private static func isLikelyYouTubeCollection(_ url: URL) -> Bool {
        isYouTubePlaylistURL(url) || isYouTubeChannelURL(url)
    }

    private static func isYouTubePlaylistURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains(where: { $0.name == "list" && !($0.value ?? "").isEmpty }) == true
            || url.path.lowercased().contains("/playlist")
    }

    private static func isYouTubeChannelURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasPrefix("/channel/")
            || path.hasPrefix("/@")
            || path.hasPrefix("/c/")
            || path.hasPrefix("/user/")
    }

    private static func collectionType(for url: URL) -> Transcript.CollectionType {
        isYouTubeChannelURL(url) ? .channel : .playlist
    }

    private static func fallbackCollectionTitle(for url: URL) -> String {
        switch collectionType(for: url) {
        case .playlist: "YouTube Playlist"
        case .channel: "YouTube Channel"
        }
    }

    private static func youtubeEntryURL(from entry: YTDLPMetadata.Entry) -> String? {
        if let webpageURL = entry.webpageURL, webpageURL.hasPrefix("http") {
            return webpageURL
        }
        if let url = entry.url, url.hasPrefix("http") {
            return url
        }
        if let id = entry.id ?? entry.url, !id.isEmpty {
            return "https://www.youtube.com/watch?v=\(id)"
        }
        return nil
    }

    private static func sanitizedOutputName(from title: String) -> String {
        String(
            title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )
    }
}

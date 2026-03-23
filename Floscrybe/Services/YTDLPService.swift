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
        let channel: String?
        let channelID: String?
        let uploader: String?
        let uploaderID: String?
        let thumbnail: String?

        struct Entry: Decodable {
            let id: String?
            let url: String?
            let title: String?
            let webpageURL: String?
            let entries: [Entry]?
            let thumbnail: String?

            enum CodingKeys: String, CodingKey {
                case id
                case url
                case title
                case webpageURL = "webpage_url"
                case entries
                case thumbnail
            }
        }

        enum CodingKeys: String, CodingKey {
            case title, entries, channel, uploader, thumbnail
            case channelID = "channel_id"
            case uploaderID = "uploader_id"
        }
    }

    struct VideoMetadata {
        let title: String
        let channelName: String?
        let channelID: String?
        let thumbnailURL: String?
    }

    /// Recursively walks nested entry structures (e.g. channel tabs containing sub-entries),
    /// returning only leaf entries — those without their own sub-entries.
    private static func flattenEntries(_ entries: [YTDLPMetadata.Entry]) -> [YTDLPMetadata.Entry] {
        var result: [YTDLPMetadata.Entry] = []
        for entry in entries {
            if let nested = entry.entries, !nested.isEmpty {
                result.append(contentsOf: flattenEntries(nested))
            } else {
                result.append(entry)
            }
        }
        return result
    }

    /// Returns true for URLs that are unambiguously collections (channels, /playlist paths),
    /// as opposed to watch URLs that happen to include a list= parameter.
    private static func isPureCollectionURL(_ url: URL) -> Bool {
        if isYouTubeChannelURL(url) { return true }
        let path = url.path.lowercased()
        if path.contains("/playlist") { return true }
        // watch?v=xxx&list=yyy is ambiguous — not a pure collection
        return false
    }

    /// Checks if a string looks like a YouTube video ID (8-15 alphanumeric chars, hyphens, underscores).
    private static func looksLikeVideoID(_ value: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9_-]{8,15}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
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

    static func fetchVideoMetadata(url: String) async throws -> VideoMetadata {
        let output = try await SubprocessRunner.runChecked(
            executable: StoragePaths.ytdlpBinary,
            arguments: [
                "--dump-single-json",
                "--no-playlist",
                "--no-download",
                "--no-warnings",
                url
            ],
            timeout: 30
        )
        guard let data = output.data(using: .utf8) else {
            throw YTDLPError.downloadFailed("Invalid metadata response")
        }
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: data)
        return VideoMetadata(
            title: metadata.title ?? url,
            channelName: metadata.channel ?? metadata.uploader,
            channelID: metadata.channelID ?? metadata.uploaderID,
            thumbnailURL: metadata.thumbnail
        )
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

            // Single video — always attempt full metadata; fall back to title-only
            let videoMeta: VideoMetadata
            do {
                videoMeta = try await fetchVideoMetadata(url: url)
            } catch {
                AppLogger.error("YTDLP", "Metadata fetch failed for \(url): \(error.localizedDescription)")
                let title = (try? await fetchTitle(url: url)) ?? url
                videoMeta = VideoMetadata(title: title, channelName: nil, channelID: nil, thumbnailURL: nil)
            }

            AppLogger.info("YTDLP", "Single video metadata: channel=\(videoMeta.channelName ?? "nil"), channelID=\(videoMeta.channelID ?? "nil")")

            let thumbnail = videoMeta.thumbnailURL ?? youtubeThumbnailURL(from: sourceURL)

            return [
                QueueItem(
                    title: videoMeta.title,
                    sourceURL: sourceURL,
                    sourceType: .url,
                    remoteSource: .youtube,
                    collectionID: videoMeta.channelID,
                    collectionTitle: videoMeta.channelName,
                    collectionType: videoMeta.channelID != nil ? .channel : nil,
                    thumbnailURL: thumbnail,
                    speakerDetection: speakerDetection,
                    speakerNames: speakerNames
                )
            ]
        case .spotify:
            // Spotify is handled by SpotifyPodcastService before reaching YTDLPService
            throw YTDLPError.unsupportedRemoteSource
        }
    }

    static func downloadAudio(
        for item: QueueItem,
        onProgress: (@Sendable (Double, String?) -> Void)? = nil
    ) async throws -> (audioFile: URL, title: String) {
        guard let sourceURL = item.sourceURL else {
            throw YTDLPError.invalidURL
        }

        AppLogger.info("YTDLP", "Downloading audio for \(sourceURL.absoluteString)")
        let remoteSource = item.remoteSource ?? remoteSource(for: sourceURL)
        switch remoteSource {
        case .youtube?:
            return try await downloadYouTubeAudio(url: sourceURL.absoluteString, onProgress: onProgress)
        case .spotify?:
            // Spotify is handled by SpotifyPodcastService before reaching YTDLPService
            throw YTDLPError.unsupportedRemoteSource
        case nil:
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
                "--flat-playlist",
                "--dateafter", dateRange.ytdlpDateString,
                "--dump-single-json", "--no-warnings",
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
        let rawEntries = metadata.entries ?? []
        let flattened = flattenEntries(rawEntries)
        AppLogger.info("YTDLP", "Raw entries: \(rawEntries.count), flattened: \(flattened.count)")

        let entries = flattened.compactMap { entry -> QueueItem? in
            guard let itemURL = youtubeEntryURL(from: entry), let sourceURL = URL(string: itemURL) else {
                return nil
            }

            let thumbnailURL = entry.thumbnail ?? youtubeThumbnailURL(from: sourceURL)

            return QueueItem(
                title: entry.title ?? itemURL,
                sourceURL: sourceURL,
                sourceType: .url,
                remoteSource: .youtube,
                collectionID: UUID().uuidString,
                collectionTitle: metadata.title ?? fallbackCollectionTitle(for: url),
                collectionType: collectionType(for: url),
                collectionItemIndex: nil,
                thumbnailURL: thumbnailURL,
                speakerDetection: speakerDetection,
                speakerNames: speakerNames
            )
        }

        AppLogger.info("YTDLP", "Resolved \(entries.count) queue items from \(flattened.count) flattened entries")

        guard !entries.isEmpty else {
            if isPureCollectionURL(url) {
                throw YTDLPError.downloadFailed("No videos found in this \(isYouTubeChannelURL(url) ? "channel" : "playlist")")
            }
            return nil
        }
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
                thumbnailURL: item.thumbnailURL,
                speakerDetection: item.speakerDetection,
                speakerNames: item.speakerNames
            )
        }
    }

    private static func downloadYouTubeAudio(
        url: String,
        onProgress: (@Sendable (Double, String?) -> Void)? = nil
    ) async throws -> (audioFile: URL, title: String) {
        AppLogger.info("YTDLP", "Downloading YouTube audio \(url)")
        let title = try await fetchTitle(url: url)
        let sanitizedTitle = sanitizedOutputName(from: title)

        let outputTemplate = StoragePaths.temp
            .appendingPathComponent("\(sanitizedTitle).%(ext)s").path

        let output = try await SubprocessRunner.runStreaming(
            executable: StoragePaths.ytdlpBinary,
            arguments: [
                "-x",
                "--audio-format", "wav",
                "--no-playlist",
                "--newline",
                "-o", outputTemplate,
                "--ffmpeg-location", StoragePaths.bin.path,
                url
            ],
            onOutputLine: { line in
                if let parsed = parseYTDLPProgress(line: line) {
                    onProgress?(parsed.percent / 100.0, parsed.speed)
                }
            }
        )

        guard output.exitCode == 0 else {
            let message = output.stderr.isEmpty ? output.stdout : output.stderr
            AppLogger.error("YTDLP", "yt-dlp failed with code \(output.exitCode): \(message)")
            throw SubprocessError.executionFailed(message, output.exitCode)
        }

        if let audioFile = latestDownloadedAudio(preferredBaseName: sanitizedTitle) {
            AppLogger.info("YTDLP", "Downloaded YouTube audio to \(audioFile.path)")
            return (audioFile, title)
        }

        throw YTDLPError.downloadFailed("No audio file found after download")
    }

    private static func parseYTDLPProgress(line: String) -> (percent: Double, speed: String?)? {
        // Matches lines like: [download]  10.5% of ~  50.55MiB at    5.43MiB/s ETA 00:09
        guard line.contains("[download]") else { return nil }
        guard let percentMatch = line.range(of: #"([\d.]+)%"#, options: .regularExpression) else { return nil }

        let percentStr = line[percentMatch].dropLast() // remove the %
        guard let percent = Double(percentStr) else { return nil }

        var speed: String?
        if let speedMatch = line.range(of: #"at\s+([\d.]+\s*\S+/s)"#, options: .regularExpression) {
            let matched = line[speedMatch]
            // Extract just the speed part after "at"
            if let atRange = matched.range(of: "at") {
                speed = String(matched[atRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        return (percent, speed)
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
        case .show: "Podcast Show"
        }
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        // youtu.be/VIDEO_ID
        if url.host?.contains("youtu.be") == true {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return looksLikeVideoID(id) ? id : nil
        }
        // youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           looksLikeVideoID(videoID) {
            return videoID
        }
        // youtube.com/shorts/VIDEO_ID or /embed/VIDEO_ID
        let segments = url.pathComponents
        if let idx = segments.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
           idx + 1 < segments.count,
           looksLikeVideoID(segments[idx + 1]) {
            return segments[idx + 1]
        }
        return nil
    }

    private static func youtubeThumbnailURL(from url: URL) -> String? {
        guard let videoID = youtubeVideoID(from: url) else { return nil }
        return "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
    }

    private static func youtubeEntryURL(from entry: YTDLPMetadata.Entry) -> String? {
        if let webpageURL = entry.webpageURL, webpageURL.hasPrefix("http") {
            return webpageURL
        }
        if let url = entry.url, url.hasPrefix("http") {
            return url
        }
        // Check entry.id first, then entry.url — only use values that look like video IDs
        if let id = entry.id, looksLikeVideoID(id) {
            return "https://www.youtube.com/watch?v=\(id)"
        }
        if let url = entry.url, looksLikeVideoID(url) {
            return "https://www.youtube.com/watch?v=\(url)"
        }
        AppLogger.info("YTDLP", "Skipped entry with no usable URL — id: \(entry.id ?? "nil"), url: \(entry.url ?? "nil"), title: \(entry.title ?? "nil")")
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

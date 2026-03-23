import Foundation
import SwiftUI

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var speakerDetection: Bool {
        didSet { defaults.set(speakerDetection, forKey: "speakerDetection") }
    }

    var showTimestamps: Bool {
        didSet { defaults.set(showTimestamps, forKey: "showTimestamps") }
    }

    var hasCompletedFirstLaunch: Bool {
        didSet { defaults.set(hasCompletedFirstLaunch, forKey: "hasCompletedFirstLaunch") }
    }

    var autoExportEnabled: Bool {
        didSet { defaults.set(autoExportEnabled, forKey: "autoExportEnabled") }
    }

    var autoExportBookmark: Data? {
        didSet { defaults.set(autoExportBookmark, forKey: "autoExportBookmark") }
    }

    var aiAutoExportEnabled: Bool {
        didSet { defaults.set(aiAutoExportEnabled, forKey: "aiAutoExportEnabled") }
    }

    var aiAutoExportPromptID: String? {
        didSet { defaults.set(aiAutoExportPromptID, forKey: "aiAutoExportPromptID") }
    }

    var codexCustomBinaryPath: String? {
        didSet { defaults.set(codexCustomBinaryPath, forKey: "codexCustomBinaryPath") }
    }

    var codexModel: String? {
        didSet { defaults.set(codexModel, forKey: "codexModel") }
    }

    var codexTimeoutSeconds: Int {
        didSet { defaults.set(codexTimeoutSeconds, forKey: "codexTimeoutSeconds") }
    }

    var spotifyClientID: String? {
        didSet { defaults.set(spotifyClientID, forKey: "spotifyClientID") }
    }

    var spotifyRSSFeedCache: [String: String] {
        didSet { defaults.set(spotifyRSSFeedCache, forKey: "spotifyRSSFeedCache") }
    }

    var spotifyAutoDownloadEnabled: Bool {
        didSet { defaults.set(spotifyAutoDownloadEnabled, forKey: "spotifyAutoDownloadEnabled") }
    }

    var spotifyAutoDownloadIntervalMinutes: Int {
        didSet { defaults.set(spotifyAutoDownloadIntervalMinutes, forKey: "spotifyAutoDownloadIntervalMinutes") }
    }

    var spotifyProcessedEpisodeIDs: Set<String> {
        didSet { defaults.set(Array(spotifyProcessedEpisodeIDs), forKey: "spotifyProcessedEpisodeIDs") }
    }

    var autoExportURL: URL? {
        guard let bookmark = autoExportBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            autoExportBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return url
    }

    var youtubeDateRange: YouTubeDateRange {
        didSet { defaults.set(youtubeDateRange.rawValue, forKey: "youtubeDateRange") }
    }

    var youtubeAutoGroupByChannel: Bool {
        didSet { defaults.set(youtubeAutoGroupByChannel, forKey: "youtubeAutoGroupByChannel") }
    }

    var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum YouTubeDateRange: String, CaseIterable {
        case allTime = "all"
        case lastYear = "year"
        case lastMonth = "month"
        case lastWeek = "week"
        case lastDay = "day"

        var displayName: String {
            switch self {
            case .allTime: "All Time"
            case .lastYear: "Last Year"
            case .lastMonth: "Last Month"
            case .lastWeek: "Last Week"
            case .lastDay: "Last Day"
            }
        }

        var ytdlpDateString: String {
            switch self {
            case .allTime: ""
            case .lastYear: "today-1year"
            case .lastMonth: "today-1month"
            case .lastWeek: "today-7days"
            case .lastDay: "today-1day"
            }
        }
    }

    func markEpisodeProcessed(_ episodeID: String) {
        spotifyProcessedEpisodeIDs.insert(episodeID)
    }

    init() {
        self.speakerDetection = defaults.bool(forKey: "speakerDetection")
        self.showTimestamps = defaults.bool(forKey: "showTimestamps")
        self.hasCompletedFirstLaunch = defaults.bool(forKey: "hasCompletedFirstLaunch")
        self.autoExportEnabled = defaults.bool(forKey: "autoExportEnabled")
        self.autoExportBookmark = defaults.data(forKey: "autoExportBookmark")
        self.aiAutoExportEnabled = defaults.bool(forKey: "aiAutoExportEnabled")
        self.aiAutoExportPromptID = defaults.string(forKey: "aiAutoExportPromptID")
        self.codexCustomBinaryPath = defaults.string(forKey: "codexCustomBinaryPath")
        self.codexModel = defaults.string(forKey: "codexModel")
        let rawTimeout = defaults.integer(forKey: "codexTimeoutSeconds")
        self.codexTimeoutSeconds = rawTimeout > 0 ? rawTimeout : 300
        self.spotifyClientID = defaults.string(forKey: "spotifyClientID")
        self.spotifyRSSFeedCache = (defaults.dictionary(forKey: "spotifyRSSFeedCache") as? [String: String]) ?? [:]
        self.spotifyAutoDownloadEnabled = defaults.bool(forKey: "spotifyAutoDownloadEnabled")
        let rawInterval = defaults.integer(forKey: "spotifyAutoDownloadIntervalMinutes")
        self.spotifyAutoDownloadIntervalMinutes = rawInterval > 0 ? rawInterval : 30
        self.spotifyProcessedEpisodeIDs = Set(defaults.stringArray(forKey: "spotifyProcessedEpisodeIDs") ?? [])
        self.youtubeDateRange = YouTubeDateRange(
            rawValue: defaults.string(forKey: "youtubeDateRange") ?? ""
        ) ?? .allTime
        self.youtubeAutoGroupByChannel = defaults.bool(forKey: "youtubeAutoGroupByChannel")
        self.appearanceMode = AppearanceMode(
            rawValue: defaults.string(forKey: "appearanceMode") ?? ""
        ) ?? .dark
    }
}

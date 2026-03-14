import Foundation

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

    init() {
        self.speakerDetection = defaults.bool(forKey: "speakerDetection")
        self.showTimestamps = defaults.bool(forKey: "showTimestamps")
        self.hasCompletedFirstLaunch = defaults.bool(forKey: "hasCompletedFirstLaunch")
        self.autoExportEnabled = defaults.bool(forKey: "autoExportEnabled")
        self.autoExportBookmark = defaults.data(forKey: "autoExportBookmark")
        self.aiAutoExportEnabled = defaults.bool(forKey: "aiAutoExportEnabled")
        self.aiAutoExportPromptID = defaults.string(forKey: "aiAutoExportPromptID")
        self.codexCustomBinaryPath = defaults.string(forKey: "codexCustomBinaryPath")
        self.youtubeDateRange = YouTubeDateRange(
            rawValue: defaults.string(forKey: "youtubeDateRange") ?? ""
        ) ?? .allTime
    }
}

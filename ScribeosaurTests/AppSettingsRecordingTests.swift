import XCTest
@testable import Scribeosaur

final class AppSettingsRecordingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsRecordingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordingPreferencesPersistAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.recordingInputDeviceID = "mic-1"
        settings.recordingLiveMode = .chunkedMultilingual
        settings.recordingRunFinalPass = false
        settings.recordingRunAIPrompt = true
        settings.recordingAIPromptID = "summary"
        settings.recordingAudioQuality = .speechOptimized
        settings.recordingKeepOriginalAudio = true

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.recordingInputDeviceID, "mic-1")
        XCTAssertEqual(reloaded.recordingLiveMode, .chunkedMultilingual)
        XCTAssertFalse(reloaded.recordingRunFinalPass)
        XCTAssertTrue(reloaded.recordingRunAIPrompt)
        XCTAssertEqual(reloaded.recordingAIPromptID, "summary")
        XCTAssertEqual(reloaded.recordingAudioQuality, .speechOptimized)
        XCTAssertTrue(reloaded.recordingKeepOriginalAudio)
    }

    func testRecordingPreferencesStartFromCleanSuite() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertNil(settings.recordingInputDeviceID)
        XCTAssertEqual(settings.recordingLiveMode, .automatic)
        XCTAssertTrue(settings.recordingRunFinalPass)
        XCTAssertFalse(settings.recordingRunAIPrompt)
        XCTAssertEqual(settings.recordingAudioQuality, .high)
        XCTAssertFalse(settings.recordingKeepOriginalAudio)
    }
}

@MainActor
final class AppStateSettingsRoutingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppStateSettingsRoutingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testOpenSettingsWithoutContextUsesLastSelectedSectionAndShowsSettingsDestination() {
        let appState = makeAppState()
        appState.lastSelectedSettingsSection = .storage

        appState.openSettings()

        XCTAssertEqual(appState.requestedSettingsSection, .storage)
        XCTAssertEqual(appState.currentDestination, .settings)
    }

    func testContextualSettingsOpenOverridesAndClearsAfterConsumption() {
        let appState = makeAppState()

        appState.openSettings(section: .ai)

        XCTAssertEqual(appState.currentDestination, .settings)
        XCTAssertEqual(appState.consumeRequestedSettingsSection(), .ai)
        XCTAssertNil(appState.requestedSettingsSection)
    }

    func testLastSelectedSectionPersistsAcrossAppStateInstances() {
        let first = makeAppState()
        first.lastSelectedSettingsSection = .spotify

        let second = makeAppState()

        XCTAssertEqual(second.lastSelectedSettingsSection, .spotify)
    }

    func testCloseSettingsReturnsToLibraryWithoutChangingLastSelectedSection() {
        let appState = makeAppState()
        appState.lastSelectedSettingsSection = .recording

        appState.openSettings()
        appState.closeSettings()

        XCTAssertEqual(appState.currentDestination, .library)
        XCTAssertEqual(appState.lastSelectedSettingsSection, .recording)
    }

    func testSettingsSectionsRemainInConsumerFacingOrder() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.general, .youtube, .recording, .storage, .ai, .spotify]
        )
    }

    private func makeAppState() -> AppState {
        let settings = AppSettings(defaults: defaults)
        let aiService = GemmaService(defaults: defaults)

        return AppState(
            settings: settings,
            provisioningService: ProvisioningService(),
            aiService: aiService,
            spotifyAuthService: SpotifyAuthService()
        )
    }
}

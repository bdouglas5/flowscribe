import XCTest
@testable import Scribeosaur

final class RecordingSessionStateTests: XCTestCase {
    func testResetPresentationStateClearsTransientFieldsAndPreservesConfiguration() {
        var previous = RecordingSessionState()
        previous.phase = .recording
        previous.captureSource = .microphone
        previous.elapsedSeconds = 91
        previous.audioLevel = 0.8
        previous.selectedInputDeviceID = "mic-1"
        previous.availableInputDevices = [
            RecordingInputDevice(id: "mic-1", name: "Desk Mic")
        ]
        previous.statusMessage = "Recording"
        previous.warmupState = .ready
        previous.warmupMessage = "Recorder ready"
        previous.finalizationProgress = 0.7
        previous.finalizationStep = "Saving"
        previous.errorMessage = "Old error"

        var next = RecordingSessionState()
        next.resetPresentationState(preservingConfigurationFrom: previous)

        XCTAssertEqual(next.phase, .idle)
        XCTAssertEqual(next.captureSource, .microphone)
        XCTAssertEqual(next.elapsedSeconds, 0)
        XCTAssertEqual(next.audioLevel, 0)
        XCTAssertEqual(next.selectedInputDeviceID, "mic-1")
        XCTAssertEqual(next.availableInputDevices, previous.availableInputDevices)
        XCTAssertNil(next.statusMessage)
        XCTAssertEqual(next.warmupState, .ready)
        XCTAssertEqual(next.warmupMessage, "Recorder ready")
        XCTAssertEqual(next.finalizationProgress, 0)
        XCTAssertNil(next.finalizationStep)
        XCTAssertNil(next.errorMessage)
    }

    func testArmedStateShowsPopoverAndBlocksStartWhileWarmupIsRunning() {
        var state = RecordingSessionState()
        state.phase = .armed
        state.warmupState = .warming

        XCTAssertTrue(state.showsRecorderPopover)
        XCTAssertFalse(state.canStartRecording)

        state.warmupState = .ready

        XCTAssertTrue(state.canStartRecording)
    }

    func testPreflightingStateDoesNotShowArmedDropdown() {
        var state = RecordingSessionState()
        state.phase = .preflighting

        XCTAssertFalse(state.showsRecorderPopover)
    }
}

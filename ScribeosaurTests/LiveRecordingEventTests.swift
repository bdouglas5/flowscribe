import XCTest
@testable import Scribeosaur

final class LiveRecordingEventTests: XCTestCase {
    func testSessionScopedEventOnlyAppliesToMatchingSession() {
        let activeSessionID = UUID()
        let staleEvent = LiveRecordingEvent(
            sessionID: UUID(),
            payload: .elapsedChanged(12)
        )
        let activeEvent = LiveRecordingEvent(
            sessionID: activeSessionID,
            payload: .elapsedChanged(18)
        )
        let globalEvent = LiveRecordingEvent(
            sessionID: nil,
            payload: .warmupStatusChanged(.ready, message: "Recorder ready")
        )

        XCTAssertFalse(staleEvent.applies(to: activeSessionID))
        XCTAssertTrue(activeEvent.applies(to: activeSessionID))
        XCTAssertTrue(globalEvent.applies(to: activeSessionID))
    }

    func testSessionScopedEventIsIgnoredWhenNoSessionIsActive() {
        let oldSessionEvent = LiveRecordingEvent(
            sessionID: UUID(),
            payload: .statusChanged("Recording")
        )
        let globalEvent = LiveRecordingEvent(
            sessionID: nil,
            payload: .devicesUpdated([], selectedID: nil)
        )

        XCTAssertFalse(oldSessionEvent.applies(to: nil))
        XCTAssertTrue(globalEvent.applies(to: nil))
    }
}

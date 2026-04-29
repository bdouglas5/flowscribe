import XCTest
@testable import Scribeosaur

final class RecordingChunkPlannerTests: XCTestCase {
    func testFlushesAfterSilenceWindow() {
        var planner = RecordingChunkPlanner(maxChunkDuration: 12, maxSilenceDuration: 0.8)

        planner.registerVoiceActivity(at: 1.2)

        XCTAssertFalse(
            planner.shouldFlushChunk(
                at: 2.0,
                speechActive: false,
                currentChunkDuration: 2.0,
                currentSilenceDuration: 0.4
            )
        )

        XCTAssertTrue(
            planner.shouldFlushChunk(
                at: 2.5,
                speechActive: false,
                currentChunkDuration: 2.5,
                currentSilenceDuration: 0.9
            )
        )
    }

    func testFlushesAtMaxChunkDuration() {
        var planner = RecordingChunkPlanner(maxChunkDuration: 6, maxSilenceDuration: 0.8)
        planner.registerVoiceActivity(at: 0.5)

        XCTAssertTrue(
            planner.shouldFlushChunk(
                at: 6.1,
                speechActive: true,
                currentChunkDuration: 6.05,
                currentSilenceDuration: 0
            )
        )
    }
}

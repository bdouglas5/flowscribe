import XCTest
@testable import Scribeosaur

final class RecordingLiveModeTests: XCTestCase {
    func testAutomaticModeResolvesToStreamingEnglish() {
        XCTAssertEqual(
            AppSettings.RecordingLiveMode.automatic.resolvedRecorderMode,
            .streamingEnglish
        )
        XCTAssertTrue(AppSettings.RecordingLiveMode.automatic.requiresStreamingWarmup)
    }

    func testChunkedMultilingualModeSkipsStreamingWarmup() {
        XCTAssertEqual(
            AppSettings.RecordingLiveMode.chunkedMultilingual.resolvedRecorderMode,
            .chunkedMultilingual
        )
        XCTAssertFalse(AppSettings.RecordingLiveMode.chunkedMultilingual.requiresStreamingWarmup)
    }
}

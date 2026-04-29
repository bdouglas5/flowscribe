import XCTest
@testable import Scribeosaur

final class TranscriptCategoryTests: XCTestCase {
    func testRecordingSourceMapsToLocalAudio() {
        let transcript = Transcript(
            title: "Mic",
            sourceType: .recording,
            sourcePath: "",
            remoteSource: nil,
            createdAt: .now,
            speakerDetection: false,
            speakerCount: 0,
            fullText: "",
            status: .completed
        )

        XCTAssertEqual(TranscriptCategory.category(for: transcript), .localAudio)
    }
}

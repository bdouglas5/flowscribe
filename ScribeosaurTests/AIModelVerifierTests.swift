import CryptoKit
import Foundation
import XCTest
@testable import Scribeosaur

final class AIModelVerifierTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testVerifyFilesThrowsChecksumMismatchWithAssetPath() throws {
        let modelDirectory = tempDirectory.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let expectedData = Data("good-data".utf8)
        let actualData = Data("bad-data!".utf8)
        let assetURL = modelDirectory.appendingPathComponent("README.md")
        try actualData.write(to: assetURL)

        let descriptor = AIModelDescriptor(
            id: "test-model",
            displayName: "Test",
            providerID: "provider/test",
            revision: "revision",
            estimatedDownloadSizeBytes: Int64(expectedData.count),
            estimatedMemoryBytes: 0,
            notes: "Test manifest",
            assetFiles: [
                AIModelAsset(
                    path: "README.md",
                    sizeBytes: Int64(actualData.count),
                    checksum: sha256(expectedData)
                )
            ]
        )

        let verifier = AIModelVerifier()

        XCTAssertThrowsError(try verifier.verifyFiles(for: descriptor, in: modelDirectory)) { error in
            guard case LocalAIProvisioningError.checksumMismatch(let assetPath, _, let actualDigest) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(assetPath, "README.md")
            XCTAssertEqual(actualDigest, sha256(actualData))
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

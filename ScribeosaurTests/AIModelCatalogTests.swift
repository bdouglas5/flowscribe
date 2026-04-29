import Foundation
import XCTest
@testable import Scribeosaur

final class AIModelCatalogTests: XCTestCase {
    func testMainBundleContainsPinnedGemmaDescriptor() throws {
        let descriptors = try AIModelCatalog.loadDescriptors(from: .main)
        XCTAssertEqual(descriptors.count, 1)
        let descriptor = try XCTUnwrap(descriptors.first)

        XCTAssertEqual(descriptor.id, "gemma-e4b-4bit-local")
        XCTAssertEqual(descriptor.displayName, "Gemma 4 E4B (4-bit)")
        XCTAssertEqual(descriptor.providerID, "unsloth/gemma-4-E4B-it-UD-MLX-4bit")
        XCTAssertEqual(descriptor.revision, "52a9e17e759f23e63acf486834de990060319265")
        XCTAssertEqual(descriptor.estimatedDownloadSizeBytes, 5_625_005_881)
        XCTAssertEqual(descriptor.assetFiles.count, 9)
        XCTAssertEqual(
            descriptor.assetFiles,
            [
                AIModelAsset(
                    path: "README.md",
                    sizeBytes: 28_163,
                    checksum: "7b6f7686d7b95fa73f5a97e37a6237bdec0905588ee683988587dcd422e4cf8c"
                ),
                AIModelAsset(
                    path: "chat_template.jinja",
                    sizeBytes: 11_926,
                    checksum: "55572b8d3c8342044e25874c73fe5234b661fa0a57a57f6ef75b58e03d7d959a"
                ),
                AIModelAsset(
                    path: "config.json",
                    sizeBytes: 98_897,
                    checksum: "2abf8c3b258e65b1463d2e03ae95c80b18613192c38f9e90e7f55dd9366c739d"
                ),
                AIModelAsset(
                    path: "generation_config.json",
                    sizeBytes: 208,
                    checksum: "d4226bbe3117d2d253ba4609720ba82c6c4ce4627a9a6ae05387c78983ac03de"
                ),
                AIModelAsset(
                    path: "model-00001-of-00002.safetensors",
                    sizeBytes: 3_273_206_124,
                    checksum: "4345216134935379bb06bbf53a44694f02f4940cc0e963f38b21e9a747a48bb7"
                ),
                AIModelAsset(
                    path: "model-00002-of-00002.safetensors",
                    sizeBytes: 2_319_336_848,
                    checksum: "79c5d284ec61ad0da1ba7ad8060f7c7c95a963581d006fefc97775de9f7831fb"
                ),
                AIModelAsset(
                    path: "model.safetensors.index.json",
                    sizeBytes: 151_391,
                    checksum: "916f30b850d8dc4c85edaf5076125702d528b1d85f0a548c8e8c21e908233729"
                ),
                AIModelAsset(
                    path: "tokenizer.json",
                    sizeBytes: 32_169_626,
                    checksum: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"
                ),
                AIModelAsset(
                    path: "tokenizer_config.json",
                    sizeBytes: 2_698,
                    checksum: "fe8db0f0aa9a6b5c5d46e9b52b91b7cecb00f879f8ee336c6352b612833c6e73"
                ),
            ]
        )
    }
}

final class ProvisioningServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        StoragePaths.setAppSupportOverride(tempRoot.appendingPathComponent("ApplicationSupport"))
        StoragePaths.setBundledResourceRootOverride(nil)
        ThumbnailCache.resetSharedForTesting()
    }

    override func tearDownWithError() throws {
        AppLogger.flush()
        ThumbnailCache.resetSharedForTesting()
        StoragePaths.setAppSupportOverride(nil)
        StoragePaths.setBundledResourceRootOverride(nil)

        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testProvisionIfNeededInstallsAndValidatesBundledHelpersIncludingUV() async throws {
        let bundleRoot = tempRoot.appendingPathComponent("BundleRoot")
        let binariesRoot = bundleRoot.appendingPathComponent("Binaries")
        try FileManager.default.createDirectory(at: binariesRoot, withIntermediateDirectories: true)

        try writeExecutable(named: "ffmpeg", body: "echo 'ffmpeg version test'")
        try writeExecutable(named: "yt-dlp", body: "echo 'yt-dlp test version'")
        try writeExecutable(named: "deno", body: "echo 'deno 2.5.0'")
        try writeExecutable(named: "uv", body: "echo 'uv 0.11.6'")

        StoragePaths.setBundledResourceRootOverride(bundleRoot)

        let service = ProvisioningService()
        await service.provisionIfNeeded()
        XCTAssertNil(service.error)

        await service.provisionIfNeeded()
        XCTAssertNil(service.error)
        XCTAssertTrue(service.binariesReady)
        XCTAssertTrue(StoragePaths.ffmpegExists)
        XCTAssertTrue(StoragePaths.ytdlpExists)
        XCTAssertTrue(StoragePaths.denoExists)
        XCTAssertTrue(StoragePaths.uvExists)
    }

    func testReleaseInstallerScriptStagesRuntimeHelpersAndOptionalSeed() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("scripts/build-release-installer.sh")
        let script = try String(contentsOf: scriptURL)

        XCTAssertTrue(script.contains("DENO_URL="))
        XCTAssertTrue(script.contains("UV_URL="))
        XCTAssertTrue(script.contains("prepare_deno"))
        XCTAssertTrue(script.contains("prepare_uv"))
        XCTAssertTrue(script.contains("AI_RUNTIME_SEED_PATH="))
        XCTAssertTrue(script.contains("verify_model_manifest"))
        XCTAssertTrue(script.contains("generate_model_manifest.swift\" --check"))
        XCTAssertTrue(script.contains("ditto \"$TOOLS_PATH/deno\" \"$binaries_path/deno\""))
        XCTAssertTrue(script.contains("ditto \"$TOOLS_PATH/uv\" \"$binaries_path/uv\""))
        XCTAssertTrue(script.contains("Contents/Resources/AIRuntimeSeed"))
        XCTAssertTrue(script.contains("\"$EXPORTED_APP_PATH/Contents/Resources/Binaries/deno\""))
        XCTAssertTrue(script.contains("\"$EXPORTED_APP_PATH/Contents/Resources/Binaries/uv\""))
    }

    private func writeExecutable(named name: String, body: String) throws {
        let url = tempRoot
            .appendingPathComponent("BundleRoot")
            .appendingPathComponent("Binaries")
            .appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

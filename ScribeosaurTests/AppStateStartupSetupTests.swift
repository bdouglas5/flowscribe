import CryptoKit
import Foundation
import XCTest
@testable import Scribeosaur

@MainActor
final class AppStateStartupSetupTests: XCTestCase {
    private var tempRoot: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        StoragePaths.setAppSupportOverride(tempRoot.appendingPathComponent("ApplicationSupport"))
        StoragePaths.setBundledResourceRootOverride(nil)
        ThumbnailCache.resetSharedForTesting()

        defaultsSuiteName = "AppStateStartupSetupTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        AppLogger.flush()
        ThumbnailCache.resetSharedForTesting()
        StoragePaths.setAppSupportOverride(nil)
        StoragePaths.setBundledResourceRootOverride(nil)

        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil

        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testRunStartupSetupCompletesFirstLaunchAfterRuntimeBootstrapProvisioningAndLoad() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("verified-model".utf8))
        let descriptor = makeDescriptor(modelID: "startup-success-model", assets: [asset])
        let downloader = StartupFakeDownloader(assetDataByPath: [asset.path: asset.expectedData])
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertTrue(appState.settings.hasCompletedFirstLaunch)
        XCTAssertEqual(runtimeClient.ensureRuntimeReadyCalls, 1)
        XCTAssertEqual(runtimeClient.loadModelCalls.count, 1)
        XCTAssertEqual(runtimeClient.loadModelCalls.first?.0, descriptor.id)
        XCTAssertEqual(runtimeClient.loadModelCalls.first?.1, StoragePaths.modelDirectory(for: descriptor.id).path)
        XCTAssertEqual(runtimeClient.healthCheckCalls, 1)
        XCTAssertEqual(downloader.downloadedAssetPaths, [asset.path])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StoragePaths.modelVerificationFile(for: descriptor.id).path
            )
        )
    }

    func testRunStartupSetupUsesBundledSeedWithoutDownloaderCalls() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("seeded-model".utf8))
        let descriptor = makeDescriptor(modelID: "startup-seed-model", assets: [asset])
        let seedDirectory = tempRoot
            .appendingPathComponent("BundleRoot")
            .appendingPathComponent("ModelSeed")
            .appendingPathComponent(descriptor.id)
        try FileManager.default.createDirectory(at: seedDirectory, withIntermediateDirectories: true)
        try asset.expectedData.write(to: seedDirectory.appendingPathComponent(asset.path))

        let downloader = StartupFakeDownloader(assetDataByPath: [:])
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient,
            bundledSeedDirectoryProvider: { _ in seedDirectory }
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertTrue(appState.settings.hasCompletedFirstLaunch)
        XCTAssertTrue(downloader.downloadedAssetPaths.isEmpty)
        XCTAssertEqual(runtimeClient.ensureRuntimeReadyCalls, 1)
        XCTAssertEqual(runtimeClient.loadModelCalls.count, 1)
        let installedData = try Data(
            contentsOf: StoragePaths.modelDirectory(for: descriptor.id).appendingPathComponent(asset.path)
        )
        XCTAssertEqual(installedData, asset.expectedData)
    }

    func testRunStartupSetupLeavesAppBlockedWhenModelProvisioningFails() async throws {
        let descriptor = makeDescriptor(
            modelID: "startup-failure-model",
            assets: [StartupAssetFixture(path: "README.md", expectedData: Data("good-data".utf8))]
        )
        let downloader = StartupFakeDownloader(assetDataByPath: [
            "README.md": Data("bad-data!".utf8)
        ])
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        XCTAssertFalse(appState.isReady)
        XCTAssertEqual(appState.setupError, "Checksum verification failed for README.md.")
        XCTAssertFalse(appState.settings.hasCompletedFirstLaunch)
        XCTAssertEqual(runtimeClient.ensureRuntimeReadyCalls, 1)
        XCTAssertTrue(runtimeClient.loadModelCalls.isEmpty)
    }

    func testRunStartupSetupLeavesAppBlockedWhenHelperLoadFails() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("verified-model".utf8))
        let descriptor = makeDescriptor(modelID: "startup-helper-failure-model", assets: [asset])
        let downloader = StartupFakeDownloader(assetDataByPath: [asset.path: asset.expectedData])
        let runtimeClient = FakeLocalAIRuntimeClient()
        runtimeClient.loadModelError = LocalAIRuntimeError.modelLoadFailed("No model factory available via ModelFactoryRegistry")
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        XCTAssertFalse(appState.isReady)
        XCTAssertEqual(
            appState.setupError,
            "Failed to load the local AI model: No model factory available via ModelFactoryRegistry"
        )
        XCTAssertFalse(appState.settings.hasCompletedFirstLaunch)
        XCTAssertEqual(runtimeClient.ensureRuntimeReadyCalls, 1)
        XCTAssertEqual(runtimeClient.loadModelCalls.count, 1)
        XCTAssertEqual(runtimeClient.healthCheckCalls, 0)
    }

    func testRunStartupSetupRepairsMissingRuntimeWhenFirstLaunchFlagAlreadySet() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("reinstalled-model".utf8))
        let descriptor = makeDescriptor(modelID: "startup-reinstall-model", assets: [asset])
        let downloader = StartupFakeDownloader(assetDataByPath: [asset.path: asset.expectedData])
        let runtimeClient = FakeLocalAIRuntimeClient()
        runtimeClient.runtimeLooksInstalledValue = false
        runtimeClient.runtimeNeedsPreparationValue = true
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = true
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertTrue(appState.settings.hasCompletedFirstLaunch)
        XCTAssertEqual(runtimeClient.ensureRuntimeReadyCalls, 1)
        XCTAssertEqual(runtimeClient.loadModelCalls.count, 1)
        XCTAssertEqual(downloader.downloadedAssetPaths, [asset.path])
    }

    func testStartApplicationProducesMonotonicProgressOnFirstLaunch() async throws {
        let assetData = Data(repeating: 0x61, count: 256)
        let asset = StartupAssetFixture(path: "weights.bin", expectedData: assetData)
        let descriptor = makeDescriptor(
            modelID: "startup-presentation-model",
            assets: [asset],
            estimatedDownloadSizeBytes: 5_625_005_881
        )
        let downloader = StartupFakeDownloader(
            assetDataByPath: [asset.path: asset.expectedData],
            progressChunkCount: 6,
            chunkDelay: .milliseconds(140)
        )
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        let startupTask = Task {
            await appState.startApplication(
                initializeCore: {
                    try await Task.sleep(for: .milliseconds(260))
                },
                provisionDependencies: {
                    await MainActor.run {
                        appState.provisioningService.isProvisioning = true
                        appState.provisioningService.startupStage = .checking
                        appState.provisioningService.progress = 0.2
                        appState.provisioningService.startupStageProgress = 0.2
                    }
                    try await Task.sleep(for: .milliseconds(260))
                    await MainActor.run {
                        appState.provisioningService.isProvisioning = false
                        appState.provisioningService.startupStage = .ready
                        appState.provisioningService.progress = 1.0
                        appState.provisioningService.startupStageProgress = 1.0
                    }
                },
                loadCoreModels: {
                    await MainActor.run {
                        appState.transcriptionService.modelLoadProgress = 0.35
                    }
                    try await Task.sleep(for: .milliseconds(220))
                    await MainActor.run {
                        appState.transcriptionService.modelLoadProgress = 1.0
                        appState.transcriptionService.isModelLoaded = true
                    }
                }
            )
        }

        var sampledProgress: [Double] = []
        var sampledCopy: [String] = []
        var sampledStageLabels: [String] = []
        var sampledVisibleStageLabels: [String] = []

        while await MainActor.run(body: { !appState.isReady && appState.setupError == nil }) {
            let snapshot = await MainActor.run { appState.startupPresentation }
            sampledProgress.append(snapshot.displayProgress)
            sampledCopy.append(snapshot.headline)
            sampledCopy.append(snapshot.detail)
            sampledStageLabels.append(snapshot.stageLabel)
            sampledVisibleStageLabels.append(contentsOf: snapshot.visibleStages.map(\.label))
            try await Task.sleep(for: .milliseconds(90))
        }

        await startupTask.value

        let finalSnapshot = await MainActor.run { appState.startupPresentation }
        sampledProgress.append(finalSnapshot.displayProgress)

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertEqual(finalSnapshot.launchMode, .firstInstall)
        XCTAssertTrue(
            zip(sampledProgress, sampledProgress.dropFirst()).allSatisfy { lhs, rhs in
                rhs + 0.0001 >= lhs
            }
        )
        XCTAssertEqual(finalSnapshot.displayProgress, 1.0, accuracy: 0.0001)
        XCTAssertTrue(sampledVisibleStageLabels.contains("Downloading local AI model (6 GB)…"))
        XCTAssertEqual(finalSnapshot.visibleStages.count, 8)

        for copyValue in sampledCopy + sampledStageLabels + sampledVisibleStageLabels {
            XCTAssertNil(
                StartupPresentationState.containsDisallowedTerm(in: copyValue),
                "Unexpected internal setup term in copy: \(copyValue)"
            )
        }
    }

    func testReturningQuickCheckStaysCompactAndVisibleForAtLeastTwoSecondsWhenStartupIsFast() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("verified-model".utf8))
        let descriptor = makeDescriptor(modelID: "returning-fast-model", assets: [asset])
        let downloader = StartupFakeDownloader(assetDataByPath: [asset.path: asset.expectedData])
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        await appState.runStartupSetup(
            provisionDependencies: {},
            loadCoreModels: {}
        )

        let startedAt = Date()
        let startupTask = Task {
            await appState.startApplication(
                initializeCore: {},
                provisionDependencies: {},
                loadCoreModels: {}
            )
        }

        var sampledLaunchModes: [StartupLaunchMode] = []
        var sampledProgress: [Double] = []

        while await MainActor.run(body: { !appState.isReady && appState.setupError == nil }) {
            let snapshot = await MainActor.run { appState.startupPresentation }
            sampledLaunchModes.append(snapshot.launchMode)
            sampledProgress.append(snapshot.displayProgress)
            try await Task.sleep(for: .milliseconds(90))
        }

        await startupTask.value
        let elapsed = Date().timeIntervalSince(startedAt)
        let finalSnapshot = await MainActor.run { appState.startupPresentation }

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertGreaterThanOrEqual(elapsed, 2.0)
        XCTAssertTrue(sampledLaunchModes.allSatisfy { $0 == .returningQuickCheck })
        XCTAssertEqual(finalSnapshot.launchMode, .returningQuickCheck)
        XCTAssertTrue(
            zip(sampledProgress, sampledProgress.dropFirst()).allSatisfy { lhs, rhs in
                rhs + 0.0001 >= lhs
            }
        )
        XCTAssertFalse(finalSnapshot.visibleStages.contains(where: { $0.label.contains("Downloading local AI model") }))
    }

    func testReturningQuickCheckCanRunLongWithoutEscalatingToFirstInstallScreen() async throws {
        let assetData = Data(repeating: 0x61, count: 256)
        let asset = StartupAssetFixture(path: "weights.bin", expectedData: assetData)
        let descriptor = makeDescriptor(
            modelID: "returning-repair-model",
            assets: [asset],
            estimatedDownloadSizeBytes: 5_625_005_881
        )
        let downloader = StartupFakeDownloader(
            assetDataByPath: [asset.path: asset.expectedData],
            progressChunkCount: 7,
            chunkDelay: .milliseconds(220)
        )
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient
        )
        appState.settings.hasCompletedFirstLaunch = true
        appState.settings.speakerDetection = false

        let startedAt = Date()
        let startupTask = Task {
            await appState.startApplication(
                initializeCore: {
                    try await Task.sleep(for: .milliseconds(120))
                },
                provisionDependencies: {
                    await MainActor.run {
                        appState.provisioningService.isProvisioning = true
                        appState.provisioningService.startupStage = .checking
                        appState.provisioningService.startupStageProgress = 0.18
                    }
                    try await Task.sleep(for: .milliseconds(180))
                    await MainActor.run {
                        appState.provisioningService.isProvisioning = false
                        appState.provisioningService.startupStage = .ready
                        appState.provisioningService.startupStageProgress = 1.0
                    }
                },
                loadCoreModels: {
                    await MainActor.run {
                        appState.transcriptionService.modelLoadProgress = 0.42
                    }
                    try await Task.sleep(for: .milliseconds(180))
                    await MainActor.run {
                        appState.transcriptionService.modelLoadProgress = 1.0
                        appState.transcriptionService.isModelLoaded = true
                    }
                }
            )
        }

        var sampledLaunchModes: [StartupLaunchMode] = []
        var sampledVisibleStageLabels: [String] = []

        while await MainActor.run(body: { !appState.isReady && appState.setupError == nil }) {
            let snapshot = await MainActor.run { appState.startupPresentation }
            sampledLaunchModes.append(snapshot.launchMode)
            sampledVisibleStageLabels.append(contentsOf: snapshot.visibleStages.map(\.label))
            try await Task.sleep(for: .milliseconds(90))
        }

        await startupTask.value
        let elapsed = Date().timeIntervalSince(startedAt)
        let finalSnapshot = await MainActor.run { appState.startupPresentation }

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertGreaterThanOrEqual(elapsed, 2.0)
        XCTAssertTrue(sampledLaunchModes.allSatisfy { $0 == .returningQuickCheck })
        XCTAssertEqual(finalSnapshot.launchMode, .returningQuickCheck)
        XCTAssertTrue(sampledVisibleStageLabels.contains("Downloading local AI model (6 GB)…"))
    }

    func testSeededFirstInstallSkipsDownloadStageWithoutFlashingIrrelevantMessaging() async throws {
        let asset = StartupAssetFixture(path: "README.md", expectedData: Data("seeded-model".utf8))
        let descriptor = makeDescriptor(
            modelID: "seeded-first-install-model",
            assets: [asset],
            estimatedDownloadSizeBytes: 5_625_005_881
        )
        let seedDirectory = tempRoot
            .appendingPathComponent("BundleRoot")
            .appendingPathComponent("ModelSeed")
            .appendingPathComponent(descriptor.id)
        try FileManager.default.createDirectory(at: seedDirectory, withIntermediateDirectories: true)
        try asset.expectedData.write(to: seedDirectory.appendingPathComponent(asset.path))

        let downloader = StartupFakeDownloader(assetDataByPath: [:])
        let runtimeClient = FakeLocalAIRuntimeClient()
        let appState = makeAppState(
            descriptor: descriptor,
            downloader: downloader,
            runtimeClient: runtimeClient,
            bundledSeedDirectoryProvider: { _ in seedDirectory }
        )
        appState.settings.hasCompletedFirstLaunch = false
        appState.settings.speakerDetection = false

        let startupTask = Task {
            await appState.startApplication(
                initializeCore: {},
                provisionDependencies: {},
                loadCoreModels: {}
            )
        }

        var sampledVisibleStageLabels: [String] = []

        while await MainActor.run(body: { !appState.isReady && appState.setupError == nil }) {
            let snapshot = await MainActor.run { appState.startupPresentation }
            sampledVisibleStageLabels.append(contentsOf: snapshot.visibleStages.map(\.label))
            try await Task.sleep(for: .milliseconds(90))
        }

        await startupTask.value
        let finalSnapshot = await MainActor.run { appState.startupPresentation }

        XCTAssertTrue(appState.isReady)
        XCTAssertNil(appState.setupError)
        XCTAssertEqual(finalSnapshot.launchMode, .firstInstall)
        XCTAssertFalse(sampledVisibleStageLabels.contains("Downloading local AI model (6 GB)…"))
    }

    func testStartupPresentationStateCopyDeckAllowsProductLocalAICopyAndAvoidsInternalSetupTerms() {
        let copyDeck = StartupPresentationState.defaultCopyDeck()
        XCTAssertTrue(copyDeck.contains(where: { $0.contains("local AI model") }))

        for copyValue in copyDeck {
            XCTAssertNil(
                StartupPresentationState.containsDisallowedTerm(in: copyValue),
                "Unexpected internal setup term in copy: \(copyValue)"
            )
        }
    }

    func testStartupPresentationStateNeverMovesBackward() {
        var state = StartupPresentationState()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let stages = StartupPresentationState.stages(
            for: .firstInstall,
            modelSizeLabel: "6 GB",
            includesAIStages: true,
            includesDownloadStage: true
        )

        state.beginSession(
            now: start,
            launchMode: .firstInstall,
            visibleStages: stages
        )
        XCTAssertEqual(state.launchMode, .firstInstall)
        XCTAssertEqual(state.stageLabel, "Initialising Scribeosaur…")

        state.update(
            phase: .preparingWorkspace,
            headline: "Getting ready",
            detail: "Please hold.",
            targetProgress: 0.08,
            visibleStages: stages,
            now: start.addingTimeInterval(0.4)
        )
        let earlyProgress = state.displayProgress

        state.update(
            phase: .unlockingSmartTools,
            headline: "Almost there",
            detail: "Still polishing.",
            targetProgress: 0.78,
            visibleStages: stages,
            now: start.addingTimeInterval(1.25)
        )
        let laterProgress = state.displayProgress

        state.update(
            phase: .unlockingSmartTools,
            headline: "Holding steady",
            detail: "Still polishing.",
            targetProgress: 0.65,
            visibleStages: stages,
            now: start.addingTimeInterval(1.55)
        )

        XCTAssertGreaterThan(laterProgress, earlyProgress)
        XCTAssertGreaterThanOrEqual(state.displayProgress, laterProgress)
        XCTAssertLessThan(state.displayProgress, StartupPhase.unlockingSmartTools.progressRange.upperBound)
        XCTAssertGreaterThan(state.activeStageIndex, 0)
        XCTAssertFalse(state.stageLabel.isEmpty)
    }

    func testStartupMascotAssetResolvesStartupSubdirectoryGIFAndProvidesStaticFrameForReducedMotion() throws {
        let gifData = try XCTUnwrap(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        let startupDirectory = tempRoot.appendingPathComponent("Startup")
        try FileManager.default.createDirectory(at: startupDirectory, withIntermediateDirectories: true)
        let gifURL = startupDirectory.appendingPathComponent("ScribasaurDance.gif")
        try gifData.write(to: gifURL)
        StoragePaths.setBundledResourceRootOverride(tempRoot)

        XCTAssertEqual(StartupMascotAsset.resourceURL(), gifURL)

        switch StartupMascotAsset.loadContent(reduceMotion: true) {
        case .staticFrame:
            break
        case .animated, .unavailable:
            XCTFail("Expected a static mascot frame when reduced motion is enabled.")
        }
    }

    func testStartupMascotAssetResolvesBundleRootGIF() throws {
        let gifData = try XCTUnwrap(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        let gifURL = tempRoot.appendingPathComponent("ScribasaurDance.gif")
        try gifData.write(to: gifURL)
        StoragePaths.setBundledResourceRootOverride(tempRoot)

        XCTAssertEqual(StartupMascotAsset.resourceURL(), gifURL)
    }

    private func makeAppState(
        descriptor: AIModelDescriptor,
        downloader: any ModelAssetDownloading,
        runtimeClient: FakeLocalAIRuntimeClient,
        bundledSeedDirectoryProvider: @escaping (String) -> URL? = { _ in nil }
    ) -> AppState {
        defaults.set(descriptor.id, forKey: "selectedAIModelID")
        let settings = AppSettings(defaults: defaults)
        let aiService = GemmaService(
            defaults: defaults,
            fileManager: .default,
            verifier: AIModelVerifier(),
            downloader: downloader,
            descriptorProvider: { _ in descriptor },
            catalogErrorProvider: { nil },
            bundledSeedDirectoryProvider: bundledSeedDirectoryProvider,
            runtimeClient: runtimeClient
        )
        return AppState(
            settings: settings,
            provisioningService: ProvisioningService(),
            aiService: aiService,
            spotifyAuthService: SpotifyAuthService()
        )
    }

    private func makeDescriptor(
        modelID: String,
        assets: [StartupAssetFixture],
        estimatedDownloadSizeBytes: Int64? = nil
    ) -> AIModelDescriptor {
        AIModelDescriptor(
            id: modelID,
            displayName: "Test Model",
            providerID: "provider/test",
            revision: "revision-1",
            estimatedDownloadSizeBytes: estimatedDownloadSizeBytes
                ?? assets.reduce(0) { $0 + Int64($1.expectedData.count) },
            estimatedMemoryBytes: 0,
            notes: "Startup test descriptor",
            assetFiles: assets.map { asset in
                AIModelAsset(
                    path: asset.path,
                    sizeBytes: Int64(asset.expectedData.count),
                    checksum: sha256(asset.expectedData)
                )
            }
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct StartupAssetFixture {
    let path: String
    let expectedData: Data
}

private final class StartupFakeDownloader: ModelAssetDownloading {
    private let fileManager = FileManager.default
    private let assetDataByPath: [String: Data]
    private let progressChunkCount: Int
    private let chunkDelay: Duration
    private(set) var downloadedAssetPaths: [String] = []

    init(
        assetDataByPath: [String: Data],
        progressChunkCount: Int = 1,
        chunkDelay: Duration = .zero
    ) {
        self.assetDataByPath = assetDataByPath
        self.progressChunkCount = max(progressChunkCount, 1)
        self.chunkDelay = chunkDelay
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let path = remoteURL.lastPathComponent
        downloadedAssetPaths.append(path)

        guard let data = assetDataByPath[path] else {
            throw SubprocessError.executionFailed("No fixture data for \(path)", 1)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let totalChunks = max(progressChunkCount, 1)
        let minimumChunkSize = max(1, data.count / totalChunks)
        var writtenBytes = 0

        for chunkIndex in 0..<totalChunks {
            let nextSize: Int
            if chunkIndex == totalChunks - 1 {
                nextSize = data.count
            } else {
                nextSize = min(data.count, writtenBytes + minimumChunkSize)
            }

            try Data(data.prefix(nextSize)).write(to: destinationURL)
            writtenBytes = nextSize
            onProgress(Int64(writtenBytes))

            if chunkIndex < totalChunks - 1, chunkDelay > .zero {
                try await Task.sleep(for: chunkDelay)
            }
        }
    }
}

@MainActor
private final class FakeLocalAIRuntimeClient: LocalAIRuntimeClient {
    var loadedModelID: String?
    var runtimeLooksInstalledValue = false
    var runtimeNeedsPreparationValue = true
    var ensureRuntimeReadyCalls = 0
    var loadModelCalls: [(String, String)] = []
    var healthCheckCalls = 0
    var unloadCalls = 0
    var cancelGenerationCalls = 0
    var ensureRuntimeReadyError: Error?
    var loadModelError: Error?
    var healthCheckError: Error?
    var streamGenerateResponse = "Hello!"

    func runtimeLooksInstalled() -> Bool {
        runtimeLooksInstalledValue
    }

    func runtimeNeedsPreparation() async -> Bool {
        runtimeNeedsPreparationValue
    }

    func ensureRuntimeReady() async throws {
        ensureRuntimeReadyCalls += 1
        if let ensureRuntimeReadyError {
            throw ensureRuntimeReadyError
        }
        runtimeLooksInstalledValue = true
        runtimeNeedsPreparationValue = false
    }

    func loadModel(at modelDirectory: URL, modelID: String) async throws {
        loadModelCalls.append((modelID, modelDirectory.path))
        if let loadModelError {
            throw loadModelError
        }
        loadedModelID = modelID
    }

    func streamGenerate(
        messages: [LocalAIChatMessage],
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        onChunk(streamGenerateResponse)
        return streamGenerateResponse
    }

    func cancelGeneration() {
        cancelGenerationCalls += 1
    }

    func unloadModel() async {
        unloadCalls += 1
        loadedModelID = nil
    }

    func healthCheck() async throws {
        healthCheckCalls += 1
        if let healthCheckError {
            throw healthCheckError
        }
    }
}

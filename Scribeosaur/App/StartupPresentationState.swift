import Foundation

enum StartupPhase: Int, CaseIterable {
    case preparingWorkspace
    case tuningTranscription
    case unlockingSmartTools
    case finalChecks

    var title: String {
        switch self {
        case .preparingWorkspace:
            "Preparing your workspace"
        case .tuningTranscription:
            "Tuning transcription"
        case .unlockingSmartTools:
            "Unlocking smart tools"
        case .finalChecks:
            "Final checks"
        }
    }

    var progressRange: ClosedRange<Double> {
        switch self {
        case .preparingWorkspace:
            0.00...0.15
        case .tuningTranscription:
            0.15...0.35
        case .unlockingSmartTools:
            0.35...0.92
        case .finalChecks:
            0.92...1.00
        }
    }
}

enum StartupLaunchMode: Equatable {
    case firstInstall
    case returningQuickCheck
}

struct StartupVisibleStage: Equatable, Identifiable {
    let id: String
    let label: String
    let threshold: Double
}

enum ProvisioningStage: Equatable {
    case idle
    case checking
    case preparingResources
    case finalizing
    case ready
    case failed
}

enum LocalAIStartupStage: Equatable {
    case idle
    case preparingRuntime
    case preparingAssets
    case downloadingAssets
    case verifyingAssets
    case loading
    case ready
    case failed
}

struct StartupPresentationError: Equatable {
    let title: String
    let message: String
    let details: String
}

struct StartupPresentationState {
    static let returningQuickCheckMinimumDuration: TimeInterval = 2.0
    static let defaultModelSizeLabel = "6 GB"
    static let disallowedTerms = [
        "gemma",
        "ffmpeg",
        "yt-dlp",
        "uv",
        "deno",
        "mlx-lm",
    ]

    var launchMode: StartupLaunchMode = .firstInstall
    var phase: StartupPhase = .preparingWorkspace
    var headline = "A private transcript studio is taking shape."
    var detail = "First setup can take a few minutes on a new install."
    var targetProgress: Double = 0
    var displayProgress: Double = 0
    var visibleStages = StartupPresentationState.stages(
        for: .firstInstall,
        modelSizeLabel: StartupPresentationState.defaultModelSizeLabel,
        includesAIStages: true,
        includesDownloadStage: true
    )
    var activeStageIndex = 0
    var stageLabel = "Initialising Scribeosaur…"
    var errorState: StartupPresentationError?
    var minimumVisibleUntil: Date?

    private(set) var sessionStartedAt: Date?
    private var lastTickAt: Date?

    mutating func beginSession(
        now: Date,
        launchMode: StartupLaunchMode,
        visibleStages: [StartupVisibleStage]
    ) {
        self.launchMode = launchMode
        phase = .preparingWorkspace
        headline = launchMode == .firstInstall
            ? "A private transcript studio is taking shape."
            : "Running a quick readiness pass."
        detail = launchMode == .firstInstall
            ? "First setup can take a few minutes on a new install."
            : "Checking the essentials before you jump back in."
        targetProgress = 0
        displayProgress = 0
        errorState = nil
        sessionStartedAt = now
        lastTickAt = now
        minimumVisibleUntil = launchMode == .returningQuickCheck
            ? now.addingTimeInterval(Self.returningQuickCheckMinimumDuration)
            : nil
        self.visibleStages = visibleStages
        syncVisibleStageState()
    }

    mutating func update(
        phase: StartupPhase,
        headline: String,
        detail: String,
        targetProgress: Double,
        visibleStages: [StartupVisibleStage],
        now: Date
    ) {
        self.phase = phase
        self.headline = headline
        self.detail = detail
        self.targetProgress = min(max(targetProgress, 0), 1)
        self.visibleStages = visibleStages
        errorState = nil
        tick(now: now)
        syncVisibleStageState()
    }

    mutating func fail(details: String, now: Date) {
        errorState = StartupPresentationError(
            title: launchMode == .firstInstall ? "Setup paused" : "Readiness check paused",
            message: launchMode == .firstInstall
                ? "Scribeosaur hit a snag while finishing first setup. Retry to continue."
                : "Scribeosaur hit a snag while checking readiness. Retry to continue.",
            details: details
        )
        lastTickAt = now
    }

    mutating func tick(now: Date) {
        let baseline = lastTickAt ?? now
        let delta = min(max(now.timeIntervalSince(baseline), 0), 0.35)
        lastTickAt = now

        let phaseCap = phase.progressRange.upperBound - (targetProgress >= phase.progressRange.upperBound ? 0 : 0.012)
        let cappedTarget = min(max(targetProgress, displayProgress), phaseCap)
        let interpolation = min(delta * (launchMode == .firstInstall ? 3.0 : 3.6), 1.0)
        let easedProgress = displayProgress + ((cappedTarget - displayProgress) * interpolation)
        displayProgress = max(displayProgress, easedProgress)

        let hasHeadroom = cappedTarget - displayProgress < 0.004
        let driftCap = min(phaseCap, cappedTarget + (launchMode == .firstInstall ? 0.035 : 0.028))
        if hasHeadroom, driftCap > displayProgress {
            displayProgress = min(driftCap, displayProgress + delta * (launchMode == .firstInstall ? 0.010 : 0.014))
        }

        displayProgress = min(max(displayProgress, 0), 1)
    }

    mutating func complete(now: Date) {
        phase = .finalChecks
        targetProgress = 1
        lastTickAt = now
        displayProgress = max(displayProgress, 1)
        syncVisibleStageState()
    }

    private mutating func syncVisibleStageState() {
        guard !visibleStages.isEmpty else {
            activeStageIndex = 0
            stageLabel = ""
            return
        }

        let progress = max(displayProgress, min(targetProgress, 1))
        let resolvedIndex = visibleStages.lastIndex(where: { progress + 0.0001 >= $0.threshold }) ?? 0
        activeStageIndex = min(max(resolvedIndex, 0), visibleStages.count - 1)
        stageLabel = visibleStages[activeStageIndex].label
    }

    static func stages(
        for launchMode: StartupLaunchMode,
        modelSizeLabel: String,
        includesAIStages: Bool,
        includesDownloadStage: Bool
    ) -> [StartupVisibleStage] {
        switch launchMode {
        case .firstInstall:
            var stages = [
                StartupVisibleStage(id: "initialising", label: "Initialising Scribeosaur…", threshold: 0.00),
                StartupVisibleStage(id: "workspace", label: "Preparing your transcript workspace…", threshold: 0.08),
                StartupVisibleStage(id: "audio-pipeline", label: "Loading audio pipeline…", threshold: 0.16),
                StartupVisibleStage(id: "transcription", label: "Loading transcription engine…", threshold: 0.24),
                StartupVisibleStage(id: "local-ai-ready", label: "Checking local AI readiness…", threshold: 0.36),
            ]

            if includesDownloadStage {
                stages.append(
                    StartupVisibleStage(
                        id: "local-ai-download",
                        label: "Downloading local AI model (\(modelSizeLabel))…",
                        threshold: 0.54
                    )
                )
            }

            stages.append(
                contentsOf: [
                    StartupVisibleStage(
                        id: "local-ai-summaries",
                        label: "Loading on-device summaries…",
                        threshold: includesDownloadStage ? 0.88 : 0.80
                    ),
                    StartupVisibleStage(id: "almost-ready", label: "Almost ready…", threshold: 0.97),
                ]
            )
            return stages

        case .returningQuickCheck:
            var stages = [
                StartupVisibleStage(id: "initialising", label: "Refreshing Scribeosaur…", threshold: 0.00),
                StartupVisibleStage(id: "workspace", label: "Checking your transcript workspace…", threshold: 0.22),
                StartupVisibleStage(id: "transcription", label: "Checking transcription engine…", threshold: 0.50),
            ]

            if includesAIStages {
                stages.append(
                    StartupVisibleStage(id: "local-ai-ready", label: "Checking local AI readiness…", threshold: 0.64)
                )

                if includesDownloadStage {
                    stages.append(
                        StartupVisibleStage(
                            id: "local-ai-download",
                            label: "Downloading local AI model (\(modelSizeLabel))…",
                            threshold: 0.74
                        )
                    )
                }

                stages.append(
                    StartupVisibleStage(
                        id: "local-ai-summaries",
                        label: "Refreshing on-device summaries…",
                        threshold: includesDownloadStage ? 0.88 : 0.80
                    )
                )
            }

            stages.append(
                StartupVisibleStage(
                    id: "almost-ready",
                    label: "Almost ready…",
                    threshold: includesAIStages ? 0.94 : 0.82
                )
            )
            return stages
        }
    }

    static func defaultCopyDeck() -> [String] {
        let firstInstallStages = stages(
            for: .firstInstall,
            modelSizeLabel: defaultModelSizeLabel,
            includesAIStages: true,
            includesDownloadStage: true
        ).map(\.label)
        let returningStages = stages(
            for: .returningQuickCheck,
            modelSizeLabel: defaultModelSizeLabel,
            includesAIStages: true,
            includesDownloadStage: true
        ).map(\.label)
        let defaultStates = [
            "A private transcript studio is taking shape.",
            "First setup can take a few minutes on a new install.",
            "Running a quick readiness pass.",
            "Checking the essentials before you jump back in.",
            "Setup paused",
            "Readiness check paused",
            "Scribeosaur hit a snag while finishing first setup. Retry to continue.",
            "Scribeosaur hit a snag while checking readiness. Retry to continue.",
        ]
        return firstInstallStages + returningStages + defaultStates
    }

    static func containsDisallowedTerm(in text: String) -> String? {
        let lowercase = text.lowercased()
        return disallowedTerms.first(where: { lowercase.contains($0) })
    }
}

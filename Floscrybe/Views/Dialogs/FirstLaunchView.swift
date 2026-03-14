import SwiftUI

struct FirstLaunchView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(ColorTokens.textSecondary)

            Text("Floscrybe")
                .font(Typography.largeTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Setting up for first use")
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)

            VStack(spacing: Spacing.md) {
                if appState.binaryDownloadService.isDownloading {
                    ProgressView(value: appState.binaryDownloadService.progress)
                        .tint(ColorTokens.progressFill)
                        .frame(width: 300)

                    Text(appState.binaryDownloadService.statusMessage)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                if appState.transcriptionService.modelLoadProgress > 0
                    && appState.transcriptionService.modelLoadProgress < 1.0 {
                    ProgressView(value: appState.transcriptionService.modelLoadProgress)
                        .tint(ColorTokens.progressFill)
                        .frame(width: 300)

                    Text("Loading transcription model...")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                if let error = appState.binaryDownloadService.error ?? appState.setupError {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.statusError)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Retry") {
                        Task { await startSetup() }
                    }
                    .buttonStyle(.primary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.backgroundBase)
        .task {
            await startSetup()
        }
    }

    private func startSetup() async {
        await MainActor.run {
            appState.isReady = false
            appState.setupError = nil
        }
        await appState.binaryDownloadService.downloadIfNeeded()
        guard appState.binaryDownloadService.error == nil else {
            return
        }
        await appState.loadModels()

        if appState.isReady {
            appState.settings.hasCompletedFirstLaunch = true
        }
    }
}

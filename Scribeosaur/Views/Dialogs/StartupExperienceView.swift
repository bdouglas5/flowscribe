import SwiftUI

private enum StartupLoadingPalette {
    static let background = Color(red: 0.015, green: 0.017, blue: 0.018)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.58)
    static let textMuted = Color.white.opacity(0.36)
    static let track = Color.white.opacity(0.12)
    static let fill = Color(red: 0.58, green: 0.92, blue: 0.45)
    static let fillHighlight = Color(red: 0.76, green: 1.0, blue: 0.58)
    static let errorSurface = Color.white.opacity(0.06)
    static let errorBorder = Color.white.opacity(0.10)
}

struct StartupExperienceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsErrorDetails = false

    private var presentation: StartupPresentationState {
        appState.startupPresentation
    }

    var body: some View {
        ZStack {
            StartupLoadingPalette.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Scribeosaur")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupLoadingPalette.textPrimary)
                    .textCase(.uppercase)
                    .tracking(2.4)

                StartupMascotView(reduceMotion: reduceMotion)
                    .frame(width: 128, height: 96)
                    .clipped()

                if let errorState = presentation.errorState {
                    StartupMinimalErrorView(
                        errorState: errorState,
                        showsDetails: $showsErrorDetails,
                        isRetrying: appState.isStartingUp,
                        onRetry: { Task { await appState.startApplication() } }
                    )
                    .frame(maxWidth: 420)
                } else {
                    StartupMinimalStatusView(
                        presentation: presentation,
                        reduceMotion: reduceMotion
                    )
                    .frame(maxWidth: 420)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: presentation.errorState) { _, _ in
            showsErrorDetails = false
        }
    }
}

private struct StartupMascotView: View {
    let reduceMotion: Bool
    @State private var content: StartupMascotAsset.Content = .unavailable

    var body: some View {
        mascotView
            .task(id: reduceMotion) {
                content = StartupMascotAsset.loadContent(reduceMotion: reduceMotion)
            }
    }

    @ViewBuilder
    private var mascotView: some View {
        switch content {
        case .animated(let image):
            AnimatedGIFView(image: image, animates: true)
                .frame(width: 128, height: 96)
                .clipped()

        case .staticFrame(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 96)
                .clipped()

        case .unavailable:
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(StartupLoadingPalette.textMuted)
                .frame(width: 72, height: 72)
        }
    }
}

private struct StartupMinimalStatusView: View {
    let presentation: StartupPresentationState
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(presentation.stageLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StartupLoadingPalette.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            StartupMinimalProgressBar(
                progress: presentation.displayProgress,
                reduceMotion: reduceMotion
            )
            .frame(height: 7)

            Text(presentation.detail)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(StartupLoadingPalette.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StartupMinimalProgressBar: View {
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = max(12, proxy.size.width * clampedProgress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StartupLoadingPalette.track)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                StartupLoadingPalette.fill,
                                StartupLoadingPalette.fillHighlight,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)

                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let cycle = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.8) / 1.8
                        let sheenWidth = max(proxy.size.width * 0.14, 42)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(0.30),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: sheenWidth)
                            .offset(x: (proxy.size.width + sheenWidth) * cycle - sheenWidth)
                            .mask(
                                Capsule()
                                    .frame(width: fillWidth)
                            )
                    }
                }
            }
        }
    }
}

private struct StartupMinimalErrorView: View {
    let errorState: StartupPresentationError
    @Binding var showsDetails: Bool
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 7) {
                Text(errorState.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupLoadingPalette.textPrimary)

                Text(errorState.message)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(StartupLoadingPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button(isRetrying ? "Retrying..." : "Retry") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .tint(StartupLoadingPalette.fill)
            .disabled(isRetrying)

            if !errorState.details.isEmpty {
                DisclosureGroup("Details", isExpanded: $showsDetails) {
                    Text(errorState.details)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(StartupLoadingPalette.textMuted)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
                .foregroundStyle(StartupLoadingPalette.textMuted)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(StartupLoadingPalette.errorSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(StartupLoadingPalette.errorBorder, lineWidth: 1)
        )
    }
}

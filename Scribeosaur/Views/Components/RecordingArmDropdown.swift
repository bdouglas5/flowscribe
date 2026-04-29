import SwiftUI

struct RecordingArmDropdown: View {
    let state: RecordingSessionState
    let inputName: String
    let modeName: String
    let onOpenSettings: () -> Void
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                metadataRow(title: "Input", value: inputName)
                metadataRow(title: "Mode", value: modeName)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTokens.backgroundFloat)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ColorTokens.border.opacity(0.65), lineWidth: 1)
            )

            Text(messageText)
                .font(Typography.caption)
                .foregroundStyle(messageColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.sm) {
                Button("Recording Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.utility)

                Spacer(minLength: 0)

                Button(primaryButtonTitle) {
                    onStart()
                }
                .buttonStyle(.compactPrimary)
                .disabled(!state.canStartRecording)
            }
        }
        .padding(14)
        .frame(width: 304, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTokens.backgroundRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ColorTokens.border.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            // Absorb taps so the background overlay doesn't dismiss the panel.
        }
        .overlay {
            Button("") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(ColorTokens.textMuted)

            Spacer(minLength: Spacing.md)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ColorTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var titleText: String {
        switch state.warmupState {
        case .warming:
            return "Preparing recorder"
        case .failed:
            return "Recorder needs attention"
        case .idle, .ready:
            return "Ready to record"
        }
    }

    private var messageText: String {
        switch state.warmupState {
        case .warming:
            return state.warmupMessage ?? "Preparing recorder…"
        case .failed:
            return state.warmupMessage ?? "Recorder warm-up failed. Start Recording will retry."
        case .idle, .ready:
            return "Change input or mode in Recording Settings."
        }
    }

    private var messageColor: Color {
        state.warmupState == .failed ? ColorTokens.statusError : ColorTokens.textMuted
    }

    private var statusColor: Color {
        switch state.warmupState {
        case .failed:
            return ColorTokens.statusError
        case .warming:
            return ColorTokens.accentBlue
        case .idle, .ready:
            return ColorTokens.textSecondary
        }
    }

    private var primaryButtonTitle: String {
        state.warmupState.isPreparing ? "Preparing…" : "Start Recording"
    }
}

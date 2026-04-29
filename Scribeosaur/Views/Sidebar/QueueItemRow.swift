import SwiftUI

struct QueueItemRow: View {
    let item: QueueItem
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.title)
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    statusIcon
                    Text(item.statusLabel)
                        .font(Typography.caption)
                        .foregroundStyle(statusColor)
                }

                if item.isProcessing {
                    ProgressView(value: item.progress)
                        .tint(ColorTokens.progressFill)
                        .scaleEffect(y: 0.5)
                }

                if let error = item.userFacingError ?? item.errorMessage {
                    HStack {
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.statusError)
                            .lineLimit(2)

                        if let onRetry, let recoveryAction = item.recoveryAction {
                            Button(recoveryAction.title) { onRetry() }
                                .font(Typography.caption)
                                .buttonStyle(.secondary)
                        }
                    }
                }
            }

            if item.isCancellable, let onCancel {
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ColorTokens.textMuted)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(ColorTokens.textMuted)
        case .resolving, .downloading, .converting, .transcribing, .diarizing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ColorTokens.textSecondary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ColorTokens.statusError)
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .failed: ColorTokens.statusError
        case .completed: ColorTokens.textSecondary
        default: ColorTokens.textMuted
        }
    }
}

import SwiftUI

struct TranscriptRow: View {
    let transcript: Transcript

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ThumbnailView(
                thumbnailURL: transcript.thumbnailURL,
                category: TranscriptCategory.category(for: transcript),
                size: 32,
                shape: .rounded
            )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(transcript.title)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(1)

                Text(metadataString)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var metadataString: String {
        var parts: [String] = [TimeFormatting.relativeDate(transcript.createdAt)]
        if let duration = transcript.durationSeconds, duration > 0 {
            parts.append(TimeFormatting.duration(seconds: duration))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

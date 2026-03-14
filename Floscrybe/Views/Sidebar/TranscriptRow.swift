import SwiftUI

struct TranscriptRow: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                if let remoteSource = transcript.remoteSource {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(ColorTokens.textMuted)
                }

                Text(transcript.title)
                    .font(Typography.headline)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let index = transcript.collectionItemIndex {
                    Text("#\(index)")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            HStack(spacing: Spacing.sm) {
                Text(TimeFormatting.relativeDate(transcript.createdAt))
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)

                if let duration = transcript.durationSeconds {
                    Text(TimeFormatting.duration(seconds: duration))
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }

                if transcript.speakerDetection && transcript.speakerCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.system(size: 9))
                        Text("\(transcript.speakerCount)")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(ColorTokens.textMuted)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

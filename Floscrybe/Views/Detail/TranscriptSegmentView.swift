import SwiftUI

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let showTimestamps: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if showTimestamps {
                Text(TimeFormatting.bracketedRange(start: segment.startTime, end: segment.endTime))
                    .font(Typography.mono)
                    .foregroundStyle(ColorTokens.textMuted)
                    .frame(minWidth: 140, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let speakerName = segment.speakerName {
                    Text(speakerName)
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textSecondary)
                }

                Text(segment.text)
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

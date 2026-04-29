import SwiftUI

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let showTimestamps: Bool
    var searchQuery: String = ""
    var currentGlobalMatchIndex: Int = 0
    var globalMatchOffset: Int = 0

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

                if !searchQuery.isEmpty {
                    HighlightedText(
                        text: segment.text,
                        query: searchQuery,
                        currentGlobalMatchIndex: currentGlobalMatchIndex,
                        globalMatchOffset: globalMatchOffset
                    )
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .textSelection(.enabled)
                } else {
                    Text(segment.text)
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

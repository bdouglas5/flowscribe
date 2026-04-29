import SwiftUI

struct SpotifyEpisodeRow: View {
    let episode: SpotifyEpisode
    var isExclusive: Bool = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(episode.name)
                        .font(Typography.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(2)

                    if episode.isFullyPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ColorTokens.progressFill)
                            .help("Fully played")
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Text(episode.formattedDuration)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Text(episode.releaseDate)
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            Spacer()

            if isExclusive {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(ColorTokens.statusError)
                    .help("Spotify Exclusive — cannot download")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .opacity(isExclusive ? 0.5 : 1.0)
    }
}

import SwiftUI

struct SpotifyShowRow: View {
    let show: SpotifyShow
    var isExclusive: Bool = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            AsyncImage(url: show.bestImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderImage
                default:
                    placeholderImage
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(show.name)
                        .font(Typography.headline)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(1)

                    if isExclusive {
                        Text("Exclusive")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ColorTokens.statusError)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(ColorTokens.statusError.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(show.publisher)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textMuted)
                    .lineLimit(1)

                if let count = show.totalEpisodes {
                    Text("\(count) episodes")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .opacity(isExclusive ? 0.5 : 1.0)
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(ColorTokens.backgroundFloat)
            .overlay {
                Image(systemName: "mic.fill")
                    .foregroundStyle(ColorTokens.textMuted)
                    .font(.system(size: 16))
            }
    }
}

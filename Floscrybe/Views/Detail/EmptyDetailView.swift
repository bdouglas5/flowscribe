import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: 16)
                .fill(ColorTokens.backgroundFloat)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundStyle(ColorTokens.textMuted)
                }

            Text("Drop audio or video here")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Or paste a YouTube URL to get started")
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textMuted)

            HStack(spacing: Spacing.xs) {
                ForEach(["mp3", "wav", "mp4", "mkv", "mov"], id: \.self) { ext in
                    Text(ext.uppercased())
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(ColorTokens.textMuted)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ColorTokens.backgroundFloat)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.backgroundRaised)
    }
}

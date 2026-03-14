import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(ColorTokens.textMuted)

            Text("Drop audio or video files here")
                .font(Typography.title)
                .foregroundStyle(ColorTokens.textSecondary)

            Text("Or paste a YouTube URL")
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textMuted)

            HStack(spacing: Spacing.sm) {
                ForEach(["mp3", "wav", "mp4", "mkv", "mov"], id: \.self) { ext in
                    Text(ext)
                        .font(Typography.caption)
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
        .background(ColorTokens.backgroundBase)
    }
}

import SwiftUI

struct DropZoneOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTokens.backgroundBase.opacity(0.85))

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    ColorTokens.textMuted,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(Spacing.md)

            VStack(spacing: Spacing.md) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 36))
                    .foregroundStyle(ColorTokens.textSecondary)

                Text("Drop to transcribe")
                    .font(Typography.title)
                    .foregroundStyle(ColorTokens.textPrimary)
            }
        }
    }
}

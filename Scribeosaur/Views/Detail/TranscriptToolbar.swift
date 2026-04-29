import AppKit
import SwiftUI

struct TranscriptToolbar: View {
    let transcript: Transcript
    let segments: [TranscriptSegment]
    @Binding var showTimestamps: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                ExportService.copyToClipboard(
                    segments: segments,
                    showTimestamps: showTimestamps
                )
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ColorTokens.textPrimary)

            toolbarDivider

            Button {
                ExportService.exportMarkdown(
                    transcript: transcript,
                    segments: segments,
                    showTimestamps: showTimestamps
                )
            } label: {
                Label("Export .md", systemImage: "square.and.arrow.up")
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ColorTokens.textPrimary)

            toolbarDivider
            HStack(spacing: Spacing.xs) {
                Text("Timestamps")
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
                Toggle("", isOn: $showTimestamps)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(ColorTokens.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(ColorTokens.backgroundRaised)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(ColorTokens.border, lineWidth: 0.5)
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(ColorTokens.border)
            .frame(width: 1, height: 16)
    }
}

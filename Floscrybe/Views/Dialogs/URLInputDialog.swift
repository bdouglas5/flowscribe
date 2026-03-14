import SwiftUI

struct URLInputDialog: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var urlString = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Paste URL")
                .font(Typography.title)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Paste a YouTube video, playlist, or channel URL to download and transcribe.")
                .font(Typography.body)
                .foregroundStyle(ColorTokens.textSecondary)

            TextField("https://youtube.com/watch?v=...", text: $urlString)
                .textFieldStyle(.plain)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorTokens.backgroundBase)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ColorTokens.border, lineWidth: 1)
                )
                .onSubmit { submit() }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(ColorTokens.statusError)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.secondary)

                Button("Download & Transcribe") {
                    submit()
                }
                .buttonStyle(.primary)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480)
        .background(ColorTokens.backgroundFloat)
    }

    private func submit() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard YTDLPService.isValidURL(trimmed) else {
            errorMessage = "URL not recognized. Paste a YouTube URL."
            return
        }

        appState.enqueueURL(
            trimmed,
            speakerDetection: appState.settings.speakerDetection,
            speakerNames: []
        )
        isPresented = false
    }
}

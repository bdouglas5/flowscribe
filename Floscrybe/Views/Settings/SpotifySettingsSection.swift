import SwiftUI

struct SpotifySettingsSection: View {
    @Environment(AppState.self) private var appState

    @State private var clientIDInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Client ID")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    TextField("Spotify Client ID", text: $clientIDInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            appState.settings.spotifyClientID = trimmed.isEmpty ? nil : trimmed
                        }
                        .onChange(of: clientIDInput) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            appState.settings.spotifyClientID = trimmed.isEmpty ? nil : trimmed
                        }

                    Text("Create a Spotify app at developer.spotify.com/dashboard to get a Client ID. Set the redirect URI to **http://127.0.0.1:19836/callback**.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            sectionHeader("Spotify Account")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(appState.spotifyAuthService.statusLabel)
                                .font(Typography.headline)
                                .foregroundStyle(ColorTokens.textPrimary)

                            if appState.spotifyAuthService.isAuthenticated {
                                Text("Connected to Spotify")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                            } else {
                                Text("Not connected")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                            }
                        }

                        Spacer()

                        spotifyStatusBadge
                    }

                    Divider()

                    HStack(spacing: Spacing.sm) {
                        if appState.spotifyAuthService.isAuthenticated {
                            Button("Disconnect") {
                                appState.spotifyAuthService.disconnect()
                            }
                            .buttonStyle(.secondary)
                        } else {
                            Button("Connect Spotify") {
                                connectSpotify()
                            }
                            .buttonStyle(.primary)
                            .disabled(effectiveClientID.isEmpty || appState.spotifyAuthService.isAuthenticating)
                        }

                        if appState.spotifyAuthService.isAuthenticating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ColorTokens.progressFill)
                        }
                    }

                    if let error = appState.spotifyAuthService.lastError {
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.statusError)
                    }
                }
            }

            sectionHeader("How It Works")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Floscrybe uses the Spotify API to browse your saved podcasts and discover episodes. Audio is downloaded from public RSS feeds (not from Spotify directly).")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)

                    Text("Spotify-exclusive podcasts that have no public RSS feed cannot be downloaded. You'll see a warning when this applies.")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }

            sectionHeader("Auto-Download Finished Episodes")
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if appState.spotifyAuthService.isAuthenticated {
                        Toggle("Automatically transcribe finished episodes", isOn: Binding(
                            get: { appState.settings.spotifyAutoDownloadEnabled },
                            set: { newValue in
                                appState.settings.spotifyAutoDownloadEnabled = newValue
                                appState.updateAutoDownloadPolling()
                            }
                        ))

                        if appState.settings.spotifyAutoDownloadEnabled {
                            Divider()

                            Picker("Check every", selection: Binding(
                                get: { appState.settings.spotifyAutoDownloadIntervalMinutes },
                                set: { newValue in
                                    appState.settings.spotifyAutoDownloadIntervalMinutes = newValue
                                    appState.updateAutoDownloadPolling()
                                }
                            )) {
                                Text("15 minutes").tag(15)
                                Text("30 minutes").tag(30)
                                Text("1 hour").tag(60)
                                Text("2 hours").tag(120)
                                Text("4 hours").tag(240)
                            }

                            HStack {
                                Text("\(appState.settings.spotifyProcessedEpisodeIDs.count) episodes processed")
                                    .font(Typography.caption)
                                    .foregroundStyle(ColorTokens.textMuted)
                                Spacer()
                                Button("Reset") {
                                    appState.settings.spotifyProcessedEpisodeIDs = []
                                    appState.resetSessionBaseline()
                                }
                                .buttonStyle(.secondary)
                                .controlSize(.small)
                            }
                        }

                        Text("When enabled, Floscrybe periodically checks your Spotify saved episodes for newly finished listens and automatically enqueues them for transcription.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    } else {
                        Text("Connect to Spotify above to enable auto-download of finished episodes.")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .onAppear {
            clientIDInput = appState.settings.spotifyClientID ?? ""
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.headline)
            .foregroundStyle(ColorTokens.textPrimary)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTokens.backgroundFloat)
            )
    }

    private var effectiveClientID: String {
        clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var spotifyStatusBadge: some View {
        let label: String
        let color: Color

        if appState.spotifyAuthService.isAuthenticating {
            label = "Connecting"
            color = ColorTokens.backgroundHover
        } else if appState.spotifyAuthService.isAuthenticated {
            label = "Connected"
            color = ColorTokens.progressFill
        } else {
            label = "Disconnected"
            color = ColorTokens.backgroundFloat
        }

        return Text(label)
            .font(Typography.caption)
            .foregroundStyle(ColorTokens.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(color)
            .clipShape(Capsule())
    }

    private func connectSpotify() {
        let clientID = effectiveClientID
        guard !clientID.isEmpty else { return }
        appState.settings.spotifyClientID = clientID

        Task {
            await appState.spotifyAuthService.authorize(clientID: clientID)
        }
    }
}

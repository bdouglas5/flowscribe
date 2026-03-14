import SwiftUI

@main
struct FloscrybeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if !appState.isReady {
                    FirstLaunchView()
                } else {
                    ContentView()
                }
            }
            .environment(appState)
            .preferredColorScheme(.dark)
            .task {
                await appState.initialize()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}

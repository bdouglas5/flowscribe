import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            .onPasteCommand(of: [.plainText, .url]) { _ in
                handlePasteCommand()
            }
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

    private func handlePasteCommand() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }

        _ = appState.enqueueSupportedURLFromPasteboard()
    }
}

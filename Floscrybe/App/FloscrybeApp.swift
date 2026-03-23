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
            .preferredColorScheme(appState.settings.resolvedColorScheme)
            .task {
                await appState.initialize()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    handlePasteCommand()
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Paste URL") {
                    _ = appState.enqueueSupportedURLFromPasteboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(appState.settings.resolvedColorScheme)
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

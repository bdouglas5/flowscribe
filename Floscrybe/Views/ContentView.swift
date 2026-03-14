import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false
    @State private var showURLInput = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let transcript = appState.selectedTranscript {
                TranscriptDetailView(transcript: transcript)
            } else {
                EmptyDetailView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showURLInput = true
                } label: {
                    Image(systemName: "link.badge.plus")
                }
                .help("Paste URL or press Command-V")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                DropZoneOverlay()
            }
        }
        .sheet(isPresented: $showURLInput) {
            URLInputDialog(isPresented: $showURLInput)
        }
        .background(ColorTokens.backgroundBase)
        .frame(minWidth: 700, minHeight: 500)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                if FFmpegService.isSupported(url) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            appState.enqueueFiles(
                urls: urls,
                speakerDetection: appState.settings.speakerDetection,
                speakerNames: []
            )
        }
    }
}

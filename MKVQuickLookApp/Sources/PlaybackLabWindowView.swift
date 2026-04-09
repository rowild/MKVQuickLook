import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PlaybackLabWindowView: View {
    @State private var selectedFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Renderer Lab")
                    .font(.title.weight(.semibold))
                Text("This window uses the same shared VLCKit player and fit-box layout as the Quick Look extension. Validate centering here before testing Finder.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Open Media…") {
                    pickMediaFile()
                }

                if let selectedFileURL {
                    Text(selectedFileURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file loaded")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedFileURL != nil {
                    Button("Clear") {
                        selectedFileURL = nil
                    }
                }
            }

            PlaybackLabControllerRepresentable(fileURL: selectedFileURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
    }

    private func pickMediaFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AppStatusViewModel.supportedImporterExtensions.compactMap { UTType(filenameExtension: $0) }

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }
}

private struct PlaybackLabControllerRepresentable: NSViewControllerRepresentable {
    let fileURL: URL?

    func makeNSViewController(context: Context) -> PlaybackLabViewController {
        PlaybackLabViewController()
    }

    func updateNSViewController(_ nsViewController: PlaybackLabViewController, context: Context) {
        nsViewController.loadFile(fileURL)
    }
}

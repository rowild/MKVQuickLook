import SwiftUI

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    let viewModel: AppStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MKVQuickLook")
                    .font(.largeTitle.weight(.semibold))
                Text("Finder Quick Look previews for MKV, WebM, Ogg, and Opus files.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Current State") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Version: \(viewModel.appVersion)")
                    Text("Embedded extensions: \(viewModel.embeddedExtensionNames.joined(separator: ", ").ifEmpty("None detected"))")
                    Text("Playback backend: \(viewModel.playbackBackend)")
                    Text("Backend distribution: bundled inside the app; the Quick Look extension loads it from there")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Supported Formats") {
                Text(viewModel.supportedFormats.joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            GroupBox("Renderer Lab") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Play a file outside Finder with the same player that the Quick Look extension uses.")
                    Button("Open Renderer Lab") {
                        openWindow(id: "renderer-lab")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(24)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

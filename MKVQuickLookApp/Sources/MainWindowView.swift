import SwiftUI

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    let viewModel: AppStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MKVQuickLook")
                    .font(.largeTitle.weight(.semibold))
                Text("Finder Quick Look preview extension scaffold for MKV, WebM, Ogg/Theora, and best-effort AVI.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Current State") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Version: \(viewModel.appVersion)")
                    Text("Embedded extensions: \(viewModel.embeddedExtensionNames.joined(separator: ", ").ifEmpty("None detected"))")
                    Text("Playback backend: \(viewModel.playbackBackend)")
                    Text("Backend distribution: bundled inside the app extension")
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

            GroupBox("Next Implementation Step") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use the renderer lab to validate centering and playback behavior outside Finder before changing the Quick Look extension again.")
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

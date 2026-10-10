import AppKit
import SwiftUI

struct SettingsView: View {
    // Must match THIRD_PARTY_NOTICES.md and the VLCKit version in scripts/bootstrap-vlckit.sh.
    private static let vlckitSourceURL = URL(string: "https://code.videolan.org/videolan/VLCKit/-/tree/3.7.2")!

    let viewModel: AppStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This utility hosts the Quick Look preview extension.")
                    Text("The extension plays supported files with VLCKit inside the Quick Look window.")
                        .foregroundStyle(.secondary)
                    Text("No external VLC installation or runtime download is required.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("License") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MKVQuickLook is released under the MIT License.")
                    Text("It contains VLCKit 3.7.2 (VLC 3.0.23), licensed under the GNU LGPL 2.1 or later. The license texts and the links to the source code ship inside the app.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Link("VLCKit Source Code", destination: Self.vlckitSourceURL)
                        Button("Show License Files") {
                            let files = ["LICENSE", "VLCKit-COPYING.txt", "THIRD_PARTY_NOTICES.md"]
                                .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
                            NSWorkspace.shared.activateFileViewerSelecting(files)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Troubleshooting") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.troubleshootingSteps, id: \.self) { step in
                        Text("- \(step)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Bundle Details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Host app version: \(viewModel.appVersion)")
                    Text("Preview extension bundle id: \(viewModel.previewExtensionBundleIdentifier)")
                    Text("Playback backend: \(viewModel.playbackBackend)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(20)
    }
}

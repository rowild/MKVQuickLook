import SwiftUI

struct SettingsView: View {
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

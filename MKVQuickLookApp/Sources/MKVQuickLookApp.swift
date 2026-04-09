import SwiftUI

@main
struct MKVQuickLookApp: App {
    var body: some Scene {
        WindowGroup("MKVQuickLook") {
            MainWindowView(viewModel: AppStatusViewModel())
        }
        .defaultSize(width: 760, height: 520)

        Window("Renderer Lab", id: "renderer-lab") {
            PlaybackLabWindowView()
        }
        .defaultSize(width: 1100, height: 820)

        Settings {
            SettingsView(viewModel: AppStatusViewModel())
                .frame(width: 520, height: 420)
        }
    }
}

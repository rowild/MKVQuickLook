import Foundation

struct AppStatusViewModel {
    let supportedFormats: [String] = ["mkv", "webm", "ogg", "ogv", "opus"]
    let previewExtensionBundleIdentifier = "com.robertwildling.MKVQuickLook.PreviewExtension"
    let playbackBackend = "VLCKit 3.7.2"
    // The Renderer Lab also opens avi/mp4/mov for comparison; Quick Look does not advertise them.
    static let supportedImporterExtensions = ["mkv", "webm", "ogg", "ogv", "opus", "avi", "mp4", "mov"]

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    var embeddedExtensionNames: [String] {
        guard let builtInPlugInsURL = Bundle.main.builtInPlugInsURL else {
            return []
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: builtInPlugInsURL,
            includingPropertiesForKeys: nil
        )) ?? []

        return contents
            .filter { $0.pathExtension == "appex" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    var troubleshootingSteps: [String] {
        [
            "Launch the app at least once after copying it to Applications.",
            "In Finder, select a supported file and press Space to invoke Quick Look.",
            "If Finder keeps using a stale preview, run qlmanage -r and reopen Finder.",
            "This app is not notarized. Gatekeeper may warn the first time you open it on another Mac.",
            "The Renderer Lab window plays files with the same player that the Quick Look extension uses.",
            "VLCKit is licensed under the LGPL 2.1. The license text ships inside the app at Contents/Resources/VLCKit-COPYING.txt."
        ]
    }
}

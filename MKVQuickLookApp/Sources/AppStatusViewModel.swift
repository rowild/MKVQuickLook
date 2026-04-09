import Foundation

struct AppStatusViewModel {
    let supportedFormats: [String] = ["mkv", "webm", "ogg", "ogv", "avi (best-effort)"]
    let previewExtensionBundleIdentifier = "com.robertwildling.MKVQuickLook.PreviewExtension"
    let playbackBackend = "VLCKit 3.7.2"
    static let supportedImporterExtensions = ["mkv", "webm", "ogg", "ogv", "avi", "mp4", "mov"]

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
            "Unsigned builds may trigger Gatekeeper on other Macs. That is expected in the current phase.",
            "The host app now includes a renderer lab window that uses the same shared player path as the Quick Look extension.",
            "The vendored VLCKit license text is stored in Vendor/VLCKit-COPYING.txt."
        ]
    }
}

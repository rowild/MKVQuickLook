import Foundation

/// Start options for MKVQuickLook's VLC engine (VLCKit's shared library).
///
/// VLCKit 3.7.2 saves VLC's settings after every media release and input close
/// (its libvlc patches 0015 and 0024). That save reads VLC's settings lock twice. On
/// macOS a waiting writer blocks the second read: a writer is an audio output that
/// closes at every stop, or a volume change. The process then freezes. VLC skips the
/// save before the second read when its settings file is read-only. So the engine
/// gets its own, read-only settings file. This also keeps VLC away from VLC.app's
/// settings file (~/Library/Preferences/org.videolan.vlc/vlcrc).
enum VLCEngineConfiguration {
    /// The user defaults key that VLCKit reads its library options from.
    private static let optionsDefaultsKey = "VLCParams"

    /// VLCKit 3.7.2's own macOS options (`-[VLCLibrary _defaultOptions]`). A value for
    /// `VLCParams` replaces them, so they are repeated here.
    private static let vlckitDefaultOptions = [
        "--play-and-pause",
        "--no-color",
        "--no-video-title-show",
        "--verbose=4",
        "--no-sout-keep",
        "--vout=macosx",
        "--text-renderer=freetype",
        "--extraintf=macosx_dialog_provider",
        "--audio-resampler=soxr",
    ]

    /// Inside the sandbox container for the Quick Look extension.
    static let settingsFileURL = URL.applicationSupportDirectory
        .appendingPathComponent("MKVQuickLook", isDirectory: true)
        .appendingPathComponent("vlcrc")

    /// Must run before the first VLCKit object exists: VLCKit reads its options once,
    /// when it creates the shared library.
    static func applyOnce() {
        _ = appliedOnce
    }

    private static let appliedOnce: Void = apply(settingsFile: settingsFileURL, defaults: .standard)

    static func apply(settingsFile: URL, defaults: UserDefaults) {
        do {
            try prepareReadOnlySettingsFile(at: settingsFile)
        } catch {
            // VLC still uses the private file, but the freeze protection is off.
            PlaybackDiagnostics.log("[engine] settings file is not read-only: \(error.localizedDescription)")
        }
        // VLC keeps volume-save on: with a read-only file the saved volume stays in
        // memory. Without it, VLC restarts at 100% after stop and play.
        defaults.set(vlckitDefaultOptions + ["--config=\(settingsFile.path)"], forKey: optionsDefaultsKey)
    }

    static func prepareReadOnlySettingsFile(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    }
}

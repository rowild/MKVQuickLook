import AppKit

enum MediaPreviewPlaybackState: Equatable {
    case idle
    case opening
    case buffering
    case playing
    case paused
    case stopped
    case ended
    case failed(String)
}

struct MediaPreviewPlaybackMetrics: Equatable {
    let position: Float
    let isSeekable: Bool
    let elapsedText: String
    let remainingText: String
    let volume: Int
}

@MainActor
protocol MediaPreviewPlayer: AnyObject {
    var renderView: NSView { get }
    var playbackStateDidChange: ((MediaPreviewPlaybackState) -> Void)? { get set }
    var playbackMetricsDidChange: ((MediaPreviewPlaybackMetrics) -> Void)? { get set }
    var videoPresentationSizeDidChange: ((CGSize?) -> Void)? { get set }
    var videoOutputVisibilityDidChange: ((Bool) -> Void)? { get set }

    func loadMedia(from url: URL)
    func primeForPausedStart()
    func play()
    func pause()
    func setMuted(_ muted: Bool)
    func setVolume(_ volume: Int, interactionID: PlaybackDiagnostics.InteractionID?)
    func beginScrubbing(interactionID: PlaybackDiagnostics.InteractionID?)
    func endScrubbing(interactionID: PlaybackDiagnostics.InteractionID?)
    func seek(to position: Float, isFinal: Bool, interactionID: PlaybackDiagnostics.InteractionID?)
    func refreshVideoLayout()
    func togglePlayback()
    func stop()
}

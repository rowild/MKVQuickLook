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

struct VolumeFeedbackState {
    private(set) var pendingVolume: Int = 100

    mutating func registerRequestedVolume(_ volume: Int) {
        pendingVolume = max(0, min(200, volume))
    }

    mutating func effectiveVolume(actualVolume: Int) -> Int {
        return pendingVolume
    }

    mutating func clear() {
        pendingVolume = 100
    }
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

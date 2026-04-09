import AppKit
import Foundation
import VLCKit

@MainActor
final class VLCKitMediaPreviewPlayer: NSObject, MediaPreviewPlayer {
    private enum Constants {
        static let seekCoalescingInterval: TimeInterval = 0.03
    }

    let renderView: NSView
    var playbackStateDidChange: ((MediaPreviewPlaybackState) -> Void)?
    var playbackMetricsDidChange: ((MediaPreviewPlaybackMetrics) -> Void)?
    var videoPresentationSizeDidChange: ((CGSize?) -> Void)?
    var videoOutputVisibilityDidChange: ((Bool) -> Void)?

    private let videoView: VLCVideoView
    private let mediaPlayer: VLCMediaPlayer
    private var pendingSeekPosition: Float?
    private var pendingSeekWorkItem: DispatchWorkItem?
    private var wasPlayingBeforeScrub = false
    private var activeSeekInteractionID: PlaybackDiagnostics.InteractionID?
    private var activeVolumeInteractionID: PlaybackDiagnostics.InteractionID?
    private var awaitingSeekTimeChange = false
    private var pendingReportedSeekPosition: Float?
    private var volumeFeedbackState = VolumeFeedbackState()
    private var requestedMuted = false
    private var lastVisibleVideoOutput = false
    private var isTemporarilyMutedForPause = false

    override init() {
        let videoView = VLCVideoView(frame: .zero)
        videoView.translatesAutoresizingMaskIntoConstraints = true
        videoView.autoresizingMask = [.width, .height]
        videoView.fillScreen = false
        videoView.backColor = .black

        self.videoView = videoView
        self.renderView = videoView
        self.mediaPlayer = VLCMediaPlayer()

        super.init()

        mediaPlayer.delegate = self
        mediaPlayer.setVideoView(videoView)
        mediaPlayer.scaleFactor = 0
        mediaPlayer.audio?.volume = 100
        mediaPlayer.videoAspectRatio = nil
        mediaPlayer.videoCropGeometry = nil
        mediaPlayer.audio?.isMuted = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioVolumeChanged(_:)),
            name: NSNotification.Name(rawValue: VLCMediaPlayerVolumeChanged),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadMedia(from url: URL) {
        let media = VLCMedia(url: url)
        media.synchronousParse()
        videoPresentationSizeDidChange?(Self.presentationSize(from: media.tracksInformation))
        mediaPlayer.media = media
        awaitingSeekTimeChange = false
        pendingReportedSeekPosition = nil
        volumeFeedbackState.clear()
        lastVisibleVideoOutput = false
        videoOutputVisibilityDidChange?(false)
        publishPlaybackMetrics()
        playbackStateDidChange?(.idle)
    }

    func primeForPausedStart() {
        guard mediaPlayer.media != nil else {
            return
        }

        mediaPlayer.audio?.isMuted = requestedMuted
        PlaybackDiagnostics.log("[prime] ready-paused t=\(PlaybackDiagnostics.timestampString())")
        publishPlaybackMetrics()
        playbackStateDidChange?(.paused)
    }

    func play() {
        PlaybackDiagnostics.log("[play] request t=\(PlaybackDiagnostics.timestampString())")
        isTemporarilyMutedForPause = false
        mediaPlayer.audio?.isMuted = requestedMuted
        playbackStateDidChange?(.opening)
        publishPlaybackMetrics()
        mediaPlayer.play()
    }

    func pause() {
        PlaybackDiagnostics.log("[pause] request t=\(PlaybackDiagnostics.timestampString())")
        isTemporarilyMutedForPause = true
        mediaPlayer.audio?.isMuted = true
        playbackStateDidChange?(.paused)
        publishPlaybackMetrics()
        mediaPlayer.pause()
    }

    func setMuted(_ muted: Bool) {
        requestedMuted = muted
        mediaPlayer.audio?.isMuted = muted
        PlaybackDiagnostics.log("[mute] apply muted=\(muted) actual=\(mediaPlayer.audio?.isMuted ?? false) t=\(PlaybackDiagnostics.timestampString())")
        publishPlaybackMetrics()
    }

    func setVolume(_ volume: Int, interactionID: PlaybackDiagnostics.InteractionID?) {
        let clampedVolume = max(0, min(200, volume))
        activeVolumeInteractionID = interactionID
        volumeFeedbackState.registerRequestedVolume(clampedVolume)
        mediaPlayer.audio?.volume = Int32(clampedVolume)
        let actualVolume = Int(mediaPlayer.audio?.volume ?? 0)
        PlaybackDiagnostics.log("[volume] apply id=\(interactionID ?? 0) target=\(clampedVolume) actual=\(actualVolume) t=\(PlaybackDiagnostics.timestampString())")
        publishPlaybackMetrics()
    }

    func beginScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) {
        activeSeekInteractionID = interactionID
        PlaybackDiagnostics.log("[seek] begin id=\(interactionID ?? 0) state=\(mediaPlayer.state.rawValue) t=\(PlaybackDiagnostics.timestampString())")
        guard !wasPlayingBeforeScrub else {
            return
        }

        switch mediaPlayer.state {
        case .playing, .opening, .buffering:
            wasPlayingBeforeScrub = true
            mediaPlayer.pause()
        default:
            wasPlayingBeforeScrub = false
        }
    }

    func endScrubbing(interactionID: PlaybackDiagnostics.InteractionID?) {
        if let interactionID {
            activeSeekInteractionID = interactionID
        }
        PlaybackDiagnostics.log("[seek] end id=\(activeSeekInteractionID ?? 0) t=\(PlaybackDiagnostics.timestampString())")
        pendingSeekWorkItem?.perform()
        pendingSeekWorkItem = nil
        pendingSeekPosition = nil

        if wasPlayingBeforeScrub {
            wasPlayingBeforeScrub = false
            mediaPlayer.play()
        }

        publishPlaybackMetrics()
    }

    func seek(to position: Float, isFinal: Bool, interactionID: PlaybackDiagnostics.InteractionID?) {
        guard mediaPlayer.isSeekable else {
            PlaybackDiagnostics.log("[seek] ignored-not-seekable id=\(interactionID ?? 0) t=\(PlaybackDiagnostics.timestampString())")
            return
        }

        if let interactionID {
            activeSeekInteractionID = interactionID
        }
        let clampedPosition = max(0, min(1, position))
        PlaybackDiagnostics.log("[seek] request id=\(activeSeekInteractionID ?? 0) position=\(String(format: "%.4f", clampedPosition)) final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())")

        if isFinal {
            pendingSeekWorkItem?.cancel()
            pendingSeekWorkItem = nil
            pendingSeekPosition = nil
            pendingReportedSeekPosition = clampedPosition
            mediaPlayer.position = clampedPosition
            awaitingSeekTimeChange = true
            PlaybackDiagnostics.log("[seek] apply-final id=\(activeSeekInteractionID ?? 0) position=\(String(format: "%.4f", clampedPosition)) t=\(PlaybackDiagnostics.timestampString())")
            publishPlaybackMetrics()
            return
        }

        pendingSeekPosition = clampedPosition
        pendingSeekWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let pendingSeekPosition = self.pendingSeekPosition else {
                    return
                }

                self.pendingReportedSeekPosition = pendingSeekPosition
                self.mediaPlayer.position = pendingSeekPosition
                self.awaitingSeekTimeChange = true
                PlaybackDiagnostics.log("[seek] apply-coalesced id=\(self.activeSeekInteractionID ?? 0) position=\(String(format: "%.4f", pendingSeekPosition)) t=\(PlaybackDiagnostics.timestampString())")
                self.pendingSeekPosition = nil
                self.pendingSeekWorkItem = nil
                self.publishPlaybackMetrics()
            }
        }

        pendingSeekWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.seekCoalescingInterval, execute: workItem)
    }

    func refreshVideoLayout() {
        videoView.frame = renderView.superview?.bounds ?? renderView.frame
        videoView.needsLayout = true
        videoView.layoutSubtreeIfNeeded()
    }

    func togglePlayback() {
        switch mediaPlayer.state {
        case .playing, .buffering, .opening:
            pause()
        case .ended:
            mediaPlayer.position = 0
            play()
        default:
            play()
        }
    }

    func stop() {
        pendingSeekWorkItem?.cancel()
        pendingSeekWorkItem = nil
        pendingSeekPosition = nil
        wasPlayingBeforeScrub = false
        activeSeekInteractionID = nil
        activeVolumeInteractionID = nil
        awaitingSeekTimeChange = false
        pendingReportedSeekPosition = nil
        volumeFeedbackState.clear()
        lastVisibleVideoOutput = false
        isTemporarilyMutedForPause = true
        mediaPlayer.audio?.isMuted = true
        mediaPlayer.stop()
        mediaPlayer.media = nil
        videoPresentationSizeDidChange?(nil)
        videoOutputVisibilityDidChange?(false)
        publishPlaybackMetrics()
        playbackStateDidChange?(.stopped)
    }

    private func publishPlaybackMetrics() {
        let isVisibleVideoOutput = hasVisibleVideoOutput
        if isVisibleVideoOutput != lastVisibleVideoOutput {
            lastVisibleVideoOutput = isVisibleVideoOutput
            videoOutputVisibilityDidChange?(isVisibleVideoOutput)
        }

        let elapsedTime = mediaPlayer.time
        let remainingTime = mediaPlayer.remainingTime
        let elapsedText = elapsedTime.value == nil ? "0:00" : elapsedTime.stringValue
        let remainingText = remainingTime?.value == nil ? "--:--" : (remainingTime?.stringValue ?? "--:--")
        let effectivePosition = pendingReportedSeekPosition ?? mediaPlayer.position
        let actualVolume = Int(mediaPlayer.audio?.volume ?? 100)
        let effectiveVolume = volumeFeedbackState.effectiveVolume(actualVolume: actualVolume)
        let metrics = MediaPreviewPlaybackMetrics(
            position: max(0, min(1, effectivePosition)),
            isSeekable: mediaPlayer.isSeekable,
            elapsedText: elapsedText,
            remainingText: remainingText,
            volume: effectiveVolume
        )
        if let activeVolumeInteractionID {
            PlaybackDiagnostics.log("[volume] metrics id=\(activeVolumeInteractionID) confirmed=\(metrics.volume) t=\(PlaybackDiagnostics.timestampString())")
            self.activeVolumeInteractionID = nil
        }
        playbackMetricsDidChange?(metrics)
    }

    private static func presentationSize(from tracksInformation: [Any]) -> CGSize? {
        for case let track as [AnyHashable: Any] in tracksInformation {
            guard let trackType = (track["type"] ?? track[VLCMediaTracksInformationType as NSString]) as? String,
                  trackType == VLCMediaTracksInformationTypeVideo || trackType == "video" else {
                continue
            }

            guard let width = numberValue(track["width"] ?? track[VLCMediaTracksInformationVideoWidth as NSString]),
                  let height = numberValue(track["height"] ?? track[VLCMediaTracksInformationVideoHeight as NSString]),
                  width > 0,
                  height > 0 else {
                continue
            }

            let sarNumerator = max(numberValue(track["sar_num"] ?? track[VLCMediaTracksInformationSourceAspectRatio as NSString]) ?? 1, 1)
            let sarDenominator = max(numberValue(track["sar_den"] ?? track[VLCMediaTracksInformationSourceAspectRatioDenominator as NSString]) ?? 1, 1)
            return CGSize(width: width * sarNumerator / sarDenominator, height: height)
        }

        return nil
    }

    private static func numberValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return nil
    }

    @objc
    private func handleAudioVolumeChanged(_ notification: Notification) {
        guard let audioObject = mediaPlayer.audio,
              let changedObject = notification.object as AnyObject?,
              changedObject === audioObject else {
            return
        }

        PlaybackDiagnostics.log("[volume] vlc-notification actual=\(Int(audioObject.volume)) t=\(PlaybackDiagnostics.timestampString())")
    }

    var hasVisibleVideoOutput: Bool {
        mediaPlayer.hasVideoOut || videoView.hasVideo
    }

    func saveSnapshot(to url: URL, width: Int = 0, height: Int = 0) {
        mediaPlayer.saveVideoSnapshot(at: url.path, withWidth: Int32(width), andHeight: Int32(height))
    }
}

extension VLCKitMediaPreviewPlayer: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleMediaPlayerStateChanged()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            if let self, self.awaitingSeekTimeChange {
                PlaybackDiagnostics.log("[seek] time-changed id=\(self.activeSeekInteractionID ?? 0) position=\(String(format: "%.4f", self.mediaPlayer.position)) time=\(self.mediaPlayer.time.stringValue) t=\(PlaybackDiagnostics.timestampString())")
                self.awaitingSeekTimeChange = false
                self.pendingReportedSeekPosition = nil
            }
            self?.publishPlaybackMetrics()
        }
    }

    private func handleMediaPlayerStateChanged() {
        let mappedState: MediaPreviewPlaybackState

        switch mediaPlayer.state {
        case .opening:
            mappedState = .opening
        case .buffering:
            mappedState = .buffering
        case .playing:
            if isTemporarilyMutedForPause {
                isTemporarilyMutedForPause = false
                mediaPlayer.audio?.isMuted = requestedMuted
            }
            mappedState = .playing
        case .paused:
            mappedState = .paused
        case .stopped:
            mappedState = .stopped
        case .ended:
            mappedState = .ended
        case .error:
            mappedState = .failed("VLCKit reported a playback error. This is usually a codec or container issue.")
        case .esAdded:
            mappedState = .opening
        @unknown default:
            mappedState = .failed("VLCKit entered an unknown playback state.")
        }

        publishPlaybackMetrics()
        PlaybackDiagnostics.log("[state] state=\(mediaPlayer.state.rawValue) mapped=\(String(describing: mappedState)) id=\(activeSeekInteractionID ?? 0) t=\(PlaybackDiagnostics.timestampString())")
        playbackStateDidChange?(mappedState)
    }
}

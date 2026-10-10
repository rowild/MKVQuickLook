import Foundation

// Connects a PreviewContentView and a MediaPreviewPlayer in both directions. The Quick
// Look extension and the Renderer Lab use this same wiring, so the lab exercises the
// exact path the extension ships.
@MainActor
enum PreviewPlayerBinding {
    /// Sends the view's controls to whatever player `currentPlayer` returns at the time
    /// of the interaction. The extension replaces its player for every previewed file.
    /// `logContext` names the host in diagnostics, e.g. "controller" or "lab".
    static func routeControls(
        of view: PreviewContentView,
        to currentPlayer: @escaping @MainActor () -> MediaPreviewPlayer?,
        logContext: String
    ) {
        view.playbackToggleHandler = {
            guard let player = currentPlayer() else {
                return
            }

            MediaPreviewPlayerSession.activate(player)
            player.togglePlayback()
        }
        view.seekTrackingHandler = { isTracking, interactionID in
            if isTracking {
                PlaybackDiagnostics.log("[seek] \(logContext)-begin id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                currentPlayer()?.beginScrubbing(interactionID: interactionID)
            } else {
                PlaybackDiagnostics.log("[seek] \(logContext)-end id=\(interactionID) t=\(PlaybackDiagnostics.timestampString())")
                currentPlayer()?.endScrubbing(interactionID: interactionID)
            }
        }
        view.seekHandler = { position, isFinal, interactionID in
            PlaybackDiagnostics.log("[seek] \(logContext)-change id=\(interactionID ?? 0) position=\(String(format: "%.4f", position)) final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())")
            currentPlayer()?.seek(to: position, isFinal: isFinal, interactionID: interactionID)
        }
        view.volumeHandler = { volume, interactionID in
            PlaybackDiagnostics.log("[volume] \(logContext)-change id=\(interactionID) target=\(volume) t=\(PlaybackDiagnostics.timestampString())")
            currentPlayer()?.setVolume(volume, interactionID: interactionID)
        }
    }

    /// Sends the player's state, metrics, video size, video visibility and media kind
    /// to the view.
    static func forwardUpdates(from player: MediaPreviewPlayer, to view: PreviewContentView) {
        player.playbackStateDidChange = { [weak view] state in
            view?.updatePlaybackState(state)
        }
        player.playbackMetricsDidChange = { [weak view] metrics in
            view?.updatePlaybackMetrics(metrics)
        }
        player.videoPresentationSizeDidChange = { [weak view] size in
            view?.updateVideoPresentationSize(size)
        }
        player.videoOutputVisibilityDidChange = { [weak view] isVisible in
            view?.setVideoOutputVisible(isVisible)
        }
        player.mediaKindDidChange = { [weak view] mediaKind in
            view?.setMediaKind(mediaKind)
        }
    }
}

import Foundation

@MainActor
enum MediaPreviewPlayerSession {
    private static weak var activePlayer: (any MediaPreviewPlayer)?

    static func replace(current: MediaPreviewPlayer?, with next: MediaPreviewPlayer?) -> MediaPreviewPlayer? {
        PlaybackDiagnostics.log("[session] replace current=\(diagnosticName(current)) next=\(diagnosticName(next)) active=\(diagnosticName(activePlayer))")
        if !isSameInstance(current, next), let current {
            current.stop()
        }
        if isSameInstance(activePlayer, current) {
            activePlayer = nil
        }
        return next
    }

    static func stopActivePreview() {
        PlaybackDiagnostics.log("[session] stop-active active=\(diagnosticName(activePlayer))")
        activePlayer?.stop()
        activePlayer = nil
    }

    static func activate(_ player: MediaPreviewPlayer) {
        PlaybackDiagnostics.log("[session] activate player=\(diagnosticName(player)) previous=\(diagnosticName(activePlayer))")
        if !isSameInstance(activePlayer, player) {
            activePlayer?.stop()
            activePlayer = player
        }
    }

    /// The host closed a preview of `file`. When Quick Look moves on to an item it
    /// shows with another previewer (for example an AVI), it keeps our hidden preview
    /// of the previous file playing and tells us nothing; Finder does close its column
    /// preview of that file at the same moment. So a closed preview of the playing file
    /// stops the playing preview. The playing preview closing itself is left to its
    /// own controller.
    static func previewDidClose(file: URL?, closingPlayer: MediaPreviewPlayer?) {
        guard let file,
              let activePlayer,
              !isSameInstance(activePlayer, closingPlayer),
              let playingFile = activePlayer.loadedFileURL,
              isSameFile(playingFile, file) else {
            return
        }

        PlaybackDiagnostics.log("[session] stop-on-close active=\(diagnosticName(activePlayer)) file=\(file.lastPathComponent)")
        activePlayer.stop()
        self.activePlayer = nil
    }

    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func deactivate(_ player: MediaPreviewPlayer?) {
        if isSameInstance(activePlayer, player) {
            activePlayer = nil
        }
    }

    // Short, stable name for a player in the unified log.
    static func diagnosticName(_ player: MediaPreviewPlayer?) -> String {
        player.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue), radix: 16) } ?? "nil"
    }

    private static func isSameInstance(_ lhs: MediaPreviewPlayer?, _ rhs: MediaPreviewPlayer?) -> Bool {
        guard let lhs, let rhs else {
            return lhs == nil && rhs == nil
        }

        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

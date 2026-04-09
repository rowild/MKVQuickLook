import Foundation

@MainActor
enum MediaPreviewPlayerSession {
    private static weak var activePlayer: (any MediaPreviewPlayer)?

    static func replace(current: MediaPreviewPlayer?, with next: MediaPreviewPlayer?) -> MediaPreviewPlayer? {
        if !isSameInstance(current, next), let current {
            current.stop()
        }
        if isSameInstance(activePlayer, current) {
            activePlayer = nil
        }
        return next
    }

    static func stopActivePreview() {
        activePlayer?.stop()
        activePlayer = nil
    }

    static func activate(_ player: MediaPreviewPlayer) {
        if !isSameInstance(activePlayer, player) {
            activePlayer?.stop()
            activePlayer = player
        }
    }

    static func deactivate(_ player: MediaPreviewPlayer?) {
        if isSameInstance(activePlayer, player) {
            activePlayer = nil
        }
    }

    private static func isSameInstance(_ lhs: MediaPreviewPlayer?, _ rhs: MediaPreviewPlayer?) -> Bool {
        guard let lhs, let rhs else {
            return lhs == nil && rhs == nil
        }

        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

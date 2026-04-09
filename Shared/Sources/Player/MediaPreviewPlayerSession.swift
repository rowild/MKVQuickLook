import Foundation

@MainActor
enum MediaPreviewPlayerSession {
    static func replace(current: MediaPreviewPlayer?, with next: MediaPreviewPlayer?) -> MediaPreviewPlayer? {
        if let current, current !== next {
            current.stop()
        }
        return next
    }
}

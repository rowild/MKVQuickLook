import Foundation
import OSLog

enum PlaybackDiagnostics {
    typealias InteractionID = UInt64

    private static let logger = Logger(subsystem: "com.robertwildling.MKVQuickLook", category: "Playback")
    @MainActor private static var nextInteractionID: InteractionID = 1

    @MainActor
    static func makeInteractionID(kind: StaticString) -> InteractionID {
        let id = nextInteractionID
        nextInteractionID += 1
        logger.debug("[\(kind)] created id=\(id, privacy: .public) t=\(timestampString(), privacy: .public)")
        return id
    }

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func timestampString() -> String {
        String(format: "%.3f", ProcessInfo.processInfo.systemUptime * 1000)
    }
}

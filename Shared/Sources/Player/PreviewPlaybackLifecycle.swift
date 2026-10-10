import Foundation

// Decides when the Quick Look controller loads, starts and stops playback.
//
// Finder can lay a preview out again after it closed it (viewDidDisappear), for
// example in Gallery view. A closed preview must stay stopped until the host
// prepares it with a file again or shows it again (viewWillAppear); otherwise it
// restarts out of sight, with sound.
struct PreviewPlaybackLifecycle: Equatable {
    enum Action: Equatable {
        case none
        case loadAndPlay
        case stop
    }

    private(set) var isMediaLoaded = false
    private(set) var isClosed = false

    mutating func prepare() {
        isMediaLoaded = false
        isClosed = false
    }

    mutating func willAppear() {
        isClosed = false
    }

    mutating func didDisappear() -> Action {
        isClosed = true
        isMediaLoaded = false
        return .stop
    }

    mutating func layout(mode: PreviewPresentationMode, hasFile: Bool) -> Action {
        switch mode {
        case .compact:
            guard isMediaLoaded else { return .none }
            isMediaLoaded = false
            return .stop
        case .expanded:
            guard hasFile, !isMediaLoaded, !isClosed else { return .none }
            isMediaLoaded = true
            return .loadAndPlay
        }
    }
}

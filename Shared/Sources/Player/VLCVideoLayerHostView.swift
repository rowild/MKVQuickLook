import AppKit
import QuartzCore
import VLCKit

@MainActor
final class VLCVideoLayerHostView: NSView {
    let videoLayer = VLCVideoLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds.integral
        CATransaction.commit()
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
        wantsLayer = true

        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.clear.cgColor
        layer = rootLayer

        videoLayer.backgroundColor = NSColor.clear.cgColor
        videoLayer.fillScreen = false
        rootLayer.addSublayer(videoLayer)
    }
}

import AppKit

enum PreviewPresentationMode {
    case compact
    case expanded
}

// MARK: - TrackingSlider

private final class TrackingSlider: NSSlider {
    var trackingStateDidChange: ((Bool) -> Void)?
    private(set) var isTrackingInteraction = false

    // Custom mouseDown replaces AppKit's default page-step behavior with an
    // immediate jump to the click position. beginScrubbing (trackingStateDidChange
    // true) is deferred until the first actual drag event — so a simple click never
    // triggers a pause/resume cycle in the player.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        // Immediately move knob to click position for visual feedback (no action yet).
        setValueFromMouseLocation(event)

        var didDrag = false

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { [weak self] evt, stop in
            guard let self, let evt else { stop.pointee = true; return }
            switch evt.type {
            case .leftMouseDragged:
                if !didDrag {
                    didDrag = true
                    self.isTrackingInteraction = true
                    self.trackingStateDidChange?(true)
                }
                self.setValueFromMouseLocation(evt, fireAction: true)
            case .leftMouseUp:
                stop.pointee = true
            default:
                break
            }
        }

        if didDrag {
            isTrackingInteraction = false
            trackingStateDidChange?(false)
        } else {
            // Plain click with no drag: fire action once as a final change.
            sendControlAction()
        }
    }

    private func setValueFromMouseLocation(_ event: NSEvent, fireAction: Bool = false) {
        guard let sliderCell = cell as? NSSliderCell else { return }
        let location = convert(event.locationInWindow, from: nil)
        let barRect = sliderCell.barRect(flipped: isFlipped)
        guard barRect.width > 0 else { return }
        let fraction = min(max((location.x - barRect.minX) / barRect.width, 0), 1)
        doubleValue = minValue + fraction * (maxValue - minValue)
        if fireAction { sendControlAction() }
    }

    private func sendControlAction() {
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }
}

// MARK: - PlayPauseOverlayView

private final class PlayPauseOverlayView: NSView {
    var clickHandler: (() -> Void)?

    private let iconCircle = NSView()
    private let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView() {
        wantsLayer = true

        iconCircle.wantsLayer = true
        iconCircle.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.52).cgColor
        iconCircle.layer?.cornerRadius = 32
        iconCircle.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        iconView.contentTintColor = .white
        iconView.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconCircle)
        iconCircle.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconCircle.widthAnchor.constraint(equalToConstant: 64),
            iconCircle.heightAnchor.constraint(equalToConstant: 64),
            iconView.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),
        ])
    }

    func setIcon(isPlaying: Bool) {
        let name = isPlaying ? "pause.fill" : "play.fill"
        let description = isPlaying ? "Pause" : "Play"
        iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }

    // Only intercept hits when visible so clicks pass through when overlay is faded out.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.05 else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
}

// MARK: - PreviewContentView

final class PreviewContentView: NSView {
    var playbackToggleHandler: (() -> Void)?
    var seekTrackingHandler: ((Bool, PlaybackDiagnostics.InteractionID) -> Void)?
    var seekHandler: ((Float, Bool, PlaybackDiagnostics.InteractionID?) -> Void)?
    var volumeHandler: ((Int, PlaybackDiagnostics.InteractionID) -> Void)?

    private let stackView = NSStackView()
    private let headerStack = NSStackView()
    private let textStack = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Loading Preview")
    private let subtitleLabel = NSTextField(labelWithString: "Preparing file information...")
    private let compactHintLabel = NSTextField(wrappingLabelWithString: "Column preview stays paused. Press Space for the full Quick Look player.")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let bufferingNoteLabel = NSTextField(wrappingLabelWithString: "Note: seek and volume changes may have a short delay. This is caused by VLCKit's audio/video pipeline buffering and cannot be avoided without introducing playback glitches.")
    private let videoFrameView = NSView()
    private let videoCanvasView = NSView()
    private let placeholderLabel = NSTextField(labelWithString: "Preparing video surface...")
    private let playbackButton = NSButton(title: "Play", target: nil, action: nil)
    private let elapsedTimeLabel = NSTextField(labelWithString: "0:00")
    private let remainingTimeLabel = NSTextField(labelWithString: "--:--")
    private let seekSlider = TrackingSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeSlider = TrackingSlider(value: 100, minValue: 0, maxValue: 200, target: nil, action: nil)
    private let volumeLabel = NSTextField(labelWithString: "Volume")
    private let controlsRow = NSStackView()
    private let badgeLabel = NSTextField(labelWithString: "MKVQuickLook / VLCKit")
    private let playPauseOverlay = PlayPauseOverlayView()
    private var attachedRenderView: NSView?
    private var isUpdatingSeekSlider = false
    private var videoMinimumHeightConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var videoPresentationSize = CGSize(width: 16, height: 9)
    private var currentSeekInteractionID: PlaybackDiagnostics.InteractionID?
    private var currentVolumeInteractionID: PlaybackDiagnostics.InteractionID?
    private var currentPlaybackState: MediaPreviewPlaybackState = .idle
    private var isVideoOutputVisible = false
    private var mediaKind: PreviewMediaKind = .video

    // MARK: Testing accessors

    var isPlaceholderVisibleForTesting: Bool {
        !placeholderLabel.isHidden
    }

    var placeholderTextForTesting: String {
        placeholderLabel.stringValue
    }

    var isPlaybackButtonEnabledForTesting: Bool {
        playbackButton.isEnabled
    }

    var isVideoFrameHiddenForTesting: Bool {
        videoFrameView.isHidden
    }

    var isControlsRowHiddenForTesting: Bool {
        controlsRow.isHidden
    }

    var volumeSliderValueForTesting: Double {
        volumeSlider.doubleValue
    }

    func setVolumeSliderValueForTesting(_ value: Double) {
        volumeSlider.doubleValue = value
    }

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        layoutVideoCanvas()
        attachedRenderView?.frame = videoCanvasView.bounds
    }

    // MARK: Mouse tracking (hover overlay)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Tracking area is set up once in configureView using .inVisibleRect,
        // which handles automatic bounds updates — no manual refresh needed here.
    }

    override func mouseEntered(with event: NSEvent) {
        guard !videoFrameView.isHidden else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            playPauseOverlay.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            playPauseOverlay.animator().alphaValue = 0
        }
    }

    // MARK: Public API

    func apply(metadata: PreviewMetadata) {
        setMediaKind(metadata.mediaKind)
        iconView.image = metadata.icon
        titleLabel.stringValue = metadata.displayName
        subtitleLabel.stringValue = "\(metadata.typeDescription) • .\(metadata.fileExtension)"
        compactHintLabel.stringValue = metadata.mediaKind == .audioOnly
            ? "Column preview stays paused. Press Space for the full Quick Look audio preview."
            : "Column preview stays paused. Press Space for the full Quick Look player."
        detailsLabel.stringValue = """
        Path: \(metadata.fileURL.path)
        Size: \(metadata.fileSizeDescription)
        Modified: \(metadata.modifiedDateDescription)
        """
        statusLabel.stringValue = metadata.mediaKind == .audioOnly
            ? "Opening audio with VLCKit..."
            : "Opening with VLCKit..."
        playbackButton.isEnabled = true
        seekSlider.isEnabled = false
        volumeSlider.isEnabled = true
        volumeSlider.doubleValue = 100
    }

    func setMediaKind(_ mediaKind: PreviewMediaKind) {
        self.mediaKind = mediaKind
        refreshLayoutForCurrentMode()
        refreshPlaceholderVisibility()
    }

    func applyPlaceholder(title: String, subtitle: String, details: String, status: String, symbolName: String = "play.rectangle") {
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        compactHintLabel.stringValue = "Load a file in the app to validate the renderer without Finder."
        detailsLabel.stringValue = details
        statusLabel.stringValue = status
        playbackButton.isEnabled = false
        seekSlider.isEnabled = false
        volumeSlider.isEnabled = false
        volumeSlider.doubleValue = 100
        placeholderLabel.isHidden = false
        placeholderLabel.stringValue = "Choose a file to start the renderer lab."
    }

    func apply(error: String) {
        iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        titleLabel.stringValue = "Preview Failed"
        subtitleLabel.stringValue = "The extension could not prepare this file."
        detailsLabel.stringValue = error
        statusLabel.stringValue = "Check the app's troubleshooting notes, then retry Finder Quick Look."
        playbackButton.isEnabled = false
        seekSlider.isEnabled = false
        volumeSlider.isEnabled = false
        volumeSlider.doubleValue = 100
        placeholderLabel.isHidden = false
        placeholderLabel.stringValue = "Playback failed"
    }

    func attachRenderView(_ renderView: NSView) {
        if attachedRenderView === renderView {
            return
        }

        attachedRenderView?.removeFromSuperview()
        attachedRenderView = renderView
        renderView.translatesAutoresizingMaskIntoConstraints = true
        renderView.autoresizingMask = [.width, .height]
        renderView.frame = videoCanvasView.bounds
        videoCanvasView.addSubview(renderView)
        needsLayout = true
    }

    func updateVideoPresentationSize(_ size: CGSize?) {
        guard let size,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            videoPresentationSize = CGSize(width: 16, height: 9)
            needsLayout = true
            return
        }

        videoPresentationSize = size
        needsLayout = true
    }

    func setPresentationMode(_ mode: PreviewPresentationMode) {
        switch mode {
        case .compact:
            videoFrameView.isHidden = true
            playbackButton.isHidden = true
            controlsRow.isHidden = true
            compactHintLabel.isHidden = false
            detailsLabel.isHidden = true
            statusLabel.isHidden = true
            bufferingNoteLabel.isHidden = true
            badgeLabel.isHidden = true
            placeholderLabel.isHidden = true
            titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            titleLabel.maximumNumberOfLines = 2
            subtitleLabel.maximumNumberOfLines = 1
            headerStack.spacing = 10
            stackView.spacing = 10
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            videoMinimumHeightConstraint?.constant = 0
            stackLeadingConstraint?.constant = 12
            stackTrailingConstraint?.constant = -12
            stackTopConstraint?.constant = 12
            stackBottomConstraint?.constant = -12
        case .expanded:
            videoFrameView.isHidden = false
            controlsRow.isHidden = false
            compactHintLabel.isHidden = true
            detailsLabel.isHidden = false
            statusLabel.isHidden = false
            bufferingNoteLabel.isHidden = false
            badgeLabel.isHidden = false
            placeholderLabel.isHidden = false
            placeholderLabel.stringValue = "Preparing video surface..."
            titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
            subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
            titleLabel.maximumNumberOfLines = 0
            subtitleLabel.maximumNumberOfLines = 0
            headerStack.spacing = 12
            stackView.spacing = 14
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
            videoMinimumHeightConstraint?.constant = 320
            stackLeadingConstraint?.constant = 32
            stackTrailingConstraint?.constant = -32
            stackTopConstraint?.constant = 24
            stackBottomConstraint?.constant = -24
        }

        refreshLayoutForCurrentMode()
    }

    func updatePlaybackMetrics(_ metrics: MediaPreviewPlaybackMetrics) {
        if !seekSlider.isTrackingInteraction {
            isUpdatingSeekSlider = true
            seekSlider.floatValue = metrics.position
            isUpdatingSeekSlider = false
        }
        seekSlider.isEnabled = metrics.isSeekable
        elapsedTimeLabel.stringValue = metrics.elapsedText
        remainingTimeLabel.stringValue = metrics.remainingText
    }

    func updatePlaybackState(_ state: MediaPreviewPlaybackState) {
        currentPlaybackState = state

        switch state {
        case .idle:
            statusLabel.stringValue = "Ready"
            playbackButton.title = "Play"
            playbackButton.isEnabled = true
            placeholderLabel.stringValue = "Ready to play"
        case .opening:
            statusLabel.stringValue = mediaKind == .audioOnly ? "Opening audio..." : "Opening media..."
            playbackButton.title = "Pause"
            playbackButton.isEnabled = true
            placeholderLabel.stringValue = "Preparing video surface..."
        case .buffering:
            statusLabel.stringValue = "Buffering..."
            playbackButton.title = "Pause"
            playbackButton.isEnabled = true
            placeholderLabel.stringValue = "Buffering..."
        case .playing:
            statusLabel.stringValue = mediaKind == .audioOnly
                ? "Playing original audio file directly through VLCKit."
                : "Playing original file directly through VLCKit."
            playbackButton.title = "Pause"
            playbackButton.isEnabled = true
        case .paused:
            statusLabel.stringValue = "Paused"
            placeholderLabel.stringValue = "Playback paused. Click Play to continue."
            playbackButton.title = "Play"
            playbackButton.isEnabled = true
        case .stopped:
            statusLabel.stringValue = "Stopped"
            placeholderLabel.stringValue = "Playback stopped"
            playbackButton.title = "Play"
            playbackButton.isEnabled = true
        case .ended:
            statusLabel.stringValue = "Playback ended"
            placeholderLabel.stringValue = "Playback finished"
            playbackButton.title = "Replay"
            playbackButton.isEnabled = true
        case .failed(let message):
            apply(error: message)
            return
        }

        let isActivePlaying: Bool
        switch state {
        case .playing, .opening, .buffering:
            isActivePlaying = true
        default:
            isActivePlaying = false
        }
        playPauseOverlay.setIcon(isPlaying: isActivePlaying)

        refreshPlaceholderVisibility()
    }

    func setVideoOutputVisible(_ isVisible: Bool) {
        isVideoOutputVisible = isVisible
        refreshPlaceholderVisibility()
    }

    // MARK: Private setup

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        videoFrameView.translatesAutoresizingMaskIntoConstraints = false
        videoFrameView.wantsLayer = true
        videoFrameView.layer?.backgroundColor = NSColor.black.cgColor
        videoFrameView.layer?.cornerRadius = 14
        videoFrameView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        videoFrameView.layer?.borderWidth = 1

        videoCanvasView.wantsLayer = true
        videoCanvasView.layer?.backgroundColor = NSColor.clear.cgColor

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 16, weight: .medium)
        placeholderLabel.textColor = .white.withAlphaComponent(0.9)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        badgeLabel.layer?.cornerRadius = 6
        badgeLabel.layer?.masksToBounds = true
        badgeLabel.lineBreakMode = .byClipping
        badgeLabel.cell?.wraps = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)

        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        compactHintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        compactHintLabel.textColor = .tertiaryLabelColor
        compactHintLabel.maximumNumberOfLines = 2

        detailsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.maximumNumberOfLines = 0

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.maximumNumberOfLines = 0

        bufferingNoteLabel.font = .systemFont(ofSize: 11, weight: .regular)
        bufferingNoteLabel.textColor = .tertiaryLabelColor
        bufferingNoteLabel.maximumNumberOfLines = 0

        playbackButton.translatesAutoresizingMaskIntoConstraints = false
        playbackButton.bezelStyle = .rounded
        playbackButton.target = self
        playbackButton.action = #selector(handlePlaybackToggle)
        playbackButton.isHidden = true  // Hidden by default; shown only for audio-only mode

        elapsedTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        remainingTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        remainingTimeLabel.textColor = .secondaryLabelColor

        seekSlider.target = self
        seekSlider.action = #selector(handleSeekChanged)
        seekSlider.controlSize = .small
        seekSlider.isContinuous = true
        seekSlider.isEnabled = false
        seekSlider.trackingStateDidChange = { [weak self] isTracking in
            guard let self else { return }

            if isTracking {
                let interactionID = PlaybackDiagnostics.makeInteractionID(kind: "seek")
                self.currentSeekInteractionID = interactionID
                PlaybackDiagnostics.log("[seek] ui-begin id=\(interactionID) position=\(String(format: "%.4f", self.seekSlider.floatValue)) t=\(PlaybackDiagnostics.timestampString())")
                self.seekTrackingHandler?(true, interactionID)
            } else if let interactionID = self.currentSeekInteractionID {
                PlaybackDiagnostics.log("[seek] ui-end id=\(interactionID) position=\(String(format: "%.4f", self.seekSlider.floatValue)) t=\(PlaybackDiagnostics.timestampString())")
                self.seekTrackingHandler?(false, interactionID)
            }

            guard !isTracking else { return }

            self.seekHandler?(self.seekSlider.floatValue, true, self.currentSeekInteractionID)
            self.currentSeekInteractionID = nil
        }

        volumeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        volumeLabel.textColor = .secondaryLabelColor

        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeChanged)
        volumeSlider.controlSize = .small
        volumeSlider.isContinuous = true
        volumeSlider.trackingStateDidChange = { [weak self] isTracking in
            guard let self else { return }

            if isTracking {
                let interactionID = PlaybackDiagnostics.makeInteractionID(kind: "volume")
                self.currentVolumeInteractionID = interactionID
                PlaybackDiagnostics.log("[volume] ui-begin id=\(interactionID) target=\(Int(self.volumeSlider.doubleValue.rounded())) t=\(PlaybackDiagnostics.timestampString())")
            } else if let interactionID = self.currentVolumeInteractionID {
                let finalVolume = Int(self.volumeSlider.doubleValue.rounded())
                PlaybackDiagnostics.log("[volume] ui-end id=\(interactionID) target=\(finalVolume) t=\(PlaybackDiagnostics.timestampString())")
                self.volumeHandler?(finalVolume, interactionID)
                self.currentVolumeInteractionID = nil
            }
        }

        // Play/pause overlay: transparent click target covering the video frame.
        // Visible only on hover; faded in/out via mouseEntered/mouseExited.
        playPauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        playPauseOverlay.alphaValue = 0
        playPauseOverlay.clickHandler = { [weak self] in
            self?.playbackToggleHandler?()
        }

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        headerStack.addArrangedSubview(iconView)
        headerStack.addArrangedSubview(textStack)
        headerStack.orientation = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 12

        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 10
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.addArrangedSubview(playbackButton)
        controlsRow.addArrangedSubview(elapsedTimeLabel)
        controlsRow.addArrangedSubview(seekSlider)
        controlsRow.addArrangedSubview(remainingTimeLabel)
        controlsRow.addArrangedSubview(volumeLabel)
        controlsRow.addArrangedSubview(volumeSlider)

        stackView.addArrangedSubview(videoFrameView)
        stackView.addArrangedSubview(controlsRow)
        stackView.addArrangedSubview(headerStack)
        stackView.addArrangedSubview(compactHintLabel)
        stackView.addArrangedSubview(detailsLabel)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(bufferingNoteLabel)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14

        videoFrameView.addSubview(videoCanvasView)
        videoFrameView.addSubview(placeholderLabel)
        videoFrameView.addSubview(badgeLabel)
        videoFrameView.addSubview(playPauseOverlay)
        addSubview(stackView)

        let stackLeadingConstraint = stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32)
        let stackTrailingConstraint = stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        let stackTopConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: 24)
        let stackBottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        let videoMinimumHeightConstraint = videoFrameView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)

        self.stackLeadingConstraint = stackLeadingConstraint
        self.stackTrailingConstraint = stackTrailingConstraint
        self.stackTopConstraint = stackTopConstraint
        self.stackBottomConstraint = stackBottomConstraint
        self.videoMinimumHeightConstraint = videoMinimumHeightConstraint

        NSLayoutConstraint.activate([
            stackLeadingConstraint,
            stackTrailingConstraint,
            stackTopConstraint,
            stackBottomConstraint,
            videoFrameView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            videoMinimumHeightConstraint,
            placeholderLabel.centerXAnchor.constraint(equalTo: videoFrameView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: videoFrameView.centerYAnchor),
            badgeLabel.topAnchor.constraint(equalTo: videoFrameView.topAnchor, constant: 12),
            badgeLabel.trailingAnchor.constraint(equalTo: videoFrameView.trailingAnchor, constant: -12),
            playPauseOverlay.topAnchor.constraint(equalTo: videoFrameView.topAnchor),
            playPauseOverlay.bottomAnchor.constraint(equalTo: videoFrameView.bottomAnchor),
            playPauseOverlay.leadingAnchor.constraint(equalTo: videoFrameView.leadingAnchor),
            playPauseOverlay.trailingAnchor.constraint(equalTo: videoFrameView.trailingAnchor),
            controlsRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            seekSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            volumeSlider.widthAnchor.constraint(equalToConstant: 120),
        ])

        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        elapsedTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        volumeLabel.setContentHuggingPriority(.required, for: .horizontal)

        // .inVisibleRect keeps the tracking rect in sync with videoFrameView bounds
        // automatically whenever the view is laid out. Owner = self so mouseEntered/
        // mouseExited are dispatched to PreviewContentView.
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        videoFrameView.addTrackingArea(trackingArea)
    }

    // MARK: Actions

    @objc
    private func handlePlaybackToggle() {
        playbackToggleHandler?()
    }

    @objc
    private func handleSeekChanged() {
        guard !isUpdatingSeekSlider else { return }

        let isFinal = !seekSlider.isTrackingInteraction
        PlaybackDiagnostics.log("[seek] ui-change id=\(currentSeekInteractionID ?? 0) position=\(String(format: "%.4f", seekSlider.floatValue)) final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())")
        seekHandler?(seekSlider.floatValue, isFinal, currentSeekInteractionID)
    }

    @objc
    private func handleVolumeChanged() {
        let interactionID = currentVolumeInteractionID ?? PlaybackDiagnostics.makeInteractionID(kind: "volume")
        let targetVolume = Int(volumeSlider.doubleValue.rounded())
        PlaybackDiagnostics.log("[volume] ui-change id=\(interactionID) target=\(targetVolume) t=\(PlaybackDiagnostics.timestampString())")
        volumeHandler?(targetVolume, interactionID)
    }

    // MARK: Private helpers

    private func layoutVideoCanvas() {
        let safeBounds = videoFrameView.bounds.insetBy(dx: 1, dy: 1)
        videoCanvasView.frame = VideoLayout.fittedRect(contentSize: videoPresentationSize, in: safeBounds).integral
    }

    private func refreshLayoutForCurrentMode() {
        let isExpanded = compactHintLabel.isHidden

        if isExpanded {
            let isAudioOnly = mediaKind == .audioOnly
            videoFrameView.isHidden = isAudioOnly
            badgeLabel.isHidden = isAudioOnly
            // Play button is only useful in audio-only mode; the overlay handles video.
            playbackButton.isHidden = !isAudioOnly
        }
    }

    private func refreshPlaceholderVisibility() {
        guard mediaKind == .video else {
            placeholderLabel.isHidden = true
            return
        }

        let shouldHidePlaceholder: Bool

        switch currentPlaybackState {
        case .playing:
            shouldHidePlaceholder = true
        case .opening, .buffering, .paused:
            shouldHidePlaceholder = isVideoOutputVisible
        case .idle, .stopped, .ended, .failed:
            shouldHidePlaceholder = false
        }

        placeholderLabel.isHidden = shouldHidePlaceholder
    }
}

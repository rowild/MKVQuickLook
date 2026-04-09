# Quick Look Preview Research

Date: 2026-04-09

Project: `MKVQuickLook`

Research focus:
1. How to properly center video inside a macOS Quick Look preview.
2. Whether a Quick Look Preview Extension can control Finder's small Column View preview size.
3. Which AppKit / Quick Look / VLCKit patterns are robust for macOS 14 and 15.

## Executive Summary

The most important result is this:

- A modern Quick Look Preview Extension does not control Finder's outer preview pane geometry.
- Finder controls the container size for Column View and the right-side Preview pane.
- The extension controls only the content inside that host rectangle.
- For `Space`-bar Quick Look, `preferredContentSize` can influence the larger panel, but it is not a reliable control surface for Finder's sidebar-like preview contexts.
- The left-offset / misaligned-video symptom is very plausibly a `VLCKit` macOS rendering problem, not a Quick Look layout problem.
- VideoLAN's own macOS issue history points to a long-standing layer-backed OpenGL resize problem around `VLCVideoView`.
- For this project, the most promising fix path is:
  - treat compact Finder preview as a separate compact layout
  - do not try to widen Finder's column preview from the extension
  - center the preview content in an AppKit wrapper that owns the layout
  - strongly consider `VLCVideoLayer` / layer-based rendering instead of `VLCVideoView` for the large preview path
  - avoid forcing `videoAspectRatio` unless there is a demonstrated file-specific need

## Short Answer To The Two Core Questions

### 1. Can the extension resize Finder's small Column View preview?

No, not in the modern `.appex` model.

Finder owns the preview pane width. Apple Support explicitly documents that the user changes Preview pane size by dragging Finder's divider line. That is host behavior, not extension behavior.

Practical implication:

- The extension should adapt to the compact bounds Finder gives it.
- It should not assume it can request a larger sidebar.
- In compact contexts, the correct strategy is a compact UI, not a larger host.

### 2. Can the video be centered correctly?

Yes, but only inside the content area given to the extension.

The right question is not "How do I center the Finder preview pane?"
The right question is:

- "How do I make the renderer fit and center inside my own wrapper view?"

For ordinary AppKit / AVFoundation playback, this is straightforward.
For `VLCKit` on macOS, there is a known complication: `VLCVideoView` historically had resize/layout issues in layer-backed environments. Quick Look preview hosts are exactly the kind of environment where this matters.

## Deep Findings

## A. What Apple says about modern Quick Look preview extensions

Apple's WWDC 2019 Quick Look session gives the clearest high-level architectural statement for modern macOS preview extensions:

- preview extensions on macOS let you provide a view directly
- the view controller template is where you prepare the preview
- the same preview may be shown in multiple host contexts
- those contexts include the Preview panel, Finder's Column View sidebar, Spotlight, and any client embedding `QLPreviewView`

That host list matters a lot. It means:

- the extension is not the window owner
- the extension is not the pane owner
- the extension is a content provider inside a host-chosen rectangle

Relevant Apple source:
- WWDC19, "What's New in File Management and Quick Look"
  - https://developer.apple.com/videos/play/wwdc2019/719/

Key practical implications for `MKVQuickLook`:

- compact and expanded previews must be designed as two different content modes
- the extension cannot assume it is only ever shown in the large `Space`-bar panel
- any live video renderer must survive being embedded into a narrow host

## B. Finder Preview pane size is host-controlled

Apple Support's Finder documentation explicitly says the Preview pane size is changed by dragging Finder's divider line.

Source:
- Apple Support, "Use the Preview pane in the Finder on Mac"
  - https://support.apple.com/en-md/guide/mac-help/mchl1e4644c2/mac

That is strong evidence that:

- Finder owns preview pane sizing
- pane width is a Finder UI concern
- a Quick Look extension cannot dictate that width

This matches the WWDC host-container model.

For this project, that means the extension should stop treating "column preview too small" as a sizing-API problem.
It is a responsive-layout problem.

## C. `preferredContentSize`: useful, but limited

There is a practical community finding around `QLPreviewingController`:

- setting `preferredContentSize` can influence Quick Look window sizing
- but it is not a general-purpose way to control all host contexts
- and older macOS behavior had quirks around autoresizing

Relevant practical sources:

- Stack Overflow: "Set QuickLook window size when previewing with QLPreviewingController.preparePreviewOfFile"
  - https://stackoverflow.com/questions/65633750/set-quicklook-window-size-when-previewing-with-qlpreviewingcontroller-preparepre
- Stack Overflow: "Setting preferredContentSize of QLPreviewingController breaks auto resizing"
  - https://stackoverflow.com/questions/66137642/setting-preferredcontentsize-of-qlpreviewingcontroller-breaks-auto-resizing

Interpretation:

- `preferredContentSize` is reasonable for the larger preview panel
- it should not be treated as a reliable control for Finder Column View
- it should not be the main mechanism used to solve a compact-preview problem

For macOS 14 and 15 specifically, `preferredContentSize` is still worth setting for the larger panel, but it does not solve the compact host problem shown in the screenshot.

## D. Old Quick Look generator sizing hints are legacy, not the right solution

Apple's archived Quick Look Programming Guide for old generators documents `QLPreviewWidth` and `QLPreviewHeight` as preview-size hints.

Source:
- Apple Documentation Archive, "Creating and Configuring a Quick Look Project"
  - https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/Quicklook_Programming_Guide/Articles/QLProjectConfig.html

Those keys belong to the old generator architecture, not the modern preview-extension architecture.

This is important because it rules out a common dead end:

- adding legacy preview-size hints will not fix a modern Finder `.appex` layout issue

## E. The compact host is not a bug; it is a real host mode

Apple explicitly says the preview can appear in:

- the Preview panel
- the Column View sidebar
- Spotlight
- any `QLPreviewView` client

So the narrow Finder presentation in the screenshot is not an edge case.
It is a first-class supported host context.

For this project, compact mode should be intentionally designed. The compact preview should likely do one of these:

1. show a still poster frame or thumbnail only
2. show a centered, letterboxed, non-interactive live frame
3. show only the essential metadata plus a poster image

Trying to squeeze the full large-preview layout into Column View is the wrong strategy.

## F. VLCKit macOS internals: why `VLCVideoView` is suspicious here

The most important practical discovery from VideoLAN's source and issue history is that `VLCVideoView` on macOS has historical resize/layout fragility in layer-backed environments.

### F1. What `VLCVideoView` actually does

The current `VLCKit` source shows:

- `VLCVideoView` is an `NSView`
- when a video output layer appears, it sets `self.wantsLayer = YES`
- it installs a custom `VLCVideoLayoutManager`
- it inserts the actual video output layer into the root layer

Source:
- `VLCVideoView.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoView.m

This means the macOS view-based path is not a simple "dumb NSView displaying pixels".
It becomes layer-backed internally and delegates sizing to a custom layer layout manager.

### F2. The layout manager is supposed to center the video

`VLCVideoCommon.m` shows the `VLCVideoLayoutManager` behavior:

- it calculates a fit/fill ratio from container bounds and original video size
- it computes a new `videoRect`
- it offsets `x` and `y` by half the remaining difference
- that is a centering algorithm

Source:
- `VLCVideoCommon.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoCommon.m

Paraphrased behavior:

```objective-c
xRatio = bounds.width / original.width
yRatio = bounds.height / original.height
ratio = fill ? max(xRatio, yRatio) : min(xRatio, yRatio)
videoRect.size = original * ratio
videoRect.origin.x += (bounds.width - videoRect.width) / 2
videoRect.origin.y += (bounds.height - videoRect.height) / 2
```

This is exactly what we want.

That means:

- if the image is still visibly shifted inside a black area, the problem is probably not "there is no centering logic"
- the more likely problem is "the underlying OpenGL/layer-backed view path is misbehaving after resize or host embedding"

### F3. VideoLAN documented a macOS resize bug around `fillScreen` and layer-backed views

VideoLAN issue `#82` is highly relevant:

- issue title: `[macOS] fillScreen not working after resizing player view`
- the discussion says the problem comes from `NSOpenGLView` resize behavior when layer-backed
- the stated workaround was to avoid a layer-backed view
- the stated future direction was a `CAOpenGLLayer`-based output
- the thread also explicitly recommends using the `CAOpenGLLayer` path

Source:
- VideoLAN issue `#82`
  - https://code.videolan.org/videolan/VLCKit/-/issues/82

This is extremely relevant for Quick Look because:

- Quick Look preview content is embedded into host-controlled views
- those hosts are very likely layer-backed
- Finder resizes and rehosts preview content frequently

In other words:

- `VLCVideoView` is entering exactly the kind of environment that VideoLAN called problematic

### F4. VideoLAN also documented misalignment when manually forcing `videoAspectRatio`

VideoLAN issue `#276` is also directly relevant:

- issue title: `set videoAspectRatio at cocoa incorrect`
- the reported symptom includes content alignment shifting unexpectedly
- the discussion links the problem to known AppKit/OpenGL issues
- the practical workaround discussed there is resizing the view to match the video rather than forcing aspect ratio blindly

Source:
- VideoLAN issue `#276`
  - https://code.videolan.org/videolan/VLCKit/-/issues/276

This strongly supports the decision to avoid manually setting `videoAspectRatio` unless absolutely necessary.

For this project, this finding is important:

- trying to "fix" alignment by manually forcing VLC aspect ratio may make the problem worse

### F5. `VLCVideoLayer` is the stronger macOS candidate

`VLCKit` also provides `VLCVideoLayer`, a CALayer-based renderer API.

Sources:
- `VLCVideoLayer.h`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Headers/VLCVideoLayer.h
- `VLCVideoLayer.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoLayer.m

The existence of `VLCVideoLayer`, combined with issue `#82`, suggests this:

- if `VLCVideoView` continues to misalign inside Quick Look hosts
- then the next serious implementation path should be a correct `VLCVideoLayer` integration

This is not proof that `VLCVideoLayer` automatically solves everything.
It is evidence that layer-based rendering is the path VideoLAN itself moved toward for this class of resize problem.

## G. What this means for the current `MKVQuickLook` bug

Based on the sources above, the current problem is most likely one of these:

1. `VLCVideoView` is misbehaving inside Finder's layer-backed embedded preview host.
2. A live renderer is being used in a compact host where a static poster would be more appropriate.
3. The layout is trying to reuse one composition for both compact and expanded contexts.
4. Repeated layout resets or renderer reattachment are interacting badly with `VLCVideoView`.

What is much less likely now:

- the MKV file itself being weird
- a missing "center this preview pane" Quick Look API
- Finder simply ignoring a valid extension-controlled width request

## Recommended Solution Paths

## Option 1: Keep `VLCKit`, but split compact and expanded behavior hard

This is the lowest-risk product change.

Compact mode:

- do not use live video playback
- render a still poster or first-frame thumbnail only
- center that poster inside a letterboxed wrapper
- keep metadata minimal

Expanded mode:

- use live playback
- use manual play only
- keep controls visible

Why this helps:

- it avoids trying to make a live OpenGL renderer behave nicely in a narrow Finder sidebar
- it respects the host model Apple describes
- it likely fixes the "only half visible in compact preview" problem even if `VLCVideoView` remains imperfect

## Option 2: Use `VLCVideoLayer` for expanded live playback

This is the strongest technical path if `VLCVideoView` remains unstable.

Why:

- VideoLAN's own issue history points toward layer-based rendering for resize correctness
- `VLCVideoLayer` fits better into an AppKit view hierarchy that already wants to own centering and sizing

This is the best candidate if the goal is:

- centered playback
- predictable resizing
- less dependence on `NSOpenGLView` behavior inside host-controlled views

## Option 3: Host a poster/thumbnail in compact mode and defer live video entirely to the large panel

This is probably the best UX for Finder.

Compact mode should answer:

- what file is this?
- what does it roughly look like?

The large panel should answer:

- play/pause
- seek
- volume
- detailed metadata

This matches Finder's actual affordances better than trying to cram a full player into Column View.

## Code Patterns That Make Sense

## 1. A centered wrapper view that owns the fit rectangle

Do not let the renderer own your outer layout.
Give it a wrapper view with a computed fit rect.

```swift
import AppKit

final class CenteredVideoHostView: NSView {
    private let contentWrapper = NSView()
    private var aspectConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        contentWrapper.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentWrapper)

        NSLayoutConstraint.activate([
            contentWrapper.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentWrapper.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentWrapper.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            contentWrapper.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAspectRatio(width: CGFloat, height: CGFloat) {
        aspectConstraint?.isActive = false
        aspectConstraint = contentWrapper.widthAnchor.constraint(equalTo: contentWrapper.heightAnchor,
                                                               multiplier: width / height)
        aspectConstraint?.priority = .required
        aspectConstraint?.isActive = true
    }

    func attachCenteredSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentWrapper.subviews.forEach { $0.removeFromSuperview() }
        contentWrapper.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentWrapper.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentWrapper.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentWrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentWrapper.bottomAnchor)
        ])
    }
}
```

Use this if:

- you know the video dimensions or aspect ratio
- you want the host view, not VLC, to decide the visible box

## 2. A compact-vs-expanded branch based on actual bounds

This should be an intentional layout choice, not an afterthought.

```swift
enum PreviewMode {
    case compact
    case expanded
}

func previewMode(for size: CGSize) -> PreviewMode {
    if size.width < 420 || size.height < 260 {
        return .compact
    }
    return .expanded
}
```

In compact mode:

```swift
switch previewMode(for: view.bounds.size) {
case .compact:
    showPosterOnly()
    hidePlaybackControls()
    stopLivePlaybackIfNeeded()

case .expanded:
    showLiveRenderer()
    showPlaybackControls()
}
```

## 3. AVFoundation example for proper centering

This example is not the recommended backend for MKV/WebM/Ogg coverage, but it shows the ideal centering behavior clearly.

```swift
import AVFoundation
import AppKit

final class PlayerLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func setPlayer(_ player: AVPlayer) {
        playerLayer.player = player
    }
}
```

The key property is `videoGravity = .resizeAspect`.
That is the behavior we want conceptually: centered, letterboxed fit.

## 4. `VLCKit` with `VLCVideoLayer`

This is the most interesting candidate for the current project.

Conceptually:

```swift
import AppKit
import QuartzCore
import VLCKit

final class VLCVideoLayerHostView: NSView {
    let videoLayer = VLCVideoLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor

        videoLayer.frame = bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.fillScreen = false
        layer?.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

Then:

```swift
let hostView = VLCVideoLayerHostView()
let player = VLCMediaPlayer()
player.setVideoLayer(hostView.videoLayer)
player.media = VLCMedia(url: fileURL)
```

Important note:

- this snippet is a recommended integration direction, not a copy-paste guarantee
- the exact sequence still needs to be validated in this project
- but architecturally it matches VideoLAN's documented direction better than relying on `VLCVideoView`

## 5. If keeping `VLCVideoView`, do less, not more

If `VLCVideoView` must stay for now:

- do not force `videoAspectRatio`
- do not repeatedly reattach the video view on every layout pass
- do not mix multiple geometry systems unless necessary
- keep it in a single, stable wrapper view
- prefer compact mode without live rendering

Pattern:

```swift
final class StableVLCVideoContainer: NSView {
    let videoView = VLCVideoView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        videoView.frame = bounds
        videoView.autoresizingMask = [.width, .height]
        videoView.fillScreen = false
        addSubview(videoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

This does not fix the known underlying VLCKit issue by itself.
It just avoids piling additional layout manipulation on top.

## 6. Compact mode should probably use a still image, not live video

For Finder Column View, a still image is likely the better design.

Example flow:

```swift
func configureCompactPreview(for fileURL: URL) {
    let image = generatePosterFrame(for: fileURL)
    posterImageView.image = image
    posterImageView.isHidden = false
    liveRendererView.isHidden = true
    controlsContainer.isHidden = true
}
```

This is the most Finder-native option because:

- the preview pane is narrow
- users scan files quickly there
- a moving player in a sidebar is usually the wrong density

## Recommended Direction For `MKVQuickLook`

## Recommendation 1: Treat compact preview as poster-only

This is the strongest UX recommendation.

Compact Finder preview should:

- show a centered poster or first frame
- show the file name
- show a minimal subtitle or format line
- avoid live playback entirely

That solves:

- cramped layout
- half-visible live video
- renderer instability in the narrow host

## Recommendation 2: Use the large panel for live playback

Expanded `Space`-bar preview should:

- host the live renderer
- stay paused until manual play
- show seek and volume
- center the renderer in a dedicated wrapper

## Recommendation 3: The next renderer experiment should be `VLCVideoLayer`, not more `VLCVideoView` tweaking

Why:

- `VLCVideoView` is the path with the known layer-backed resize bug history
- VideoLAN source and issue threads point toward the layer-based path as the better fit
- the current symptom looks like a renderer/layout problem, not a host-sizing problem

## Recommendation 4: Add a dedicated in-app renderer test surface

This is not a product feature.
It is a validation tool.

Before changing the Quick Look extension again, create a host-app "renderer lab" window that:

- uses the exact same renderer class
- loads the same sample MKV
- resizes through several aspect ratios
- logs the renderer frame and visible output behavior

That would let the project distinguish:

- renderer bug
- Quick Look host bug
- extension layout bug

## What This Research Changes In Practice

After this research, the likely plan is:

1. Stop trying to control Finder pane size from the extension.
2. Make compact preview poster-only or at least non-live.
3. Keep expanded preview as the interactive player.
4. Move the next centering fix attempt toward `VLCVideoLayer`.
5. Avoid manual `videoAspectRatio` forcing unless absolutely required.

## Sources

### Apple

- WWDC19: "What's New in File Management and Quick Look"
  - https://developer.apple.com/videos/play/wwdc2019/719/
- Apple Support: "Use the Preview pane in the Finder on Mac"
  - https://support.apple.com/en-md/guide/mac-help/mchl1e4644c2/mac
- Apple Documentation Archive: "Creating and Configuring a Quick Look Project"
  - https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/Quicklook_Programming_Guide/Articles/QLProjectConfig.html
- Quick Look UI documentation root
  - https://developer.apple.com/documentation/quicklookui/
- `QLPreviewingController`
  - https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller
- `QLPreviewViewStyle.normal`
  - https://developer.apple.com/documentation/quicklookui/qlpreviewviewstyle/normal
- `QLPreviewViewStyle.compact`
  - https://developer.apple.com/documentation/quicklookui/qlpreviewviewstyle/compact
- `NSViewController.preferredContentSize`
  - https://developer.apple.com/documentation/appkit/nsviewcontroller/1434409-preferredcontentsize

### VideoLAN / VLCKit

- VLCKit repository
  - https://github.com/videolan/vlckit
- `VLCVideoView.h`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Headers/VLCVideoView.h
- `VLCVideoLayer.h`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Headers/VLCVideoLayer.h
- `VLCMediaPlayer.h`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Headers/VLCMediaPlayer.h
- `VLCVideoView.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoView.m
- `VLCVideoLayer.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoLayer.m
- `VLCVideoCommon.m`
  - https://raw.githubusercontent.com/videolan/vlckit/master/Sources/Video/VLCVideoCommon.m
- VideoLAN issue `#82`: `[macOS] fillScreen not working after resizing player view`
  - https://code.videolan.org/videolan/VLCKit/-/issues/82
- VideoLAN issue `#276`: `set videoAspectRatio at cocoa incorrect`
  - https://code.videolan.org/videolan/VLCKit/-/issues/276

### Practical community references

- Stack Overflow: "Set QuickLook window size when previewing with QLPreviewingController.preparePreviewOfFile"
  - https://stackoverflow.com/questions/65633750/set-quicklook-window-size-when-previewing-with-qlpreviewingcontroller-preparepre
- Stack Overflow: "Setting preferredContentSize of QLPreviewingController breaks auto resizing"
  - https://stackoverflow.com/questions/66137642/setting-preferredcontentsize-of-qlpreviewingcontroller-breaks-auto-resizing
- Apple StackExchange: "Resizing preview pane in Finder column view"
  - https://apple.stackexchange.com/questions/275789/resizing-preview-pane-in-finder-column-view
- List of modern `.appex`-based Quick Look extensions
  - https://github.com/Oil3/List-of-modern-Quick-Look-extensions

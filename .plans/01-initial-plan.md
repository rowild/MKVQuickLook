# MKVQuickLook Implementation Plan And Postmortem

Version snapshot:

- release version: `0.1.7`
- build number: `8`
- snapshot date: `2026-04-16`

## Goal

Build a macOS app that contains a Quick Look Preview Extension for direct preview of:

- `mkv` as the primary target
- `webm`
- `ogv` / Ogg video
- `opus` (audio-only)

Target runtime:

- macOS 14
- macOS 15

Core requirement:

- no permanent remuxed or transcoded output files
- direct playback from the original file URL
- no external helper install requirement

## Final Working Architecture

### Host App

`MKVQuickLook.app` is the container for:

- the Quick Look Preview Extension
- VLC-based playback dependencies
- the settings/help UI
- the local playback lab used to test renderer behavior outside Finder

Why this matters:

- modern Quick Look previews are app-extension based
- Finder routing depends on the app bundle metadata, not just the extension metadata

### Quick Look Preview Extension

The extension is a view-based Quick Look preview extension with:

- `NSExtensionPointIdentifier = com.apple.quicklook.preview`
- a custom `PreviewViewController`
- direct playback of the original file URL

Current behavior:

- compact Finder column preview is non-live summary mode
- expanded Quick Look preview autoplays
- large Quick Look preview is the live playback surface

This was a deliberate change. Autoplay in the small Finder preview was too disruptive and Finder does not expose a reliable public “column preview vs full preview” switch for the extension.

### Playback Backend

The project uses bundled-at-build-time `VLCKit`.

Important packaging decision:

- `VLCKit` is bootstrapped by script into `Vendor/` for development and CI
- it is embedded into the `.appex` at build time
- it is not downloaded at runtime by the shipped app
- it does not need to be preinstalled on the user’s Mac

This is the correct distribution model for this project.

### Shared Playback Layer

Playback code is isolated in shared wrapper types rather than spread across the extension UI.

Important shared pieces:

- `MediaPreviewPlayer`
- `VLCKitMediaPreviewPlayer`
- `PreviewContentView`
- `VideoLayout`

Why this matters:

- Finder-specific behavior is hard to debug
- the same renderer path must be testable in a normal AppKit host window
- swapping renderer details should not require rewriting the whole extension

## What Actually Made Finder Use The Extension

The critical fix was not in the renderer. It was in Launch Services metadata.

The app must:

- `UTExportedTypeDeclarations` for the custom media UTIs it owns
- `CFBundleDocumentTypes` with `LSItemContentTypes`
- `LSHandlerRank = Owner`

The extension must:

- list the custom media UTIs in `QLSupportedContentTypes`

The install flow must:

- force Launch Services registration with `lsregister -f`
- refresh Quick Look caches
- refresh Finder / Quick Look UI services

Without that, the extension can be installed and still never be selected.

## Implemented Registration Model

### App Bundle

The app exports and owns these UTIs:

- `com.robertwildling.mkvquicklook.mkv`
- `com.robertwildling.mkvquicklook.webm`
- `com.robertwildling.mkvquicklook.ogg-video`
- `com.robertwildling.mkvquicklook.avi`

The app claims them as document types with:

- role `Viewer`
- rank `Owner`

### Extension Bundle

The extension supports:

- the system/public media UTIs where useful
- the custom `com.robertwildling...` UTIs above

In practice, the custom owned UTIs are what made routing predictable.

## Current Product Behavior

### Working

- Finder can route supported files to `MKVQuickLook`
- `mkv`, `webm`, and Ogg video preview path are working
- problematic `Reflections.mkv` is now selected through the extension and renders in the correct position
- large preview exposes manual controls
- volume and seek controls exist
- play/pause now lives in the control row beside the seek bar
- diagnostics exist for volume and seek latency
- dragging the volume knob lands at the release point correctly again
- dragging the seek knob works
- pure click behavior on the seek bar was repeatedly problematic in Finder-hosted Quick Look and required custom handling
- autoplay in expanded Quick Look works again without re-enabling the old compact-preview autoplay bug

### Deliberate Constraints

- compact Finder column preview is not a live player
- AVI is no longer advertised; the UTI registration and VLCKit path remain in the bundle but the feature is not presented to users (see Pitfall #9)
- no fallback remux pipeline exists
- some Finder-hosted control behavior still requires on-machine validation even when AppKit/VLCKit tests pass

### Playback Delay Explanation (Permanent Technical Constraint)

Both seek and volume changes have a short but perceptible delay. This is **not a software bug**. These delays are inherent to how digital audio and compressed video work and cannot be removed without introducing worse problems.

**Volume delay — audio output pipeline latency**

When the volume slider changes, the Swift API call sets the level instantly. What you hear is delayed because VLCKit renders decoded audio into a ring buffer that feeds Core Audio and then the hardware DAC. That buffer exists to absorb CPU timing jitter; without it, even a brief stall causes audible crackling or dropout. The buffer is typically **80–200 ms** deep on macOS. Volume changes apply only to audio not yet queued into the buffer. The audio already buffered plays at the old level and drains through first. Flushing the buffer to apply volume immediately would cause audible clicks on every adjustment. Even macOS's own system volume control has a milder version of this effect.

**Seek delay — inter-frame video compression**

Only keyframes (I-frames) in a compressed video stream are self-contained and decodable independently. P-frames and B-frames reference earlier frames and cannot be decoded alone. Seeking to an arbitrary position requires finding the nearest preceding keyframe and decoding every frame from there to the target. A typical H.264 stream with 2–10 second keyframe intervals at 30 fps means decoding **60–300 frames** before the target frame is displayable. For HD content this takes **100–500 ms** even with hardware decoding. Native Apple players appear faster because AVFoundation has direct access to the Apple Silicon hardware video decoder; VLCKit operates at a higher abstraction level.

These delays are documented in the UI with a note to the user. The slider position updates immediately; only the audio and video output lag behind.

### Current Control Findings

These findings are specific enough that they should remain documented here:

- volume drag is responsive because the app writes directly to `mediaPlayer.audio?.volume`
- the remaining volume delay is downstream of the Swift path, inside VLCKit's audio output buffer and Core Audio pipeline — this is permanent
- seek drag and seek click now use the same custom tracking loop via `window?.trackEvents`; the slider jumps immediately on mouseDown without AppKit's default page-step behavior
- a simple click on the seek bar no longer triggers a pause/resume cycle; `beginScrubbing` is deferred to the first actual drag event
- the remaining seek delay after a click is VLCKit's keyframe-to-target-frame decode latency — this is permanent

Implementation-level findings from the later volume investigation:

- the custom slider path must distinguish knob drags from track clicks; pre-applying an absolute value on knob drag start is wrong
- track-click targeting must use AppKit slider bar geometry (`NSSliderCell.barRectFlipped(_:)` / `knobRectFlipped(_:)`), not raw `bounds.width`
- volume needs the same kind of interaction protection that seek needed:
  - a persistent interaction identity during the drag/click
  - a pending requested value that stays authoritative
- the deeper correction is stronger than that:
  - for this app, the displayed volume should not be driven by repeated player read-backs at all
  - volume is a local user command, not a media timeline
  - letting VLCKit metric publications re-drive the slider reintroduces drift and apparent delay after release
- another concrete failure that actually happened:
  - the custom slider was still pre-applying an absolute value on knob drag start
  - that was wrong for knob drags and caused volume-handle movement to be inconsistent with the real drag gesture
- otherwise a late metrics publication from VLCKit can overwrite the just-released handle position and make the control feel delayed or imprecise

Primary sources used for this conclusion:

- AppKit SDK header: `NSSliderCell.h`
  - `-knobRectFlipped:`
  - `-barRectFlipped:`
- AppKit SDK header: `NSCell.h`
  - `-hitTestForEvent:inRect:ofView:`
- repository-local playback diagnostics logs and the `TrackingSlider` / `VLCKitMediaPreviewPlayer` code paths

Current diagnostic support:

- timestamped unified logging exists for seek and volume UI events, controller handoff, player apply, and post-apply metrics
- this must be used before making more speculative “speed” changes
- those diagnostics already answer one key question:
  - the app does measure UI-change, controller handoff, player apply, and later metrics timestamps
  - so when the slider still feels wrong after `apply`, the remaining problem is not “missing measurement”; it is usually wrong control architecture or downstream audio/output behavior
- local VLCKit volume notifications are now also logged, so future work must compare:
  - `ui-change`
  - `controller-change`
  - `apply`
  - `vlc-notification`
  - `metrics`

## Test Strategy That Must Stay In Place

### Renderer Smoke Tests

These tests are mandatory because they catch the worst regression we already caused:

- “the app builds, but no visible video frame is rendered”

The renderer tests:

- load real sample files
- start playback in an AppKit host window
- wait for visible video output
- require a readable snapshot frame to be produced

If these tests fail, do not ship the change.

Important CI exception:

- these smoke tests are intentionally skipped in the GitHub Release workflow
- reason: they depend on visible AppKit/VLCKit rendering and are not reliable on hosted release runners
- they remain mandatory for local verification

### Control Regression Tests

The test suite must also keep explicit regression coverage for control-state bugs that already happened:

- volume state must keep the latest requested value even if the player reports an older one
- playback metrics must not overwrite the user-controlled volume slider position
- active preview session replacement must stop the previous player

### Metadata Tests

These tests are also mandatory because Finder selection depends on metadata correctness:

- app exports the custom media UTIs
- app claims document ownership
- extension supports the custom media UTIs

If these tests fail, Finder may silently fall back to the system preview again.

### Layout Tests

The pure layout math is covered separately so centering rules can be tested without Finder or VLC.

### UI State Tests

UI regression coverage must include at least:

- overlay visibility once a paused-ready frame is visible
- playback button availability while VLC reports `opening` or `buffering`

These tests do not prove Finder event delivery, but they do protect against local UI regressions introduced by code changes.

## Code Examples That Matter

These examples are intentionally taken from the patterns that proved necessary in this repository.

### 1. App Bundle Ownership Metadata

Without host-app ownership metadata, Finder can ignore the extension even when the extension itself is installed.

Representative `Info.plist` shape:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>
    <string>com.robertwildling.mkvquicklook.mkv</string>
    <key>UTTypeConformsTo</key>
    <array>
      <string>public.movie</string>
      <string>public.data</string>
    </array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array>
        <string>mkv</string>
      </array>
    </dict>
  </dict>
</array>

<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>Matroska Video</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>com.robertwildling.mkvquicklook.mkv</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSHandlerRank</key>
    <string>Owner</string>
  </dict>
</array>
```

Why this matters:

- `UTImportedTypeDeclarations` alone was not enough
- the host app had to export and own the types
- Finder routing became predictable only after this metadata was correct

### 2. Extension Supported Content Types

The extension must explicitly list the custom owned UTIs:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.quicklook.preview</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).PreviewViewController</string>
  <key>QLSupportedContentTypes</key>
  <array>
    <string>com.robertwildling.mkvquicklook.mkv</string>
    <string>com.robertwildling.mkvquicklook.webm</string>
    <string>com.robertwildling.mkvquicklook.ogg-video</string>
    <string>com.robertwildling.mkvquicklook.avi</string>
  </array>
</dict>
```

Why this matters:

- app ownership and extension support must agree
- if the app exports the type but the extension does not support it, routing still breaks

### 3. Paused-By-Default Preview Wiring

The working shape is intentionally simple:

```swift
func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
    fileURL = url
    previewContentView.configureForLoading(fileURL: url)
    player?.loadMedia(from: url)
    player?.primeForPausedStart()
    completionHandler(nil)
}

@objc private func handlePlaybackButton() {
    player?.togglePlayback()
}
```

Why this matters:

- the preview loads media but does not autoplay
- this avoids surprise audio in Finder column preview
- earlier “start-and-immediately-pause” experiments caused regressions and should not be the default approach

### 4. Diagnostic Logging For Control Latency

The diagnostics need timestamps at every stage, not just inside the player:

```swift
PlaybackDiagnostics.log(
    "[seek] ui-change id=\(interactionID) " +
    "position=\(String(format: "%.4f", seekSlider.floatValue)) " +
    "final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())"
)
seekHandler?(seekSlider.floatValue, isFinal, interactionID)
```

```swift
PlaybackDiagnostics.log(
    "[seek] controller-change id=\(interactionID ?? 0) " +
    "position=\(String(format: "%.4f", position)) " +
    "final=\(isFinal) t=\(PlaybackDiagnostics.timestampString())"
)
player?.seek(to: position, isFinal: isFinal, interactionID: interactionID)
```

```swift
PlaybackDiagnostics.log(
    "[seek] apply-final id=\(activeSeekInteractionID ?? 0) " +
    "position=\(String(format: "%.4f", clampedPosition)) " +
    "t=\(PlaybackDiagnostics.timestampString())"
)
mediaPlayer.position = clampedPosition
```

Why this matters:

- without multi-stage timestamps, “it feels slow” is too vague to debug properly
- this is what separates Swift-side lag from VLC-side buffering/output lag

### 5. Direct Volume Application

The current volume path is deliberately direct:

```swift
func setVolume(_ volume: Int, interactionID: PlaybackDiagnostics.InteractionID?) {
    activeVolumeInteractionID = interactionID
    mediaPlayer.audio?.volume = Int32(max(0, min(200, volume)))
    let actualVolume = Int(mediaPlayer.audio?.volume ?? 0)
    PlaybackDiagnostics.log(
        "[volume] apply id=\(interactionID ?? 0) target=\(volume) " +
        "actual=\(actualVolume) t=\(PlaybackDiagnostics.timestampString())"
    )
    publishMetrics()
}
```

Why this matters:

- if drag feels immediate but bar-click feels slow, the remaining lag is likely not in this direct assignment itself
- the code path must stay simple before blaming VLCKit or output buffering

### 6. Seek Coalescing With Explicit Final Apply

Seek interaction needs separate handling for drag and release:

```swift
func seek(to position: Float, isFinal: Bool, interactionID: PlaybackDiagnostics.InteractionID?) {
    let clampedPosition = max(0, min(1, position))
    pendingSeekPosition = clampedPosition
    activeSeekInteractionID = interactionID

    if isFinal {
        pendingSeekWorkItem?.cancel()
        mediaPlayer.position = clampedPosition
        publishMetrics(positionOverride: clampedPosition)
        return
    }

    let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        guard let pendingSeekPosition = self.pendingSeekPosition else { return }
        self.mediaPlayer.position = pendingSeekPosition
        self.publishMetrics(positionOverride: pendingSeekPosition)
    }

    pendingSeekWorkItem = workItem
    DispatchQueue.main.asyncAfter(
        deadline: .now() + Constants.seekCoalescingInterval,
        execute: workItem
    )
}
```

Why this matters:

- drag would otherwise flood VLC with tiny seeks
- but release still needs a final direct seek so the slider does not bounce back

### 7. Renderer Smoke Test Shape

Visible-frame smoke tests are mandatory for this repo:

```swift
func testReflectionsMKVProducesVisibleVideoFrame() throws {
    let sampleURL = try XCTUnwrap(sampleURL(named: "Reflections.mkv"))
    let player = try makePlayerInHostWindow()

    player.loadMedia(from: sampleURL)
    player.play()

    let expectation = expectation(description: "visible video frame")
    waitForVisibleFrame(from: player, expectation: expectation)
    wait(for: [expectation], timeout: 10.0)
}
```

Why this matters:

- build success is not enough
- state changes are not enough
- this catches the exact regression where the player appears active but no image is visible

### 8. Metadata Regression Test Shape

The host app metadata is part of runtime behavior and must be tested like code:

```swift
func testAppExportsMediaTypesAndClaimsDocumentOwnership() throws {
    let info = try appInfoDictionary()
    let exportedTypes = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
    let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])

    XCTAssertTrue(exportedTypes.contains {
        ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.mkv"
    })

    XCTAssertTrue(documentTypes.contains {
        ($0["LSHandlerRank"] as? String) == "Owner"
    })
}
```

Why this matters:

- Finder routing depends on metadata correctness
- a metadata regression can silently undo the whole app even when code builds and tests otherwise look healthy

## Pitfalls, Errors, And No-Gos

This section is the main reason to keep this file updated.

### 1. Do Not Assume “Installed Extension” Means “Finder Will Use It”

This was the biggest architecture mistake.

What went wrong:

- the extension was registered
- `pluginkit` showed it
- but Finder still preferred the built-in movie preview

Root cause:

- the host app only imported types
- it did not export and own them as document types

Rule:

- always verify Launch Services ownership, not just extension registration

Checks to run:

- `pluginkit -m -A -D -i com.robertwildling.MKVQuickLook.PreviewExtension`
- `lsregister -dump`
- `mdls -name kMDItemContentType -name kMDItemContentTypeTree`
- `/usr/bin/log show ...`

### 2. Do Not Change The Renderer Path Without A Visible-Frame Test

This caused the worst regression.

What went wrong:

- `VLCVideoView` was replaced with a `VLCVideoLayer` path
- the build still succeeded
- playback logic still ran
- but no image was visible at all

Rule:

- renderer changes require renderer smoke tests to pass before being considered usable

No-go:

- never accept “state changes worked” as evidence that video rendering works

### 3. Do Not Treat Finder As The Only Test Host

Finder is too opaque for primary iteration.

What went wrong:

- renderer/layout debugging was happening directly inside Quick Look
- this made it too easy to confuse Finder-host issues, registration issues, and renderer issues

Rule:

- keep and use the host-app playback lab for the same shared renderer path

### 4. Do Not Autoplay In Compact Finder Preview

What went wrong:

- MKV files started playing immediately in Finder column view
- audio started before the user even opened the large Quick Look preview

Reason:

- Quick Look host context is not exposed cleanly enough to make autoplay reliable

Rule:

- compact Finder preview must stay non-live
- any autoplay behavior must be restricted to the expanded Quick Look path only

No-go:

- do not reintroduce autoplay in compact Finder preview unless there is a reliable host-context discriminator and a test for it

### 5. Do Not Trust VLC State Enums As The Only Playback Truth

What went wrong:

- state-driven paused-start experiments looked correct in code
- visible rendering worked in smoke tests
- but some user-triggered transitions still failed because VLCKit state changes were not reliable enough as the sole assertion target

Rule:

- test visible output, control availability, and user-observable behavior
- use VLC state as supporting telemetry, not as the only source of truth

### 6. Do Not Ship Control Changes Without Verifying Real Finder Interaction

What went wrong:

- slider drag behavior and slider click behavior were not identical
- AppKit control behavior inside Finder-hosted Quick Look differed from assumptions made from code inspection alone
- volume drag and volume track-click also did not feel equivalent to the user, even when both reached the same code path

Rule:

- when changing slider behavior, test both:
  - drag from the knob
  - direct click on the bar
- for volume, test both:
  - knob drag
  - bar click
- for seek, test both while playback is active:
  - knob drag
  - bar click with no drag
- for volume, backend playback metrics must not be allowed to re-drive the visible slider position during or after user interaction
- for knob drags, do not pre-apply an absolute track-click value at mouse-down

No-go:

- do not claim control fixes complete until both interaction styles are verified in Finder
- do not let player read-backs overwrite the user-commanded volume slider state

### 7. Do Not Use Clever Paused-Start State Machines Without End-To-End Playback Verification

What went wrong:

- a “prime paused start” experiment tried to secretly start and pause VLC so the preview would be ready faster
- that change caused regressions including:
  - no visible video
  - no sound
  - seek not working
  - overlay text not disappearing correctly

Rule:

- prefer the simpler behavior:
  - load media
  - present paused-ready UI
  - only start playback when the user explicitly presses Play

No-go:

- do not add hidden startup state machines unless they are covered by end-to-end playback tests and real Finder validation

### 8. Do Not Assume Compact Preview Size Is Under Extension Control

What went wrong:

- the small Finder column preview looked oversized and broken

Reality:

- Finder owns that host size
- the extension can only adapt its content to the given bounds

Rule:

- design compact preview content for constrained bounds
- do not try to “set the width” of Finder’s preview pane

### 9. AVI Routing Requires Explicit `public.avi` Ownership

AVI has a special routing problem that the other supported formats do not.

Root cause:

- `mkv`, `webm`, `ogv`, and `opus` do not have Apple-system UTIs with the `public.` prefix
- `.avi` files are assigned `public.avi` by macOS — an Apple-owned system type
- the app's custom UTI `com.robertwildling.mkvquicklook.avi` uses the `com.robertwildling.` prefix and does not inherit from `public.avi`
- if the app only claims ownership of `com.robertwildling.mkvquicklook.avi`, Finder assigns actual `.avi` files as `public.avi` and routes them to the system handler, completely ignoring this extension

Fix applied:

- `public.avi` was added to the `LSItemContentTypes` array of the AVI document type entry in `MKVQuickLookApp/Resources/Info.plist`
- the extension already listed `public.avi` in `QLSupportedContentTypes`

Fix limitation — Quick Look extension still does not override system generator for `public.avi`:

- even with `public.avi` claimed in both `CFBundleDocumentTypes` and `QLSupportedContentTypes`, the system `Movie.qlgenerator` in `/System/Library/QuickLook/` takes over for `public.avi` on any system where MKVQuickLook is not the active default opener for AVI
- Quick Look routes to the Quick Look extension of whichever app is the registered default opener for the UTI; if that app is VLC (or anything other than MKVQuickLook), the system generator handles the preview instead
- this is a macOS design constraint, not a bug: the only fix is to set MKVQuickLook as the default app for `.avi` via Finder → Get Info → Open With → Change All, or via `duti -s com.robertwildling.MKVQuickLookApp public.avi all`
- in practice this is not critical: macOS `Movie.qlgenerator` handles AVI files with common codecs (MPEG-4 Part 2 / DivX, H.264, MP3) correctly via AVFoundation; our extension's irreplaceable value is for MKV, WebM, Ogg, and Opus which the system cannot preview at all

Rule:

- for any file type that macOS already recognises with a `public.*` or `org.*` system UTI, the app must claim the system UTI directly in `CFBundleDocumentTypes`, not just a custom shadow type
- AVI codec support is still best-effort — VLCKit handles DivX, Xvid, H.264 in AVI, and most modern encodings, but will fail on obscure legacy codecs such as Indeo Video
- do not treat "Quick Look uses system generator for AVI" as an unresolved bug; document it as a known architectural constraint

### 10. Do Not Introduce A Remux Fallback Into The Main Path

This project exists specifically to avoid that.

No-go:

- no ffmpeg/remux/transcode fallback in the normal preview path
- no persistent generated media files

### 11. Do Not Describe Work As Solved Before Evidence Exists

What went wrong:

- some explanations used probability language or confidence language before the underlying behavior was fully verified
- that weakened trust and violated the repository communication standard

Rule:

- separate observed fact, evidence, hypothesis, fix, and remaining unverified risk
- do not describe a fix as complete until tests and observed behavior support that claim

No-go:

- do not present guesses, partial reasoning, or under-verified fixes as if they were solid conclusions

## Recommended Debug Workflow For Future Changes

When something breaks, use this order:

1. Run the test suite.
2. Confirm metadata tests and renderer smoke tests both pass.
3. If Finder is not selecting the extension:
   - inspect app `Info.plist`
   - inspect extension `Info.plist`
   - inspect `lsregister -dump`
   - inspect `pluginkit`
   - inspect `mdls`
4. If the extension is selected but rendering is wrong:
   - reproduce in the host-app playback lab first
   - only then debug Finder-specific behavior
5. Use `/usr/bin/log show` to confirm whether `MKVQuickLookPreviewExtension` is actually launched.

## Files That Matter Most

Core implementation:

- `project.yml`
- `MKVQuickLookApp/Resources/Info.plist`
- `MKVQuickLookPreviewExtension/Resources/Info.plist`
- `Shared/Sources/Player/VLCKitMediaPreviewPlayer.swift`
- `Shared/Sources/PreviewContentView.swift`
- `Shared/Sources/VideoLayout.swift`
- `MKVQuickLookPreviewExtension/Sources/PreviewViewController.swift`

Installation and registration:

- `scripts/install-local.sh`
- `scripts/reset-quicklook.sh`

Tests that must not be removed:

- `Tests/VideoLayoutTests.swift`
- `Tests/BundleMetadataTests.swift`

## Current Status

The project now has:

- working app container
- working Quick Look Preview Extension
- bundled VLC dependency
- system-level Launch Services ownership configured correctly
- renderer smoke tests
- metadata regression tests
- settings/help UI
- host-app playback lab for renderer debugging

## Next Safe Improvements

These are reasonable future changes:

- improve compact preview poster/summary presentation
- improve playback controls polish
- strengthen logging around extension lifecycle and file type routing
- document release packaging and distribution more cleanly

These are risky and should be approached carefully:

- changing renderer integration again
- changing expanded-preview autoplay behavior without re-checking compact-preview isolation
- trying to force Finder compact preview sizing
- adding conversion/remux fallback logic

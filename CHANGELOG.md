# Changelog

## Unreleased

## 0.1.10 - 2026-10-10

### Changed

- `VLCKit` is embedded once instead of twice. The app is about 80 MB instead of 158 MB, and the DMG about 40 MB instead of 74 MB. The app embeds `VLCKit.framework` in `Contents/Frameworks`; the Quick Look extension only links it. Because `VLCKit` records its load path as `@loader_path/../Frameworks/...`, a build step of the extension target (`scripts/link-extension-to-app-vlckit.sh`) rewrites the extension's reference to `@loader_path/../../../../Frameworks/...` after linking and re-signs the binary ad hoc. The build fails if the reference is not the expected one.
- `scripts/verify-vlckit-load-paths.sh` checks a built app (one `VLCKit` copy, every reference resolves). `install-local.sh` and `build-release-dmg.sh` run it before they install or package, and they now sign the app's `VLCKit` copy.
- The test file `Tests/VideoLayoutTests.swift` is split by topic into `VideoLayoutTests`, `MediaKindTests`, `PreviewContentViewTests`, `PreviewPlaybackLifecycleTests`, `PreviewPlayerBindingTests`, `MediaPreviewPlayerSessionTests`, `RendererSmokeTests` and `TestSupport` (shared spies and helpers). All 41 existing tests are unchanged.

### Added

- Bundle tests `testBuiltAppEmbedsVLCKitOnce` and `testEveryBinaryCanResolveItsVLCKitLoadPath`. The second one resolves the app's and the extension's `VLCKit` load paths the way dyld does, so a bundle layout that would crash the extension at launch fails the tests.

### Known Issues

- The intermittent `VLCKit` teardown deadlock (see 0.1.9) hit the renderer smoke tests again in 1 of 3 runs while this release was prepared. The smoke tests do not involve the bundle layout. The trigger is still unknown.
- All other Known Issues of 0.1.9 remain, except the app size, which this release fixes.

## 0.1.9 - 2026-10-10

### Fixed

- A preview that Finder had already closed no longer starts again, out of sight and with sound. Finder lays a closed preview out once more (for example in Gallery view), and that layout pass reloaded and restarted the video. The load/start/stop decision now lives in `PreviewPlaybackLifecycle`: a closed preview stays stopped until it is prepared or shown again.
- The play button works again after "Playback stopped". `stop()` unloads the media; pressing play now reloads the last file instead of doing nothing.
- In the Space window, moving to a file that Quick Look shows with another previewer (for example an AVI) no longer leaves the previous video playing in the background. Quick Look does not tell the extension; Finder does close its column preview of the previous file at that moment, and a closed preview of the playing file now stops it. This works in column view and whenever the Finder preview pane is open.

### Changed

- Lifecycle diagnostics in the unified log: `[ql] prepare / autoplay / will-appear / did-disappear / stop`, `[session] …` and `[load]` / `[stop]` per player.
- `MediaPreviewPlayer.loadedFileURL` exposes the file last passed to `loadMedia(from:)`.

### Known Issues

- Gallery view, and list or icon view without the preview pane: when Finder switches to a file shown by another previewer (`.mp4`, `.mov`, `.avi`), the previous MKVQuickLook preview keeps playing until Finder closes it. Finder sends the extension no signal in these cases.
- Rare, intermittent freeze inside VLCKit while a player is destroyed: two VLCKit cleanup threads deadlock on VLC's configuration lock. Reproduced 3 times in a load/stop stress program and in 2 renderer smoke-test runs, then 0 times in 10 alternating runs of the 0.1.7 and 0.1.8 player code. The trigger is not known, and it is not known whether 0.1.8 made it more likely.
- Renderer smoke tests can hang when VLCKit produces no video output, because stopping the player then blocks. Run them with `-test-timeouts-enabled YES -default-test-execution-time-allowance 60`.
- All Known Issues of 0.1.8 remain.

## 0.1.8 - 2026-10-10

### Fixed

- `.ogg`, `.oga`, `.opus` and `.ogv` files now reach the Quick Look extension on Macs where another app (for example a Chromium-based browser) declares `org.xiph.ogg-audio` / `org.xiph.ogg-video`. macOS resolved these files to those identifiers, which `QLSupportedContentTypes` did not list. A new test checks the identifier this Mac resolves for every advertised extension.
- The "Preparing video surface..." placeholder no longer reappears over a playing video after a layout pass (window resize, full screen). A failure message is no longer replaced on the next layout pass.
- Audio-only Ogg files use the audio preview layout instead of an empty black video frame. Audio vs. video is now decided from the tracks VLCKit parses, not from the file extension.
- Renderer smoke tests pointed to a missing `Reflections.mkv` sample. They now use `Reflections-test.mkv` and name the missing file when a local sample is absent.
- Loading a file no longer parses it on the main thread. The deprecated `synchronousParse()` blocked the Quick Look window on large files or slow volumes. Parsing now runs asynchronously (`parse(options:timeout:)`, 5 s timeout), and the video size and audio/video kind arrive through `mediaDidFinishParsing(_:)`. The player keeps its own reference to the current `VLCMedia`, because `VLCMediaPlayer` does not keep it alive and its `media` getter returns a different object.
- AppKit no longer logs "Invalid view geometry" while the video frame is smaller than 2 pt. `VideoLayout.fittedRect` returned the null rect (infinite origin) it got from insetting tiny bounds; it now returns `.zero` for null or infinite bounds.

### Added

- The video play/pause overlay is an accessibility button ("Play" / "Pause"), so VoiceOver, Voice Control and Full Keyboard Access can start and pause a video.
- The app ships the VLCKit license (LGPL 2.1) at `MKVQuickLook.app/Contents/Resources/VLCKit-COPYING.txt`. A test checks the built app for it.

### Changed

- The host app no longer advertises AVI and now lists Opus in its supported formats. Leftover development wording ("scaffold", "Next Implementation Step", "remaining work", "current phase") was replaced.
- The Renderer Lab can open `.opus` files.
- The Quick Look extension and the Renderer Lab now share one tested player/view wiring (`PreviewPlayerBinding`) instead of two hand-copied versions. Diagnostics keep the `controller-*` and `lab-*` log names.
- `PreviewContentView` stores its presentation mode instead of reading it from a hidden label.
- Removed code without effect: `VolumeFeedbackState` and `MediaPreviewPlaybackMetrics.volume` (the view never read them), the unused `setMuted`, an empty `updateTrackingAreas` override, a `perform()` in `endScrubbing` that never applied a seek, and redundant `await MainActor.run` calls. The `[volume] metrics` log now reports the actual VLCKit volume.
- `scripts/install-local.sh` builds into its own `.build/install-derived-data` folder instead of searching Xcode's shared DerivedData, which could pick up a stale build from another copy of the project. A failed build now prints the errors and the log path.
- GitHub releases use only the matching `CHANGELOG.md` section as release notes (`scripts/changelog-section.sh`), not the whole file. The release job fails if that section is missing.
- `.claude/settings.json`: removed permission rules for a deleted file and for an old project path.
- `project.yml`: removed the `resources:` keys. XcodeGen ignored them, so they never copied anything; regenerating the project without them produces an identical project file. The license file is added through `sources` with `buildPhase: resources`.

### Documentation

- README: fixed the workflow link, which pointed to a local path on the developer's Mac.
- The 0.1.7 entry said all AVI references were removed. The bundle registration, the bundle metadata tests, and the Renderer Lab still reference AVI on purpose.
- Corrected the AVI notes in `.plans/01-initial-plan.md` (Pitfall #9). This also corrects the 0.1.6 Known Issues entry, which said the system preview plays AVI files with common codecs. On macOS 26.6.2, AVFoundation opens an AVI with MPEG-4 Part 2 (DivX) video and MP3 audio with no tracks, so the system preview cannot play it. While VLC (or any other app without a Quick Look extension) is the default `.avi` app, such files get no working preview. VLC stays the default AVI app by decision.
- Fixed the `duti` example, which used a wrong bundle identifier (`com.robertwildling.MKVQuickLookApp` instead of `com.robertwildling.MKVQuickLook`).

### Known Issues

- Quick Look routing still depends on the type identifier each Mac resolves for a file, and other installed apps can declare their own identifiers. This release covers the identifiers seen on the development Mac (`org.xiph.ogg-audio`, `org.xiph.ogg-video`). A Mac where yet another app wins can still route a format past the extension; the new bundle test reports this on the machine that runs it.
- AVI files with codecs AVFoundation cannot decode (for example DivX/MP3) get no working Quick Look preview while another app, such as VLC, is the default `.avi` app. Making MKVQuickLook the default AVI app is not practical: the host app cannot open files, so a double-click would only show its status window.
- VLCKit (about 79 MB) is embedded twice, in the app and in the extension, so the app is about 159 MB.
- Not verified: a Finder preview pane larger than 720 × 440 pt is treated as the full Quick Look player and may start playback with sound.
- Seek and volume delays are inherent pipeline constraints, not bugs. See README section "Playback Delays".
- The app is ad hoc signed and not notarized. See README section "Gatekeeper".

## 0.1.7 - 2026-04-16

### Changed

- Removed AVI from the advertised list of supported formats. The UTI registration and VLCKit playback path for `.avi` remain in the bundle, but the feature was conditional on MKVQuickLook being the active default opener for `public.avi` — a constraint that makes it unreliable to advertise. The README feature list, AVI Quick Look Limitation section, and all dev/testing AVI references have been removed.
- Added `.vscode/` to `.gitignore` to prevent editor-local Claude Code workspace settings from being committed to the repository.

### Known Issues

- Seek and volume delays are inherent pipeline constraints, not bugs. See README section "Playback Delays".

## 0.1.6 - 2026-04-10

### Fixed (Documentation)

- Clarified in `.plans/01-initial-plan.md` that the Quick Look extension does not override the system `Movie.qlgenerator` for `public.avi` files unless MKVQuickLook is set as the active default opener for AVI in Launch Services. The `LSHandlerRank = Owner` declaration is a preference, not a guarantee — if another app (e.g. VLC) is already the registered default, the system generator wins. This is a macOS architectural constraint, not a code bug.

### Known Issues

- For AVI files, Quick Look uses the system `Movie.qlgenerator` (AVFoundation) on systems where MKVQuickLook is not the default app for `public.avi`. This produces a working preview for files with common codecs (MPEG-4 Part 2, H.264, MP3). For exotic codecs that AVFoundation cannot decode, the user must set MKVQuickLook as the default AVI opener via Finder → Get Info → Open With → Change All.
- Seek and volume delays are inherent pipeline constraints, not bugs. See README section "Playback Delays".

## 0.1.5 - 2026-04-10

### Added

- Hover overlay play/pause toggle on the video frame — fades in on mouse enter, fades out on exit, clicking anywhere on the video frame toggles playback. Matches native Quick Look behavior.
- Buffering note label added to the expanded preview explaining that seek and volume changes have an inherent short delay caused by VLCKit's audio/video pipeline.
- README now includes a permanent technical explanation of volume buffer latency (80–200 ms) and keyframe seek latency (100–500 ms) so users understand these are inherent hardware/codec constraints, not bugs.

### Changed

- Seek and volume sliders now jump immediately to the click position. Replaced `super.mouseDown` (which triggered AppKit page-step behavior) with a `window?.trackEvents` custom local event loop. Handle jumps on first `mouseDown`; `beginScrubbing` is deferred to the first actual drag event, so a plain click never triggers an unwanted pause/resume cycle.
- Play button removed from the controls row for video mode. The hover overlay replaces it. The play button is kept only for audio-only mode where there is no video frame to hover.
- AVI routing fixed: added `public.avi` to `LSItemContentTypes` in `CFBundleDocumentTypes`. macOS assigns real `.avi` files the system UTI `public.avi`; the app only claimed `com.robertwildling.mkvquicklook.avi`, so Finder never routed `.avi` files to it. The extension `QLSupportedContentTypes` already had `public.avi`; only the host app ownership declaration was missing.

### Removed

- `VLCVideoLayerHostView.swift` deleted. It was dead code — never referenced outside its own file. The playback path exclusively uses `VLCVideoView`.

### Known Issues

- Seek and volume delays are not bugs but inherent pipeline constraints. See README section "Playback Delays" for the full technical explanation.
- AVI playback is routed correctly but playback quality for obscure legacy codecs (DivX, old Xvid variants, uncompressed audio) depends on VLCKit codec support and may fail for unusual files.

## 0.1.4 - 2026-04-10

### Added

- Added owned `.opus` audio support in the app and extension metadata.
- Added an audio-only Quick Look mode that keeps playback controls visible without showing an empty video frame.
- Added stronger regression tests for volume state handling and for preventing playback metrics from overwriting the user-controlled volume slider position.
- Added local VLCKit volume-notification diagnostics so downstream audio timing can be measured instead of guessed.

### Changed

- Full Quick Look preview autoplays again in expanded mode; compact Finder preview remains a non-live summary.
- Volume slider state is now driven by the last user-commanded value instead of repeated backend metric write-backs.

### Fixed

- Selecting another file while a preview is already open now stops the previously active preview session before the new one loads, preventing stray audio from continuing in the background.
- Pause now cuts audible output immediately before VLC finishes its own state transition, so the control feels more responsive.
- Volume handle release now stays at the released position instead of snapping back to the earlier pickup position.
- The custom slider no longer pre-applies an absolute value on knob drag start, which was a real source of incorrect volume-handle movement.

### Known Issues

- Direct click on the volume bar still has an observable delay on the target machine even though handle placement is now exact.
- The remaining volume-click latency is instrumented but not fully eliminated in Finder-hosted Quick Look.

## 0.1.3 - 2026-04-09

### Changed

- Replaced the committed `VLCKit` binary payload with a pinned bootstrap download script.
- Updated install, DMG-build, and GitHub Actions release paths to fetch `VLCKit` automatically when needed.
- Updated the GitHub Actions release workflow to skip `RendererSmokeTests` at the `xcodebuild` layer so the DMG packaging path can complete on GitHub-hosted macOS runners.
- Clarified the README release flow so the asynchronous DMG upload behavior on GitHub Releases is easier to understand.

### Fixed

- Reduced repository bloat by removing the tracked `VLCKit` runtime payload and generated release artifacts from Git history.
- Fixed the release pipeline so a tagged GitHub Actions run can finish and attach a downloadable DMG asset to the GitHub Release.

### Notes

- Local development still keeps the full renderer smoke tests.
- GitHub release runs intentionally skip only the GUI renderer smoke tests; the metadata and layout tests still run in CI.

## 0.1.2 - 2026-04-09

### Changed

- Added automatic tag-driven GitHub Release automation with a macOS GitHub Actions workflow.
- Added a script to build a release DMG and upload-ready release artifacts.
- Added developer and release documentation for GitHub Releases, ignored build artifacts, and repository size policy.

### Notes

- `v0.1.2` was the first automated-release attempt and exposed CI incompatibility in the renderer smoke tests.

## 0.1.1 - 2026-04-09

### Added

- Bundled `VLCKit` playback backend embedded directly into the Quick Look preview extension.
- Shared playback layer for the app and Quick Look extension:
  - `MediaPreviewPlayer`
  - `VLCKitMediaPreviewPlayer`
  - `PreviewContentView`
  - `VideoLayout`
- Playback diagnostics via unified logging under:
  - subsystem: `com.robertwildling.MKVQuickLook`
  - category: `Playback`
- Host-app playback lab for renderer and layout verification outside Finder.
- Renderer smoke tests that verify visible video output for real sample media.
- Metadata tests that verify Launch Services ownership and extension-supported types.
- UI regression tests for overlay visibility and playback button availability.

### Changed

- Quick Look playback now starts paused by default in all contexts.
- Compact Finder column preview is non-live summary mode instead of autoplaying media.
- Finder routing now relies on exported and owned app UTIs plus document claims, not extension registration alone.
- The play/pause button was moved into the control row to the left of the seek bar.
- Volume changes while dragging are immediate.
- Seek dragging is stable and no longer snaps back to the old value after release.
- Seek and volume controls now emit timestamped diagnostics for latency analysis.

### Fixed

- Finder now reliably selects `MKVQuickLook` for the supported owned media UTIs.
- `Reflections.mkv` now renders through the custom Quick Look path instead of the stock preview.
- Large-preview renderer regressions where state changed but no visible video frame appeared.
- MKV centering issues caused by earlier renderer/layout experiments.
- Immediate autoplay in Finder column preview.
- Stuck overlay text such as `Preparing video surface...` after video output becomes visible.
- Audio muting regressions introduced during paused-start experiments.
- Pause button becoming unavailable while VLC remained in `opening` or `buffering`.

### Notes

- `avi` remains best-effort support.
- The current OGG sample in `example-videos` resolves to audio on this machine, not Theora video.
- Pure seek-bar click behavior has been strengthened again in this version and should be revalidated in Finder on the target machine.

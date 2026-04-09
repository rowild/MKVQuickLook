# Changelog

## Unreleased

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

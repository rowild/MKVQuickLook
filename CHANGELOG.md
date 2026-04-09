# Changelog

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

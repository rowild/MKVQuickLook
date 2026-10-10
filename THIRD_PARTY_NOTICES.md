# Third-Party Software

MKVQuickLook's own source code is licensed under the MIT License (see `LICENSE`).
The app also contains the following third-party software. It keeps its own license.

## VLCKit 3.7.2 (with libVLC, VLC 3.0.23)

- **Copyright:** VideoLAN and the VLC and VLCKit authors
- **License:** GNU Lesser General Public License, version 2.1 or later (LGPL-2.1-or-later)
- **License text in the app:** `MKVQuickLook.app/Contents/Resources/VLCKit-COPYING.txt`
- **Location in the app:** `MKVQuickLook.app/Contents/Frameworks/VLCKit.framework`. MKVQuickLook uses it unmodified, as a separate dynamic framework. The Quick Look extension loads it from there.
- **Binary used:** the official VideoLAN package
  `https://download.videolan.org/cocoapods/prod/VLCKit-3.7.2-3e42ae47-79128878.tar.xz`
  (SHA-256 `45fc6398c80d1f8dc0e384a9c80704848e9e82a3a382611bf531fa83c198c276`)

### Corresponding source code

- **VLCKit**, tag `3.7.2` (commit `3e42ae4786d74be5a7387e01824733cbd4b294c3`):
  https://code.videolan.org/videolan/VLCKit/-/tree/3.7.2
  (mirror: https://github.com/videolan/vlckit/tree/3.7.2)
- **VLC (libVLC)**, branch `3.0.x`, commit `79128878ddb2c280bbb6c89c76a46b31a80ade1c`:
  https://code.videolan.org/videolan/vlc/-/tree/79128878ddb2c280bbb6c89c76a46b31a80ade1c
  (mirror: https://github.com/videolan/vlc/tree/79128878ddb2c280bbb6c89c76a46b31a80ade1c)
  VLCKit's build applies the patches in `libvlc/patches` of the VLCKit tag above to this commit.
- The libraries that VLC builds into VLCKit (for example FFmpeg, built here under LGPL-2.1-or-later) are defined, with their versions and checksums, in `contrib/src` of that VLC source.

### Replacing VLCKit

You may replace `MKVQuickLook.app/Contents/Frameworks/VLCKit.framework` with a modified, interface-compatible build. Then re-sign the framework and the app, for example:

```sh
codesign --force --sign - MKVQuickLook.app/Contents/Frameworks/VLCKit.framework
codesign --force --sign - MKVQuickLook.app
```

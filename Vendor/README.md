# Vendor

This directory is used for locally bootstrapped binary dependencies.

It is intentionally not fully tracked in Git.

Current expected generated contents:

- `VLCKit.xcframework`
- `VLCKit-COPYING.txt`
- `VLCKit-NEWS.txt`

Populate it with:

```sh
./scripts/bootstrap-vlckit.sh
```

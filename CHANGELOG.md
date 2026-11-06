# Changelog

All notable changes to evovpeg. Versions follow Semantic Versioning and move when the source or build recipe changes.

## [0.1.0] - 2026-11-06

### Added

- First software-only video decode profile from FFmpeg 9.0.2, with dav1d 1.5.1 for AV1.
- Static `evovpeg` and `evovprobe` programs for armv7 (also shipped as `arm`), armv8 and x64, with no network or device I/O and no shared-library runtime dependencies.
- Decode and probe support for H.264, H.265/HEVC, H.266/VVC, MPEG-2, MPEG-4 Part 2, VP8, VP9 and AV1.
- Per-target ELF, component-set, probe, decode, seek, network-isolation and compiler-warning checks.
- Signed release archives using the evo release key.

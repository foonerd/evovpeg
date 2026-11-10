# Changelog

All notable changes to evovpeg. Versions follow Semantic Versioning and move when the source or build recipe changes.

## [0.3.2] - 2026-11-10

### Added

- HTTP and HTTPS input for both programs, with static mbedTLS, certificate and hostname verification, request headers, range seeking and timeout support.
- Static x264 H.264 and native AAC encoding, PNG/JPEG/WebP and raw-frame input, raw PCM input, padding, and FLV, H.264 and fragmented MP4 output.
- Network and H.264/AAC encode checks, including landscape/portrait still frames, dual-pipe input, two-second GOPs and decoded output verification.
- Corresponding-source release archive with verified upstream sources, patches and the complete build recipe.
- Bounded CPU, memory and paced encode-latency measurement tools.
- Windows x64 `evovpeg.exe` and `evovprobe.exe`, built with MinGW-w64 and checked for Windows-system-only DLL imports.
- Android NDK builds for Glass's `armeabi-v7a`, `arm64-v8a` and `x86_64` ABIs, using API 24 and the platform C runtime.
- Signed-release ZIP packaging for Windows and Android, with per-architecture decoder/prober paths and SHA-256 digests in `manifest.json`.
- Native Windows codec, HTTP range, TLS verification and Linux frame-parity checks, plus Android x86_64 emulator probe/decode parity checks.

### Changed

- Cross-target dependency builds now use the pinned MinGW and Android NDK toolchains; Linux target outputs remain unchanged in format.
- All platform binaries are represented in one release manifest; Windows/Android archives use ZIP and Linux archives remain tar.gz.
- The combined binaries are distributed under GPL version 3 or later; dependency licences are included in every binary archive.
- Local-only invocations can restrict input with `-protocol_whitelist file,pipe`; network support is now included in the binary and that restriction is not an OS sandbox.
- Existing software and ARM V4L2 M2M decoders remain enabled; HLS/DASH ingestion and RTMP transport are not added.

### Fixed

- Keep parallel FFmpeg build diagnostics grouped so the warning gate receives intact output.
- Normalize CRLF when comparing FFmpeg component lists, and use a tail-indexed MP4 to ensure Windows HTTP smoke exercises Range requests.
- Run Android CI with an explicit Pixel 2 AVD, service-readiness checks and software translation on runners without KVM.
- Fetch zlib 1.4 from its official fossil archive using the published checksum; its source tree matches the original pinned archive.

## [0.2.0] - 2026-11-06

### Added

- Upstream FFmpeg V4L2 M2M decoders for H.264, HEVC, MPEG-2, MPEG-4 Part 2, VP8 and VP9 on armv7 and armv8. Existing software decoders remain enabled; x64 remains software-only.
- ARM smoke gates that verify all six M2M decoders are registered without requiring hardware access.
- Project-generated VVC smoke fixture with exact decoded frame-size and luma checks, removing the external FATE sample dependency.

## [0.1.1] - 2026-11-06

### Added

- Native FFmpeg audio decoders for Glass lip-sync calibration, outputting selected audio as mono 8 kHz float PCM while leaving audible playback to MPD.
- AAC-bearing Matroska smoke fixtures paired with all six video codec samples; each target probes AAC and checks PCM output length and non-silent samples.
- ASF demuxing for WMAv2 and raw f32le output support; network and device I/O remain disabled.

## [0.1.0] - 2026-11-06

### Added

- First software-only video decode profile from FFmpeg 9.0.2, with dav1d 1.5.1 for AV1.
- Static `evovpeg` and `evovprobe` programs for armv7 (also shipped as `arm`), armv8 and x64, with no network or device I/O and no shared-library runtime dependencies.
- Decode and probe support for H.264, H.265/HEVC, H.266/VVC, MPEG-2, MPEG-4 Part 2, VP8, VP9 and AV1.
- Per-target ELF, component-set, probe, decode, seek, network-isolation and compiler-warning checks.
- Signed release archives using the evo release key.

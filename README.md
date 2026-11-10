# evovpeg

`evovpeg` is the media codec component of the evo framework. It probes and decodes media for Glass and encodes H.264/AAC output for Outcast. Glass's audible playback continues through MPD; Outcast owns its streaming destinations.

Linux programs are statically linked with no shared-library dependencies. Windows programs use only Windows system DLLs. Android programs use the platform's Bionic runtime and no bundled third-party shared libraries:

| Program | Purpose |
| --- | --- |
| `bin/evovpeg` (`evovpeg.exe` on Windows) | Decode video/audio or encode H.264/AAC streams on stdout. |
| `bin/evovprobe` (`evovprobe.exe` on Windows) | Report selected audio/video stream properties. |

FFmpeg device capture/output modules and non-free components are disabled. Protocols are restricted to `file`, `pipe`, `tcp`, `http`, `https` and `tls`. HTTPS uses statically linked mbedTLS; H.264 encoding uses statically linked x264, making the resulting programs GPL-covered. The build, package and release checks verify the enabled component set and reject ELF interpreters and dynamic dependencies.

## Supported Set

The software decode profile includes H.264, H.265/HEVC, H.266/VVC, MPEG-2, MPEG-4 Part 2, VP8, VP9 and AV1 video, plus AAC, AAC-LATM, AC-3, E-AC-3, DTS, TrueHD, MLP, MP3, MP2, Opus, Vorbis, FLAC, ALAC, WMA v2 and PCM audio. AV1 uses the statically linked dav1d library. Audio decoding produces PCM and does not replace MPD's playback path. Supported input containers and elementary streams are recorded in `components/ffmpeg/configure.txt` and checked against the built binary on every target.

ARM builds include upstream V4L2 M2M decoder registrations for H.264, HEVC, MPEG-2, MPEG-4 Part 2, VP8 and VP9 alongside the software decoders. These registrations require a compatible V4L2 M2M device and driver at runtime; the build does not claim hardware execution. x64 remains software-only. VAAPI and V4L2 request API decoders are not included.

## Platform Builds

Linux targets are `armv7` (also released as `arm`), `armv8` and `x64`. Windows provides x64 executables. Android targets the Glass app's `armeabi-v7a`, `arm64-v8a` and `x86_64` ABIs at API 24. Android binaries use the system runtime; Glass currently does not enable its movie-decoding module on Android, so these binaries alone do not add movie playback to the app. MediaCodec acceleration is not enabled.

## Use

For local-only input, pass `-protocol_whitelist file,pipe` before each input. For HTTPS, pass `-tls_verify 1 -ca_file CA_FILE` before the input. Protocol whitelists constrain input access; they are not a process-wide network sandbox. The caller owns credentials, destinations and operating-system access restrictions.

Probe a file:

```sh
evovprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 FILE
```

Decode from a seek position to a back-pressured pipe:

```sh
evovpeg -nostdin -loglevel error -ss SECONDS -i FILE \
  -an -sn -f rawvideo -pix_fmt yuv420p -
```

Each frame is `width * height * 3 / 2` bytes. Decoder errors end the output stream; the caller owns playback timing and presentation.

Decode the media's audio track separately for analysis or synchronization:

```sh
evovpeg -nostdin -loglevel error -ss SECONDS -i FILE \
  -vn -sn -ac 1 -ar 8000 -f f32le -
```

This writes mono 8 kHz float PCM to stdout. Glass drains the video and audio invocations independently; MPD remains responsible for audible playback.

Render a PNG, JPEG or WebP picture once at the output size:

```sh
evovpeg -nostdin -v error -i picture.png \
  -vf 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p' \
  -frames:v 1 -f rawvideo picture.yuv
```

Encode that frame repeatedly with stereo signed 16-bit PCM on stdin, producing H.264/AAC FLV on stdout:

```sh
evovpeg -nostdin -v error \
  -f rawvideo -pix_fmt yuv420p -video_size 1280x720 -framerate 10 \
  -stream_loop -1 -i picture.yuv -f s16le -ar 44100 -ac 2 -i pipe:0 \
  -map 0:v:0 -map 1:a:0 -c:v libx264 -preset veryfast \
  -tune stillimage,zerolatency -profile:v main -b:v 500k \
  -maxrate 500k -bufsize 1000k -g 20 -keyint_min 20 -sc_threshold 0 \
  -c:a aac -b:a 128k -ar 48000 -f flv -flush_packets 1 pipe:1
```

Use `720x1280` and matching scale/pad dimensions for portrait output. Keep the GOP at twice the frame rate for two-second keyframe intervals. The `zerolatency` tune disables lookahead buffering; callers own pacing, bitrate, frame-rate and quality selection. Raw video and PCM can also arrive on separate pipe descriptors. Fragmented MP4 output uses `-f mp4 -movflags +cmaf -frag_duration MICROSECONDS -flush_packets 1 pipe:1`. RTMP transport and HLS/DASH delivery remain the caller's responsibility.

## Archives

Each version is released as one archive per target: `arm`, `armv7`, `armv8`, `x64`, `windows-x64`, `android-armeabi-v7a`, `android-arm64-v8a` and `android-x86_64`. The `arm` archive is the `armv7` build, following evopeg's existing architecture bundle. Linux archives are named `evovpeg-<version>-<arch>.tar.gz`; Windows and Android archives are `.zip`. Each contains both programs, license texts, `NOTICE`, `build.json`, this README and the MIT `LICENSE` for the recipe.

Releases include signed `SHA256SUMS` and a `manifest.json` mapping target names to archive names and recording each decoder/prober path and SHA-256 digest. `evovpeg-sources-<version>.tar.xz` contains the verified upstream sources and complete build recipe and is covered by the signed checksums. Consumers verify the selected archive and its internal manifest before use.

## Build and Checks

Docker is required. Linux targets are built natively in Debian bookworm; Windows x64 is cross-built with MinGW-w64 and Android targets with the pinned Android NDK 27.2.12479018. The build container has network disabled. Source archives are pinned by URL and SHA-256 in `components/ffmpeg/*.lock` and fetched before the offline build.

```sh
scripts/check.sh       # shell, lock, expected-set and workflow checks
./build.sh             # all Linux, Windows and Android targets
./build.sh x64         # one target
./build.sh windows-x64
./build.sh android-arm64-v8a
```

Linux builds verify architecture, static linkage, component lists, probe/decode, seek, audio output, encode and warning gates. Windows builds verify PE format and Windows-system-only DLL imports, then run the codec suite and HTTP/HTTPS/TLS/frame-parity checks on a native Windows runner. Android builds verify each ABI and platform-only dependencies; CI runs probe/decode parity on an Android x86_64 emulator. Android armv7 throughput remains to be measured before changing the generic byte-swap loop.

## Licences

The recipe and packaging are MIT-licensed. The resulting programs are GPL version 3 or later. x264 is GPL 2-or-later, dav1d is BSD 2-Clause, mbedTLS is used under Apache-2.0, and zlib uses the Zlib license. `licenses/NOTICE` and the license files in every archive identify the included components and terms. Exact upstream source URLs and hashes are in `components/ffmpeg/*.lock`; build instructions and source patches are included in this repository. Non-free components are disabled.

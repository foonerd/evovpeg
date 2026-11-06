# evovpeg

`evovpeg` is the media decoder component of the evo framework. It is a small, purpose-built FFmpeg build for Glass: it probes local files, decodes video to raw frames, and can decode an audio track to raw PCM for Glass's lip-sync calibration. The sound the listener hears continues through MPD.

Both programs are statically linked and have no dynamic loader or shared-library dependencies:

| Program | Purpose |
| --- | --- |
| `bin/evovpeg` | Decode video to raw planar YUV 4:2:0 frames on stdout. |
| `bin/evovprobe` | Report selected audio/video stream properties. |

FFmpeg is built with network protocols and device I/O disabled, and without GPL or non-free components. Only the local `file` and `pipe` protocols are enabled. The build, package and release checks verify the enabled component set and reject ELF interpreters and dynamic dependencies.

## Supported Set

The software decode profile includes H.264, H.265/HEVC, H.266/VVC, MPEG-2, MPEG-4 Part 2, VP8, VP9 and AV1 video, plus AAC, AAC-LATM, AC-3, E-AC-3, DTS, TrueHD, MLP, MP3, MP2, Opus, Vorbis, FLAC, ALAC, WMA v2 and PCM audio. AV1 uses the statically linked dav1d library. Audio decoding is offline and produces PCM; it does not add network protocols or replace MPD's playback path. Supported input containers and elementary streams are recorded in `components/ffmpeg/configure.txt` and checked against the built binary on every target.

ARM builds include upstream V4L2 M2M decoder registrations for H.264, HEVC, MPEG-2, MPEG-4 Part 2, VP8 and VP9 alongside the software decoders. These registrations require a compatible V4L2 M2M device and driver at runtime; the build does not claim hardware execution. x64 remains software-only. VAAPI and V4L2 request API decoders are not included.

## Use

Probe a file:

```sh
evovprobe -v error -select_streams v:0 \\
  -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 FILE
```

Decode from a seek position to a back-pressured pipe:

```sh
evovpeg -nostdin -loglevel error -ss SECONDS -i FILE \\
  -an -sn -f rawvideo -pix_fmt yuv420p -
```

Each frame is `width * height * 3 / 2` bytes. Decoder errors end the output stream; the caller owns playback timing and presentation.

Decode the media's audio track separately for analysis or synchronization:

```sh
evovpeg -nostdin -loglevel error -ss SECONDS -i FILE \
  -vn -sn -ac 1 -ar 8000 -f f32le -
```

This writes mono 8 kHz float PCM to stdout. Glass drains the video and audio invocations independently; MPD remains responsible for audible playback.

## Archives

Each version is released as one archive per Volumio architecture: `arm`, `armv7`, `armv8` and `x64`. The `arm` archive is the `armv7` build, following evopeg's existing architecture bundle. Archives are named `evovpeg-<version>-<arch>.tar.gz` and contain both programs, their license texts, `NOTICE`, `build.json`, this README and the MIT `LICENSE` for the recipe.

Releases include signed `SHA256SUMS` and a `manifest.json` mapping architecture names to archive names. The binaries are not bundled into Glass; Glass fetches and verifies the selected archive when needed.

## Build and Checks

Docker is required. Each target is built natively in Debian bookworm with network disabled inside the build container. Source archives are pinned by URL and SHA-256 in `components/ffmpeg/*.lock` and fetched before the offline build.

```sh
scripts/check.sh       # shell, lock, expected-set and workflow checks
./build.sh             # armv7, armv8 and x64
./build.sh x64         # one target
```

Every target checks both ELF files for architecture and static linkage, compares FFmpeg's component lists against the expected sets, probes and decodes the video smoke clips (including a project-generated VVC vector with exact frame-content checks), decodes AAC audio-bearing variants to mono 8 kHz float PCM and checks output duration, verifies seeking, refuses network input and requires zero compiler warnings.

## Licences

The recipe and packaging are MIT-licensed. The statically linked FFmpeg and dav1d components are distributed under their respective LGPL 2.1-or-later and BSD 2-Clause terms. `licenses/NOTICE` and the license files in every archive identify the included components and terms. FFmpeg is built without GPL and non-free components.

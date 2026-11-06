#!/bin/bash
# Decode and probe every video sample, including the pinned VVC conformance stream.
#
#   smoke.sh DECODER PROBER CLIP_DIR VVC_SAMPLE WORKDIR
set -euo pipefail
bin=$1
probe=$2
clips=$3
vvc_sample=$4
work=$5
rm -rf "$work" && mkdir -p "$work"

run() { timeout 120 "$bin" -hide_banner -loglevel error -nostdin "$@"; }
probe_run() { timeout 120 "$probe" -hide_banner -v error "$@"; }
mean_y() { # decoded file, frame index
  dd if="$1" bs=86400 skip="$2" count=1 status=none \
    | head -c 57600 \
    | od -An -v -tu1 \
    | awk '{ for (i = 1; i <= NF; i++) { sum += $i; count++ } } END { if (count) print int(sum / count); else exit 1 }'
}

for spec in \
  "h264 flash-h264.mp4" \
  "hevc flash-hevc.mp4" \
  "vp9 flash-vp9.webm" \
  "av1 flash-av1.mkv" \
  "mpeg2video flash-mpeg2.ts" \
  "mpeg4 flash-mpeg4.avi"; do
  read -r codec name <<< "$spec"
  input="$clips/$name"
  decoded="$work/$name.yuv"
  metadata=$(probe_run -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$input")
  metadata_rows=$(printf '%s\n' "$metadata" | sed -e 's/,$//' -e '/^$/d' | LC_ALL=C sort -u)
  [[ "$metadata_rows" == "$codec,320,180,30/1" ]] || { echo "WRONG $name probe: $metadata" >&2; exit 1; }
  run -i "$input" -an -sn -frames:v 60 -pix_fmt yuv420p -f rawvideo "$decoded"
  [[ "$(stat -c %s "$decoded")" -eq 5184000 ]] || { echo "WRONG $name frame count or size" >&2; exit 1; }
  for frame in 0 30; do
    [[ "$(mean_y "$decoded" "$frame")" -gt 200 ]] || { echo "WRONG $name frame $frame is not white" >&2; exit 1; }
  done
  for frame in 1 31; do
    [[ "$(mean_y "$decoded" "$frame")" -lt 32 ]] || { echo "WRONG $name frame $frame is not black" >&2; exit 1; }
  done
  run -ss 1 -i "$input" -an -sn -frames:v 1 -pix_fmt yuv420p -f rawvideo - > "$work/seek.yuv"
  [[ "$(mean_y "$work/seek.yuv" 0)" -gt 200 ]] || { echo "WRONG $name seek did not start at the expected frame" >&2; exit 1; }
  echo "  ok    $codec: probed and decoded 60 frames; seek verified"
done

vvc_metadata=$(probe_run -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$vvc_sample")
IFS=, read -r vvc_codec vvc_width vvc_height <<< "$vvc_metadata"
[[ "$vvc_codec" == vvc && "$vvc_width" =~ ^[0-9]+$ && "$vvc_height" =~ ^[0-9]+$ ]] \
  || { echo "WRONG VVC probe: $vvc_metadata" >&2; exit 1; }
run -i "$vvc_sample" -an -sn -frames:v 1 -pix_fmt yuv420p -f rawvideo - > "$work/vvc.yuv"
[[ -s "$work/vvc.yuv" ]] || { echo "WRONG VVC decoder produced no frame" >&2; exit 1; }
echo "  ok    vvc: probed $vvc_width x $vvc_height and decoded a frame"

if run -i http://127.0.0.1:9/unreachable -frames:v 1 -f null - 2> "$work/network.txt"; then
  echo "WRONG network input was not refused" >&2
  exit 1
fi
grep -q 'Protocol not found' "$work/network.txt" || { echo "WRONG network input failed for an unexpected reason" >&2; exit 1; }
echo "  ok    network input refused"

echo "[OK] video decode, probe, seek, and network-isolation checks passed"

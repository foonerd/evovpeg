#!/bin/bash
# Decode and probe every video sample, including the project-generated VVC stream.
#
#   smoke.sh DECODER PROBER CLIP_DIR VVC_SAMPLE WORKDIR TARGET
set -euo pipefail
bin=$1
probe=$2
clips=$3
vvc_sample=$4
work=$5
target=$6
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

for input in "$clips"/audio/*-aac.mkv; do
  name=$(basename "$input")
  codec=$(probe_run -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$input" \
    | sed -e 's/,$//' -e '/^$/d' | head -n1)
  [[ "$codec" == aac ]] || { echo "WRONG $name probe: expected aac, got $codec" >&2; exit 1; }
  sample_rate=$(probe_run -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$input" \
    | sed -e 's/,$//' -e '/^$/d' | head -n1)
  [[ "$sample_rate" =~ ^[0-9]+ ]] \
    || { echo "WRONG $name probe: invalid sample rate" >&2; exit 1; }
  raw="$work/$name.f32le"
  run -ss 0 -i "$input" -vn -sn -ac 1 -ar 8000 -f f32le - > "$raw"
  expected_bytes=64000
  frame_bytes=$(awk -v rate="$sample_rate" 'BEGIN { printf "%d", (1024 * 8000 / rate + 0.999999) * 4 }')
  actual_bytes=$(stat -c %s "$raw")
  delta=$((actual_bytes - expected_bytes))
  if (( delta < 0 )); then delta=$((-delta)); fi
  (( delta <= frame_bytes )) \
    || { echo "WRONG $name PCM length: expected $expected_bytes +/- $frame_bytes, got $actual_bytes" >&2; exit 1; }
  peak=$(od -An -v -t f4 "$raw" \
    | awk '{ for (i = 1; i <= NF; i++) { value = $i < 0 ? -$i : $i; if (value > peak) peak = value } } END { print peak + 0 }')
  awk -v peak="$peak" 'BEGIN { exit !(peak > 0.01) }' \
    || { echo "WRONG $name decoded silence" >&2; exit 1; }
  echo "  ok    $name: AAC to mono 8 kHz float, $actual_bytes bytes"
done

vvc_metadata=$(probe_run -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$vvc_sample")
IFS=, read -r vvc_codec vvc_width vvc_height <<< "$vvc_metadata"
[[ "$vvc_codec" == vvc && "$vvc_width" =~ ^[0-9]+$ && "$vvc_height" =~ ^[0-9]+$ ]] \
  || { echo "WRONG VVC probe: $vvc_metadata" >&2; exit 1; }
run -i "$vvc_sample" -an -sn -frames:v 1 -pix_fmt yuv420p -f rawvideo - > "$work/vvc.yuv"
[[ "$(stat -c %s "$work/vvc.yuv")" -eq 6144 ]] \
  || { echo "WRONG VVC decoder frame size" >&2; exit 1; }
if ! head -c 4096 "$work/vvc.yuv" | od -An -v -tu1 \
  | awk '{ for (i = 1; i <= NF; i++) { if ($i != 128) wrong = 1; count++ } } END { exit !(count == 4096 && !wrong) }'; then
  echo "WRONG VVC decoded luma differs from the synthetic gray frame" >&2
  exit 1
fi
echo "  ok    vvc: probed $vvc_width x $vvc_height and decoded a frame"

m2m_count=$("$bin" -hide_banner -decoders | grep -c 'v4l2m2m' || true)
case "$target" in
  armv7|armv8) expected_m2m=6 ;;
  x64) expected_m2m=0 ;;
  *) echo "error: unknown target '$target'" >&2; exit 2 ;;
esac
[[ "$m2m_count" -eq "$expected_m2m" ]] \
  || { echo "WRONG $target V4L2 M2M decoder count: expected $expected_m2m, got $m2m_count" >&2; exit 1; }
echo "  ok    $target V4L2 M2M decoders: $m2m_count"

if run -protocol_whitelist file,pipe -i http://127.0.0.1:9/unreachable -frames:v 1 -f null - 2> "$work/network.txt"; then
  echo "WRONG network input was not refused" >&2
  exit 1
fi
grep -q 'not on whitelist' "$work/network.txt" || { echo "WRONG network input failed for an unexpected reason" >&2; exit 1; }
echo "  ok    network input refused"

echo "[OK] video/audio decode, probe, seek, and network-isolation checks passed"

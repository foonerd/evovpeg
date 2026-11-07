#!/bin/bash
set -euo pipefail
bin=$1
probe=$2
fixture=$3
fixture_probe="$(dirname "$fixture")/ffprobe"
clips=$4
work=$5
mkdir -p "$work"
run() { timeout 120 "$bin" -nostdin -v error "$@"; }
run -i "$clips/flash-h264.mp4" -an -sn -frames:v 1 -pix_fmt yuv420p -f rawvideo - > "$work/seed.yuv"
for spec in 'png png' 'mjpeg jpg'; do
  read -r codec extension <<< "$spec"
  "$fixture" -nostdin -v error -f rawvideo -pix_fmt yuv420p -video_size 320x180 \
    -i "$work/seed.yuv" -frames:v 1 -c:v "$codec" -f image2 "$work/still.$extension"
done
for geometry in 1280x720 720x1280; do
  dimensions=${geometry/x/:}
  for extension in png jpg; do
    picture="$work/$geometry-$extension.yuv"
    run -i "$work/still.$extension" \
      -vf "scale=$dimensions:force_original_aspect_ratio=decrease,pad=$dimensions:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
      -frames:v 1 -f rawvideo "$picture"
    head -c $((44100 * 5 * 4)) /dev/zero | run \
      -f rawvideo -pix_fmt yuv420p -video_size "$geometry" -framerate 10 -stream_loop -1 -i "$picture" \
      -f s16le -ar 44100 -ac 2 -i pipe:0 -map 0:v:0 -map 1:a:0 -t 5 \
      -c:v libx264 -preset veryfast -tune stillimage -profile:v main \
      -b:v 500k -maxrate 500k -bufsize 1000k -g 20 -keyint_min 20 -sc_threshold 0 \
      -c:a aac -b:a 128k -ar 48000 -f flv -flush_packets 1 pipe:1 > "$work/result.flv"
    metadata=$("$fixture_probe" -v error -select_streams v:0 \
      -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$work/result.flv")
    [[ "$metadata" == "h264,${geometry/x/,},10/1" ]]
    [[ "$("$fixture_probe" -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$work/result.flv")" == 'aac,48000,2' ]]
    "$fixture_probe" -v error -select_streams v:0 -show_frames \
      -show_entries frame=key_frame,best_effort_timestamp_time -of csv=p=0 "$work/result.flv" \
      | awk -F, '$1 == 1 { if (seen && ($2-last < 1.99 || $2-last > 2.01)) exit 1; last=$2; seen++ } END { if (seen < 3) exit 1 }'
    "$fixture" -nostdin -v error -i "$work/result.flv" -map 0:v:0 -an -sn -f rawvideo -pix_fmt yuv420p - \
      | wc -c > "$work/size"
    [[ "$(cat "$work/size")" -eq $((1280 * 720 * 3 / 2 * 50)) ]]
    echo "[OK] $geometry $extension prepared once; H.264/AAC FLV, 50 decoded frames, two-second GOP"
  done
done
run -i "$clips/flash-h264.mp4" -frames:v 60 -pix_fmt rgb24 -f rawvideo "$work/rgb.raw"
head -c $((44100 * 2 * 4)) /dev/zero | run \
  -f rawvideo -pix_fmt rgb24 -video_size 320x180 -framerate 30 -i pipe:3 \
  -f s16le -ar 44100 -ac 2 -i pipe:0 -map 0:v:0 -map 1:a:0 -t 2 \
  -vf format=yuv420p -c:v libx264 -preset veryfast -g 60 -fps_mode passthrough -c:a aac -ar 48000 \
  -f flv pipe:1 3< "$work/rgb.raw" > "$work/pipes.flv"
[[ "$("$fixture_probe" -v error -select_streams v:0 -count_frames \
  -show_entries stream=nb_read_frames -of csv=p=0 "$work/pipes.flv")" -eq 60 ]]
"$fixture" -nostdin -v error -i "$work/pipes.flv" -an -sn -fps_mode passthrough -f rawvideo -pix_fmt yuv420p - | wc -c > "$work/size"
actual=$(cat "$work/size")
[[ "$actual" -eq $((320 * 180 * 3 / 2 * 60)) ]] \
  || { echo "WRONG dual-pipe frame bytes: $actual, expected 5184000" >&2; exit 1; }
run -loop 1 -framerate 10 -i "$work/still.png" -t 5 -an -c:v libx264 \
  -preset veryfast -g 20 -pix_fmt yuv420p -f mp4 -movflags +cmaf -frag_duration 1000000 -flush_packets 1 pipe:1 > "$work/video.mp4"
[[ "$("$probe" -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$work/video.mp4")" == h264 ]]
run -i "$work/video.mp4" -an -sn -f rawvideo -pix_fmt yuv420p - | wc -c > "$work/size"
actual=$(cat "$work/size")
[[ "$actual" -eq $((320 * 180 * 3 / 2 * 50)) ]] \
  || { echo "WRONG video fMP4 frame bytes: $actual, expected 4320000" >&2; exit 1; }
if run -protocol_whitelist file,pipe -i "$work/video.mp4" -c:v copy -f flv \
    rtmp://127.0.0.1:9/blocked > "$work/refused" 2> "$work/refused.err"; then exit 1; fi
grep -q 'Protocol not found' "$work/refused.err"
echo '[OK] raw RGB/audio dual-pipe input, video fMP4 decode and RTMP refusal'
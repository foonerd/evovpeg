#!/bin/bash
set -euo pipefail
target=$1
bin_dir=$2
clip=$3
reference=$4
boot_mode=${5:-}
work=$(mktemp -d)
device_dir=/data/local/tmp/evovpeg
emulator_pid=
cleanup() {
  rm -rf "$work"
  adb shell rm -rf "$device_dir" >/dev/null 2>&1 || true
  if [[ -n "$emulator_pid" ]]; then kill "$emulator_pid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

[[ "$target" == android-x86_64 ]] || { echo "error: no emulator runtime recipe for $target" >&2; exit 2; }
if [[ "$boot_mode" == --boot ]]; then
  printf 'no\n' | avdmanager create avd --name evovpeg-smoke \
    --package 'system-images;android-35;google_apis;x86_64' --force
  emulator -avd evovpeg-smoke -no-window -no-audio -no-boot-anim -no-snapshot \
    -accel off -no-metrics > "$work/emulator.log" 2>&1 &
  emulator_pid=$!
  adb wait-for-device
  zygote=
  surfaceflinger=
  attempt=0
  while [[ "$zygote" != running || "$surfaceflinger" != running ]] \
    && [[ "$attempt" -lt 120 ]]; do
    zygote=$(adb shell getprop init.svc.zygote | tr -d '\r')
    surfaceflinger=$(adb shell getprop init.svc.surfaceflinger | tr -d '\r')
    attempt=$((attempt + 1))
    [[ "$zygote" == running && "$surfaceflinger" == running ]] || sleep 2
  done
  [[ "$zygote" == running && "$surfaceflinger" == running ]] \
    || { cat "$work/emulator.log" >&2; exit 1; }
fi
adb shell mkdir -p "$device_dir"
adb push "$bin_dir/evovpeg" "$device_dir/evovpeg" >/dev/null
adb push "$bin_dir/evovprobe" "$device_dir/evovprobe" >/dev/null
adb push "$clip" "$device_dir/clip.mp4" >/dev/null
adb shell chmod 755 "$device_dir/evovpeg" "$device_dir/evovprobe"

metadata=$(adb shell "$device_dir/evovprobe" -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$device_dir/clip.mp4" | tr -d '\r')
[[ "$metadata" == "h264,320,180,30/1" ]] \
  || { echo "WRONG Android probe: $metadata" >&2; exit 1; }

adb exec-out "$device_dir/evovpeg" -nostdin -v error -threads 1 -i "$device_dir/clip.mp4" \
  -frames:v 60 -an -sn -pix_fmt yuv420p -f rawvideo - > "$work/android.yuv"
cmp "$reference" "$work/android.yuv"
echo "[OK] $target Android probe and 60-frame parity with Linux x64"
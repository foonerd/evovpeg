#!/bin/bash
# The proof that the binary carries the set and nothing else: what it answers to
# -encoders, -decoders, -muxers, -demuxers, -protocols, -filters, -bsfs and -hwaccels,
# compared line for line with components/ffmpeg/expected/<list>.txt; that every flag of
# configure.txt is in its build configuration; that it names evovpeg's version and
# FFmpeg's. Runs where the binary runs (in the build container, or on a player).
#
#   verify-set.sh BINARY [REPOSITORY]     REPOSITORY defaults to the script's own
set -euo pipefail
bin=$1
root=${2:-$(cd "$(dirname "$0")/.." && pwd)}
probe=${3:-}
expected="$root/components/ffmpeg/expected"
[ -x "$bin" ] || { echo "verify-set: $bin is not an executable" >&2; exit 2; }
[ -d "$expected" ] || { echo "verify-set: no expected lists at $expected" >&2; exit 2; }

# The component names of one listing, one a line, sorted as the expected files are.
names() {
  case "$1" in
    encoders|decoders)
      "$bin" -hide_banner "-$1" | sed -n '/^ *-\{3,\}/,$p' | tail -n +2 | awk 'NF >= 2 {print $2}' ;;
    muxers|demuxers)
      "$bin" -hide_banner "-$1" | sed -n '/^ *--/,$p' | tail -n +2 | awk 'NF >= 2 {print $2}' ;;
    filters)
      "$bin" -hide_banner -filters | sed -n '/^ *-\{3,\}/,$p' | tail -n +2 | awk 'NF >= 2 {print $2}' ;;
    bsfs)
      "$bin" -hide_banner -bsfs | sed -n '/^Bitstream filters:/,$p' | tail -n +2 | awk 'NF {print $1}' ;;
    hwaccels)
      "$bin" -hide_banner -hwaccels | sed -n '/^Hardware acceleration methods:/,$p' | tail -n +2 | awk 'NF {print $1}' ;;
    protocols)
      "$bin" -hide_banner -protocols | awk '/^Input:/ {d="in"; next} /^Output:/ {d="out"; next} d != "" && NF {print d ":" $1}' ;;
  esac | LC_ALL=C sort -u
}

fail=0
for list in encoders decoders muxers demuxers protocols filters bsfs hwaccels; do
  [ -f "$expected/$list.txt" ] || { echo "verify-set: no $expected/$list.txt" >&2; exit 2; }
  if diff -u "$expected/$list.txt" <(names "$list") > /tmp/verify-set.diff; then
    echo "  ok    $list: $(grep -c . "$expected/$list.txt") as expected"
  else
    echo "  WRONG $list: the binary differs from $expected/$list.txt (- expected, + the binary):"
    grep -E '^[-+][^-+]' /tmp/verify-set.diff | sed 's/^/        /'
    fail=1
  fi
done

# Every flag of the set is in the binary's own account of its build (which quotes a
# flag's list of names; the quotes are dropped for the comparison).
buildconf=$("$bin" -hide_banner -buildconf | tr -d "'")
while IFS= read -r flag; do
  if ! grep -qF -- "$flag" <<< "$buildconf"; then
    echo "  WRONG build configuration: $flag is not in it"
    fail=1
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$root/components/ffmpeg/configure.txt")
for forbidden in --enable-gpl --enable-nonfree --enable-network --enable-avdevice; do
  if grep -qF -- "$forbidden" <<< "$buildconf"; then
    echo "  WRONG build configuration: $forbidden is in it"
    fail=1
  fi
done

# It names evovpeg's version and FFmpeg's.
version=$(cat "$root/VERSION")
ffmpeg=$(sed -n 's/^VERSION=//p' "$root/components/ffmpeg/ffmpeg.lock")
first=$("$bin" -version | head -n1)
if [[ "$first" == "ffmpeg version $ffmpeg-evovpeg-$version "* ]]; then
  echo "  ok    version: $first"
else
  echo "  WRONG version: '$first' does not begin with 'ffmpeg version $ffmpeg-evovpeg-$version'"
  fail=1
fi

if [[ -n "$probe" ]]; then
  probe_first=$("$probe" -version | head -n1)
  if [[ "$probe_first" == "ffprobe version $ffmpeg-evovpeg-$version "* ]]; then
    echo "  ok    probe version: $probe_first"
  else
    echo "  WRONG probe version: '$probe_first' does not begin with 'ffprobe version $ffmpeg-evovpeg-$version'"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "error: $bin does not carry the set exactly" >&2
  exit 1
fi
echo "[OK] $bin carries the set and nothing else"

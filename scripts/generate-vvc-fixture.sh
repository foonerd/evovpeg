#!/bin/bash
set -euo pipefail
vvencapp=${1:?usage: generate-vvc-fixture.sh /path/to/vvencapp-1.14.0}
root=$(cd "$(dirname "$0")/.." && pwd)
output="$root/tests/clips/vvc-synthetic.266"
version=$("$vvencapp" --version 2>&1)
grep -qF 'version 1.14.0' <<< "$version" \
  || { echo "error: fixture generation requires VVenC 1.14.0" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dd if=/dev/zero bs=6144 count=1 status=none | tr '\000' '\200' > "$work/frame.yuv"
"$vvencapp" --preset faster -i "$work/frame.yuv" -s 64x64 --fps 1/1 \
  -f 1 -q 45 --qpa 0 -t 1 --mtprofile 0 -rt idr -o "$work/vvc-synthetic.266"
install -m 644 "$work/vvc-synthetic.266" "$output"
sha256sum "$output"
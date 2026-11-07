#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dist=${1:-$root/dist}
version=$(cat "$root/VERSION")
mkdir -p "$dist"
dist=$(cd "$dist" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
top="evovpeg-sources-$version"
mkdir -p "$work/$top/upstream" "$work/$top/recipe"
for lock in "$root"/components/ffmpeg/*.lock; do
  filename=$(basename "$(sed -n 's/^URL=//p' "$lock")")
  source="$root/.cache/src/$filename"
  sha=$(sed -n 's/^SHA256=//p' "$lock")
  [[ -f "$source" ]] || { echo "missing $source; run scripts/fetch-sources.sh" >&2; exit 1; }
  printf '%s  %s\n' "$sha" "$source" | sha256sum -c --quiet
  cp "$source" "$work/$top/upstream/"
done
cp -a "$root/components" "$root/scripts" "$root/docker" "$root/.github" \
  "$root/tests" "$root/keys" "$work/$top/recipe/"
cp "$root/build.sh" "$root/VERSION" "$root/README.md" "$root/LICENSE" \
  "$root/CHANGELOG.md" "$work/$top/recipe/"
tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' \
  -cJf "$dist/$top.tar.xz" "$top"
echo "[OK] $dist/$top.tar.xz contains verified upstream sources and the complete recipe"
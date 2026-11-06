#!/bin/bash
# The release's archives: dist/evovpeg-<version>-<arch>.tar.gz for arm, armv7, armv8 and
# x64 (arm from the armv7 build), each unpacking to evovpeg-<version>-<arch>/ with
# bin/evovpeg, bin/evovprobe, licenses/, build.json, README.md and LICENSE. Every file is checked against
# the digest build.json recorded for it, so a build that came through a workflow's
# artifact store is the build that was proven.
#
#   scripts/package.sh [--from <dir>]     <dir> holds the <target>/ trees (default: out)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/targets.sh

from="out"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) from="$2"; shift 2 ;;
    *) echo "error: unknown option '$1'" >&2; exit 1 ;;
  esac
done
version=$(cat VERSION)

for t in $TARGETS; do
  for f in bin/evovpeg bin/evovprobe licenses/NOTICE build.json; do
    [[ -f "$from/$t/$f" ]] || { echo "error: $from/$t/$f is missing; build target '$t' first" >&2; exit 1; }
  done
  # Each file as build.json has it.
  while IFS= read -r -d '' f; do
    rel="${f#"$from/$t"/}"
    want=$(sed -n "s|^ *\"$rel\": { \"sha256\": \"\([0-9a-f]*\)\".*|\1|p" "$from/$t/build.json")
    [[ -n "$want" ]] || { echo "error: $t: $rel is not in build.json" >&2; exit 1; }
    have=$(sha256sum "$f" | cut -d' ' -f1)
    [[ "$have" == "$want" ]] || { echo "error: $t: $rel is not the file build.json names (digest differs)" >&2; exit 1; }
  done < <(find "$from/$t" -type f ! -name build.json ! -name build.log -print0)
done

rm -rf dist && mkdir -p dist
for arch in $ARCHIVES; do
  t=$(archive_source "$arch")
  top="evovpeg-$version-$arch"
  rm -rf "dist/$top" && mkdir -p "dist/$top/bin" "dist/$top/licenses"
  install -m 755 "$from/$t/bin/evovpeg" "dist/$top/bin/evovpeg"
  install -m 755 "$from/$t/bin/evovprobe" "dist/$top/bin/evovprobe"
  install -m 644 "$from/$t"/licenses/* "dist/$top/licenses/"
  install -m 644 "$from/$t/build.json" README.md LICENSE "dist/$top/"
  tar -C dist --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' -czf "dist/$top.tar.gz" "$top"
  rm -rf "dist/$top"
  echo "[OK] dist/$top.tar.gz: $(stat -c %s "dist/$top.tar.gz") bytes (from $t)"
done

{
  echo "{"
  echo '  "name": "evovpeg",'
  printf '  "version": "%s",\n' "$version"
  echo '  "assets": {'
  first=1
  for arch in $ARCHIVES; do
    [ "$first" -eq 1 ] || echo ","
    first=0
    printf '    "%s": "%s"' "$arch" "evovpeg-$version-$arch.tar.gz"
  done
  echo
  echo "  }"
  echo "}"
} > dist/manifest.json
echo "[OK] dist/manifest.json"

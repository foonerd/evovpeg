#!/bin/bash
# Write out/<target>/build.json: evovpeg's version, the target, the commit, every source
# with its version, URL, digest and licence, the configure set, and every file with its
# digest and size. Runs on the host after a build.
#
#   write-manifest.sh <target>
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
out="$root/out/$target"
[ -x "$out/bin/evovpeg" ] || { echo "error: $out/bin/evovpeg is missing" >&2; exit 1; }

json_string() { printf '"%s"' "$(printf '%s' "$1" | sed 's/["\\]/\\&/g')"; }

{
  echo "{"
  echo "  \"evovpeg\": $(json_string "$(cat "$root/VERSION")"),"
  echo "  \"target\": $(json_string "$target"),"
  echo "  \"built\": $(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),"
  echo "  \"repository\": {"
  echo "    \"commit\": $(json_string "$(git -C "$root" rev-parse --verify -q HEAD 2>/dev/null || echo unknown)"),"
  echo "    \"describe\": $(json_string "$(git -C "$root" describe --tags --always --dirty 2>/dev/null || echo unknown)")"
  echo "  },"
  echo "  \"sources\": {"
  first=1
  for lock in "$root"/components/*/*.lock; do
    [ "$first" -eq 1 ] || echo ","
    first=0
    printf '    %s: {\n' "$(json_string "$(sed -n 's/^NAME=//p' "$lock")")"
    printf '      "version": %s,\n' "$(json_string "$(sed -n 's/^VERSION=//p' "$lock")")"
    printf '      "url": %s,\n' "$(json_string "$(sed -n 's/^URL=//p' "$lock")")"
    printf '      "sha256": %s,\n' "$(json_string "$(sed -n 's/^SHA256=//p' "$lock")")"
    printf '      "license": %s\n' "$(json_string "$(sed -n 's/^LICENSE=//p' "$lock")")"
    printf '    }'
  done
  echo
  echo "  },"
  echo "  \"patches\": {"
  echo "    \"ffmpeg\": {"
  echo "      \"file\": \"components/ffmpeg/0001-fix-decoder-build-warnings.patch\","
  echo "      \"sha256\": \"$(sha256sum "$root/components/ffmpeg/0001-fix-decoder-build-warnings.patch" | cut -d' ' -f1)\""
  echo "    }"
  echo "  },"
  echo "  \"configure\": ["
  first=1
  while IFS= read -r flag; do
    [ "$first" -eq 1 ] || echo ","
    first=0
    printf '    %s' "$(json_string "$flag")"
  done < <(grep -vE '^[[:space:]]*(#|$)' "$root/components/ffmpeg/configure.txt")
  echo
  echo "  ],"
  echo "  \"files\": {"
  first=1
  while IFS= read -r -d '' f; do
    rel="${f#"$out"/}"
    [ "$first" -eq 1 ] || echo ","
    first=0
    printf '    %s: { "sha256": "%s", "size": %s }' "$(json_string "$rel")" "$(sha256sum "$f" | cut -d' ' -f1)" "$(stat -c %s "$f")"
  done < <(find "$out" -type f ! -name build.json ! -name build.log -print0 | LC_ALL=C sort -z)
  echo
  echo "  }"
  echo "}"
} > "$out/build.json"
echo "[OK] $out/build.json: $(grep -c '"sha256"' "$out/build.json") entries"

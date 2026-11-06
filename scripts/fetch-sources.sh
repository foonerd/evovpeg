#!/bin/bash
# Fetch every upstream tarball named by a lock file into .cache/src/, and refuse any whose
# digest is not the lock's. Runs on the host, and only when a build image has to be made:
# the image carries the tarballs, and the build itself is offline.
#
# A lock file (components/<component>/<name>.lock) holds, one a line:
#   NAME=<name>  VERSION=<the release>  URL=<the tarball>  SHA256=<its digest>
#   LICENSE=<its licence, an SPDX identifier>
set -euo pipefail
cd "$(dirname "$0")/.."

cache=".cache/src"
mkdir -p "$cache"

for lock in components/*/*.lock; do
  # Read as text, never sourced: a lock file is data.
  name=$(sed -n 's/^NAME=//p' "$lock")
  url=$(sed -n 's/^URL=//p' "$lock")
  sha=$(sed -n 's/^SHA256=//p' "$lock")
  version=$(sed -n 's/^VERSION=//p' "$lock")
  if [[ -z "$name" || -z "$url" || -z "$version" || ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: $lock needs NAME, VERSION, URL and a SHA256 of 64 hex digits" >&2
    exit 1
  fi
  file="$cache/$(basename "$url")"
  if [[ -f "$file" ]] && echo "$sha  $file" | sha256sum -c --quiet - 2>/dev/null; then
    echo "[=] $name $version: $(basename "$file")"
    continue
  fi
  echo "[+] $name $version: fetching $url"
  rm -f "$file"
  # Every error class is retried: a mirror's TLS reset is as passing as a timeout.
  curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors -o "$file.part" "$url"
  if ! echo "$sha  $file.part" | sha256sum -c --quiet -; then
    echo "error: $name: $(basename "$file") is not the file the lock names (digest differs)" >&2
    rm -f "$file.part"
    exit 1
  fi
  mv "$file.part" "$file"
done

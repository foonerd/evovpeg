#!/bin/bash
# The workshop pass CI runs: the scripts through shellcheck, the lock files well formed,
# VERSION and the changelog in step, the expected lists sorted and unique, no python
# anywhere, the workflows through actionlint. Run before every commit.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "check: shellcheck"
shellcheck -x -S warning build.sh scripts/*.sh components/ffmpeg/build.sh

echo "check: lock files"
for lock in components/*/*.lock; do
  for key in NAME VERSION URL SHA256 LICENSE; do
    grep -qE "^$key=.+" "$lock" || { echo "$lock: no $key" >&2; exit 1; }
  done
  grep -qE '^SHA256=[0-9a-f]{64}$' "$lock" || { echo "$lock: SHA256 is not 64 hex digits" >&2; exit 1; }
  grep -qE '^URL=https://' "$lock" || { echo "$lock: URL is not https" >&2; exit 1; }
done

echo "check: version and changelog"
version=$(cat VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION '$version' is not major.minor.patch" >&2; exit 1; }
scripts/release-notes.sh "$version" | grep -q . || { echo "CHANGELOG.md has no section for $version" >&2; exit 1; }

echo "check: expected lists"
for list in components/ffmpeg/expected/*.txt; do
  if ! diff -q "$list" <(LC_ALL=C sort -u "$list") > /dev/null; then
    echo "$list is not sorted and unique (LC_ALL=C sort -u)" >&2; exit 1
  fi
done

echo "check: no python"
if grep -rIl --exclude-dir=.git --exclude-dir=out --exclude-dir=dist --exclude-dir=.cache -E '^#!.*python|\bpython3?\b' . | grep -v '^./scripts/check.sh$'; then
  echo "python is not used here" >&2; exit 1
fi

echo "check: actionlint"
if command -v actionlint > /dev/null; then
  actionlint -no-color .github/workflows/*.yml
elif command -v docker > /dev/null; then
  docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest -no-color .github/workflows/ci.yml .github/workflows/release.yml
else
  echo "check: neither actionlint nor docker is here; the workflows were not linted" >&2
  exit 1
fi

echo "[OK] check"

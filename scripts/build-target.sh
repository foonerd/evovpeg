#!/bin/bash
# Build evovpeg for one target. Runs in the build container, started by build.sh: the
# repository is mounted read-only at /src, the target's output directory at /out, the
# upstream tarballs are in the image at /opt/src, and there is no network.
set -euo pipefail
. /src/scripts/targets.sh

: "${TARGET:?TARGET is not set}"
export TARGET
export SRC_CACHE=/opt/src
export WORK=/tmp/work
export OUT=/out
TARGET_CFLAGS="$(target_cflags "$TARGET")"
TARGET_ARCH="$(target_arch "$TARGET")"
TARGET_TRIPLET="$(target_triplet "$TARGET")"
EVOVPEG_VERSION="$(cat /src/VERSION)"
export TARGET_CFLAGS TARGET_ARCH TARGET_TRIPLET EVOVPEG_VERSION

rm -rf "${OUT:?}/bin" "${OUT:?}/licenses" "${OUT:?}/build.json"
mkdir -p "$WORK" "$OUT"
trap 'chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"' EXIT

echo "=== $TARGET: $(uname -m), gcc $(gcc -dumpversion), glibc $(ldd --version | head -n1 | awk '{print $NF}'), flags: ${TARGET_CFLAGS:-none} ==="

bash /src/components/ffmpeg/build.sh

echo "=== $TARGET: checking what was built ==="
bash /src/scripts/check-elf.sh "$TARGET" "$OUT/bin"
bash /src/scripts/verify-set.sh "$OUT/bin/evovpeg" /src "$OUT/bin/evovprobe"
bash /src/scripts/smoke.sh "$OUT/bin/evovpeg" "$OUT/bin/evovprobe" \
	/src/tests/clips "$SRC_CACHE/CodingToolsSets_A_2.bit" "$WORK/smoke"
echo "[OK] $TARGET built: bin/evovpeg $(stat -c %s "$OUT/bin/evovpeg") bytes; bin/evovprobe $(stat -c %s "$OUT/bin/evovprobe") bytes"

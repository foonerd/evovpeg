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
case "$TARGET" in
	windows-x64)
		export CC=x86_64-w64-mingw32-gcc
		export AR=x86_64-w64-mingw32-ar
		export NM=x86_64-w64-mingw32-nm
		export RANLIB=x86_64-w64-mingw32-ranlib
		export STRIP=x86_64-w64-mingw32-strip
		;;
	android-*)
		toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
		api="$(target_android_api "$TARGET")"
		ANDROID_ABI="$(target_android_abi "$TARGET")"
		export ANDROID_ABI
		export ANDROID_PLATFORM="android-$api"
		export CC="$toolchain/$TARGET_TRIPLET$api-clang"
		export AR="$toolchain/llvm-ar"
		export NM="$toolchain/llvm-nm"
		export RANLIB="$toolchain/llvm-ranlib"
		export STRIP="$toolchain/llvm-strip"
		;;
	*)
		export CC=gcc AR=ar NM=nm RANLIB=ranlib STRIP=strip
		;;
esac
export TARGET_CFLAGS TARGET_ARCH TARGET_TRIPLET EVOVPEG_VERSION

rm -rf "${OUT:?}/bin" "${OUT:?}/licenses" "${OUT:?}/build.json"
mkdir -p "$WORK" "$OUT"
trap 'chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"' EXIT

echo "=== $TARGET: $(uname -m), gcc $(gcc -dumpversion), glibc $(ldd --version | head -n1 | awk '{print $NF}'), flags: ${TARGET_CFLAGS:-none} ==="

bash /src/components/ffmpeg/build.sh

echo "=== $TARGET: checking what was built ==="
bash /src/scripts/check-elf.sh "$TARGET" "$OUT/bin"
if [[ "$TARGET" == windows-x64 || "$TARGET" == android-* ]]; then
	echo "[OK] $TARGET cross-build complete; runtime checks run on the native platform"
else
	bash /src/scripts/verify-set.sh "$OUT/bin/evovpeg" /src "$OUT/bin/evovprobe" "$TARGET"
	bash /src/scripts/smoke.sh "$OUT/bin/evovpeg" "$OUT/bin/evovprobe" \
		/src/tests/clips /src/tests/clips/vvc-synthetic.266 "$WORK/smoke" "$TARGET"
	echo "[OK] $TARGET built: bin/evovpeg $(stat -c %s "$OUT/bin/evovpeg") bytes; bin/evovprobe $(stat -c %s "$OUT/bin/evovprobe") bytes"
fi

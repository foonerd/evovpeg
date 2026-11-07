#!/bin/bash
# The recipe: dav1d and FFmpeg are built and linked static, with FFmpeg configured down
# to the set in configure.txt. The ffmpeg and ffprobe programs are installed under the
# evovpeg names beside every included licence. There is no network: each source is in the
# image at the digest its lock names.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../scripts/targets.sh"

prefix="$WORK/prefix"
rm -rf "$WORK/src" "$prefix" "$WORK/ffmpeg-install"
mkdir -p "$WORK/src" "$prefix" "$OUT/bin" "$OUT/licenses"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
export CC=gcc
jobs=$(nproc)

# A lock's tarball unpacked under $WORK/src/<name>; prints the directory.
unpack() {
  local name=$1 file
  file="$SRC_CACHE/$(basename "$(sed -n 's/^URL=//p' "$here/$name.lock")")"
  [ -f "$file" ] || { echo "error: $file is not in the image; scripts/fetch-sources.sh fetches it" >&2; exit 1; }
  rm -rf "$WORK/src/$name" && mkdir -p "$WORK/src/$name"
  tar -xf "$file" -C "$WORK/src/$name" --strip-components=1
  echo "$WORK/src/$name"
}
version_of() { sed -n 's/^VERSION=//p' "$here/$1.lock"; }

# Which machine the libraries' configure scripts build for is the target's to say, not
# the building machine's: a 32-bit container on a 64-bit ARM runner would otherwise be
# told "aarch64". build and host the same, so nothing is treated as a cross build.
export CFLAGS="$TARGET_CFLAGS -O2 -ffunction-sections -fdata-sections"

echo "[+] dav1d $(version_of dav1d)"
dir=$(unpack dav1d)
meson setup "$dir/build" "$dir" --prefix="$prefix" --libdir=lib \
  --buildtype=release --default-library=static \
  -Denable_tools=false -Denable_tests=false -Denable_docs=false
ninja -C "$dir/build" -j"$jobs"
ninja -C "$dir/build" install

echo "[+] zlib $(version_of zlib)"
dir=$(unpack zlib)
(
  cd "$dir"
  ./configure --prefix="$prefix" --static
  make -j"$jobs"
  make install
)
echo "[+] mbedtls $(version_of mbedtls)"
dir=$(unpack mbedtls)
cmake -S "$dir" -B "$dir/build" -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$CFLAGS" \
  -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
cmake --build "$dir/build" --parallel "$jobs"
cmake --install "$dir/build"

echo "[+] x264 $(version_of x264)"
dir=$(unpack x264)
patch -d "$dir" -p1 < "$here/x264-build-warnings.patch"
(
  cd "$dir"
  ./configure --prefix="$prefix" --host="$TARGET_TRIPLET" --enable-static \
    --disable-cli --disable-opencl --disable-lavf --disable-swscale \
    --bit-depth=8 --chroma-format=420
  make -j"$jobs"
  make install
)

# Only static libraries are kept, so FFmpeg cannot link runtime dependencies.
find "$prefix/lib" -name '*.so*' -delete

echo "[+] ffmpeg $(version_of ffmpeg)"
dir=$(unpack ffmpeg)
patch -d "$dir" -p1 < "$here/0001-fix-decoder-build-warnings.patch"
mapfile -t flags < <(
  grep -vE '^[[:space:]]*(#|$)' "$here/configure.txt"
  target_configure_flags "$TARGET"
)
(
  cd "$dir"
  ./configure --prefix="$WORK/ffmpeg-install" --arch="$TARGET_ARCH" \
    --extra-version="evovpeg-$EVOVPEG_VERSION" \
    --extra-cflags="$TARGET_CFLAGS -isystem $prefix/include" \
    --extra-ldflags="-L$prefix/lib -static -Wl,--gc-sections" \
    "${flags[@]}"
  make -j"$jobs"
  make install
)
install -m 755 "$WORK/ffmpeg-install/bin/ffmpeg" "$OUT/bin/evovpeg"
install -m 755 "$WORK/ffmpeg-install/bin/ffprobe" "$OUT/bin/evovprobe"
strip "$OUT/bin/evovpeg" "$OUT/bin/evovprobe"

make -C "$WORK/src/ffmpeg" distclean
mkdir -p "$WORK/fixture-build"
(
  cd "$WORK/fixture-build"
  "$WORK/src/ffmpeg/configure" --arch="$TARGET_ARCH" \
    --extra-cflags="$TARGET_CFLAGS -isystem $prefix/include" \
    --extra-ldflags="-L$prefix/lib -static" --disable-everything \
    --disable-autodetect --disable-network --disable-doc --disable-programs \
    --disable-avdevice --disable-debug --enable-ffmpeg --enable-ffprobe --enable-zlib \
    --enable-protocol=file,pipe --enable-demuxer=rawvideo,flv --enable-decoder=rawvideo,h264,aac \
    --enable-encoder=png,mjpeg,rawvideo --enable-muxer=image2,image2pipe,rawvideo --enable-filter=scale --enable-swscale \
    --pkg-config-flags=--static
  make -j"$jobs" ffmpeg ffprobe
)
bash "$here/../../scripts/encode-smoke.sh" "$OUT/bin/evovpeg" \
  "$OUT/bin/evovprobe" "$WORK/fixture-build/ffmpeg" /src/tests/clips "$WORK/encode-smoke"

# The licences of everything in the binary travel with it.
install -m 644 "$WORK/src/ffmpeg/LICENSE.md" "$OUT/licenses/ffmpeg-LICENSE.md"
install -m 644 "$WORK/src/ffmpeg/COPYING.LGPLv2.1" "$OUT/licenses/ffmpeg-COPYING.LGPLv2.1"
install -m 644 "$WORK/src/ffmpeg/COPYING.GPLv3" "$OUT/licenses/ffmpeg-COPYING.GPLv3"
install -m 644 "$WORK/src/dav1d/COPYING" "$OUT/licenses/dav1d-COPYING"
install -m 644 "$WORK/src/x264/COPYING" "$OUT/licenses/x264-COPYING"
install -m 644 "$WORK/src/mbedtls/LICENSE" "$OUT/licenses/mbedtls-LICENSE"
install -m 644 "$WORK/src/zlib/LICENSE" "$OUT/licenses/zlib-LICENSE"
install -m 644 "$here/NOTICE" "$OUT/licenses/NOTICE"

echo "[OK] ffmpeg: bin/evovpeg $(stat -c %s "$OUT/bin/evovpeg") bytes"
echo "[OK] ffprobe: bin/evovprobe $(stat -c %s "$OUT/bin/evovprobe") bytes"

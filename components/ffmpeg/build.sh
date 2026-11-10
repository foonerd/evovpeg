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
export CC="${CC:-gcc}" AR="${AR:-ar}" NM="${NM:-nm}" RANLIB="${RANLIB:-ranlib}" STRIP="${STRIP:-strip}"
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

meson_args=()
case "$TARGET" in
  windows-x64) meson_system=windows; meson_cpu_family=x86_64; meson_cpu=x86_64 ;;
  android-armeabi-v7a) meson_system=android; meson_cpu_family=arm; meson_cpu=armv7 ;;
  android-arm64-v8a) meson_system=android; meson_cpu_family=aarch64; meson_cpu=aarch64 ;;
  android-x86_64) meson_system=android; meson_cpu_family=x86_64; meson_cpu=x86_64 ;;
esac
if [[ -n "${meson_system:-}" ]]; then
  {
    printf '[binaries]\nc = %s\nar = %s\nstrip = %s\npkgconfig = %s\n' \
      "'$(command -v "$CC")'" "'$(command -v "$AR")'" \
      "'$(command -v "$STRIP")'" "'$(command -v pkg-config)'"
    printf '[host_machine]\nsystem = %s\ncpu_family = %s\ncpu = %s\nendian = %s\n' \
      "'$meson_system'" "'$meson_cpu_family'" "'$meson_cpu'" "'little'"
    echo '[properties]'
    echo 'needs_exe_wrapper = true'
  } > "$WORK/meson-cross.ini"
  meson_args=(--cross-file "$WORK/meson-cross.ini")
fi

# Which machine the libraries' configure scripts build for is the target's to say, not
# the building machine's: a 32-bit container on a 64-bit ARM runner would otherwise be
# told "aarch64". build and host the same, so nothing is treated as a cross build.
export CFLAGS="$TARGET_CFLAGS -O2 -ffunction-sections -fdata-sections"

echo "[+] dav1d $(version_of dav1d)"
dir=$(unpack dav1d)
meson setup "$dir/build" "$dir" --prefix="$prefix" --libdir=lib \
  --buildtype=release --default-library=static "${meson_args[@]}" \
  -Denable_tools=false -Denable_tests=false -Denable_docs=false
ninja -C "$dir/build" -j"$jobs"
ninja -C "$dir/build" install

echo "[+] zlib $(version_of zlib)"
dir=$(unpack zlib)
(
  cd "$dir"
  if [[ "$TARGET" == windows-x64 || "$TARGET" == android-* ]]; then
    CHOST="$TARGET_TRIPLET" ./configure --prefix="$prefix" --static
  else
    ./configure --prefix="$prefix" --static
  fi
  make -j"$jobs"
  make install
)
echo "[+] mbedtls $(version_of mbedtls)"
dir=$(unpack mbedtls)
cmake_args=()
case "$TARGET" in
  windows-x64)
    cmake_args+=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_AR="$(command -v "$AR")" -DCMAKE_RANLIB="$(command -v "$RANLIB")" \
      -DCMAKE_RC_COMPILER="$(command -v x86_64-w64-mingw32-windres)")
    ;;
  android-*)
    cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$ANDROID_ABI" -DANDROID_PLATFORM="$ANDROID_PLATFORM")
    ;;
esac
cmake -S "$dir" -B "$dir/build" -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$CFLAGS" \
  -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF "${cmake_args[@]}"
cmake --build "$dir/build" --parallel "$jobs"
cmake --install "$dir/build"

echo "[+] x264 $(version_of x264)"
dir=$(unpack x264)
patch -d "$dir" -p1 < "$here/x264-build-warnings.patch"
x264_flags=()
x264_strip="$STRIP"
case "$TARGET" in
  android-*)
    x264_flags+=(--enable-pic)
    x264_strip=true
    ;;
esac
(
  cd "$dir"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$x264_strip" \
    ./configure --prefix="$prefix" --host="$TARGET_TRIPLET" --enable-static \
    --disable-cli --disable-opencl --disable-lavf --disable-swscale \
    --bit-depth=8 --chroma-format=420 "${x264_flags[@]}"
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
binary_suffix=$(target_binary_suffix "$TARGET")
extra_ldflags="-L$prefix/lib -static -Wl,--gc-sections"
configure_tools=()
case "$TARGET" in
  windows-x64)
    configure_tools+=(--cc="$CC" --ar="$AR" --nm="$NM" --ranlib="$RANLIB" --strip="$STRIP" \
      --pkg-config=pkg-config --extra-libs="-lws2_32 -lbcrypt")
    ;;
  android-*)
    extra_ldflags="-L$prefix/lib -Wl,--gc-sections"
    configure_tools+=(--cc="$CC" --ar="$AR" --nm="$NM" --ranlib="$RANLIB" --strip="$STRIP" \
      --sysroot="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot")
    ;;
esac
(
  cd "$dir"
  if ! ./configure --prefix="$WORK/ffmpeg-install" --arch="$TARGET_ARCH" \
    --extra-version="evovpeg-$EVOVPEG_VERSION" \
    --extra-cflags="$TARGET_CFLAGS -isystem $prefix/include" \
    --extra-ldflags="$extra_ldflags" "${configure_tools[@]}" \
    "${flags[@]}"; then
    grep -n -i -C 4 -E 'mbedtls|error:|failed' ffbuild/config.log | tail -n 100 >&2 || true
    exit 1
  fi
  make --output-sync=target -j"$jobs"
  make install
)
install -m 755 "$WORK/ffmpeg-install/bin/ffmpeg$binary_suffix" "$OUT/bin/evovpeg$binary_suffix"
install -m 755 "$WORK/ffmpeg-install/bin/ffprobe$binary_suffix" "$OUT/bin/evovprobe$binary_suffix"
"$STRIP" "$OUT/bin/evovpeg$binary_suffix" "$OUT/bin/evovprobe$binary_suffix"

if [[ "$TARGET" != windows-x64 && "$TARGET" != android-* ]]; then
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
    make --output-sync=target -j"$jobs" ffmpeg ffprobe
  )
  bash "$here/../../scripts/encode-smoke.sh" "$OUT/bin/evovpeg" \
    "$OUT/bin/evovprobe" "$WORK/fixture-build/ffmpeg" /src/tests/clips "$WORK/encode-smoke"
fi

# The licences of everything in the binary travel with it.
install -m 644 "$WORK/src/ffmpeg/LICENSE.md" "$OUT/licenses/ffmpeg-LICENSE.md"
install -m 644 "$WORK/src/ffmpeg/COPYING.LGPLv2.1" "$OUT/licenses/ffmpeg-COPYING.LGPLv2.1"
install -m 644 "$WORK/src/ffmpeg/COPYING.GPLv3" "$OUT/licenses/ffmpeg-COPYING.GPLv3"
install -m 644 "$WORK/src/dav1d/COPYING" "$OUT/licenses/dav1d-COPYING"
install -m 644 "$WORK/src/x264/COPYING" "$OUT/licenses/x264-COPYING"
install -m 644 "$WORK/src/mbedtls/LICENSE" "$OUT/licenses/mbedtls-LICENSE"
install -m 644 "$WORK/src/zlib/LICENSE" "$OUT/licenses/zlib-LICENSE"
install -m 644 "$here/NOTICE" "$OUT/licenses/NOTICE"

echo "[OK] ffmpeg: bin/evovpeg$binary_suffix $(stat -c %s "$OUT/bin/evovpeg$binary_suffix") bytes"
echo "[OK] ffprobe: bin/evovprobe$binary_suffix $(stat -c %s "$OUT/bin/evovprobe$binary_suffix") bytes"

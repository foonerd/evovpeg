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
export CFLAGS="$TARGET_CFLAGS -O2"

echo "[+] dav1d $(version_of dav1d)"
dir=$(unpack dav1d)
meson setup "$dir/build" "$dir" --prefix="$prefix" --libdir=lib \
  --buildtype=release --default-library=static \
  -Denable_tools=false -Denable_tests=false -Denable_docs=false
ninja -C "$dir/build" -j"$jobs"
ninja -C "$dir/build" install

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
    --extra-cflags="$TARGET_CFLAGS -I$prefix/include" \
    --extra-ldflags="-L$prefix/lib -static" \
    "${flags[@]}"
  make -j"$jobs"
  make install
)
install -m 755 "$WORK/ffmpeg-install/bin/ffmpeg" "$OUT/bin/evovpeg"
install -m 755 "$WORK/ffmpeg-install/bin/ffprobe" "$OUT/bin/evovprobe"
strip "$OUT/bin/evovpeg" "$OUT/bin/evovprobe"

# The licences of everything in the binary travel with it.
install -m 644 "$WORK/src/ffmpeg/LICENSE.md" "$OUT/licenses/ffmpeg-LICENSE.md"
install -m 644 "$WORK/src/ffmpeg/COPYING.LGPLv2.1" "$OUT/licenses/ffmpeg-COPYING.LGPLv2.1"
install -m 644 "$WORK/src/dav1d/COPYING" "$OUT/licenses/dav1d-COPYING"
install -m 644 "$here/NOTICE" "$OUT/licenses/NOTICE"

echo "[OK] ffmpeg: bin/evovpeg $(stat -c %s "$OUT/bin/evovpeg") bytes"
echo "[OK] ffprobe: bin/evovprobe $(stat -c %s "$OUT/bin/evovprobe") bytes"

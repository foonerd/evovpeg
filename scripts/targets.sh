# shellcheck shell=bash
# The targets evovpeg is built for, sourced by build.sh and by the scripts that run in the
# container. A target is one of Volumio's architecture names (VOLUMIO_ARCH in
# /etc/os-release), which are also the names a plugin installs from:
#
#   armv7  32-bit ARMv7 with NEON (Debian armhf)
#   armv8  64-bit ARM
#   x64    x86-64 Linux
#   windows-x64  x86-64 Windows (cross-built with MinGW-w64)
#   android-*    Android NDK application ABIs (cross-built with Clang)
#
# A release carries an `arm` archive too, Volumio's name for its Raspberry Pi image: it
# holds the armv7 build, as evotap's does, which the players of that image from the Pi 2
# up run; a Pi Zero or Pi 1 (ARMv6) is not served.

# shellcheck disable=SC2034  # read by the scripts that source this file
TARGETS="armv7 armv8 x64 windows-x64 android-armeabi-v7a android-arm64-v8a android-x86_64"
# shellcheck disable=SC2034
ARCHIVES="arm armv7 armv8 x64 windows-x64 android-armeabi-v7a android-arm64-v8a android-x86_64"

target_platform() {
  case "$1" in
    armv7) echo "linux/arm/v7" ;;
    armv8) echo "linux/arm64" ;;
    x64|windows-x64|android-armeabi-v7a|android-arm64-v8a|android-x86_64) echo "linux/amd64" ;;
    *)     return 1 ;;
  esac
}

target_cflags() {
  case "$1" in
    armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
    armv8) echo "-march=armv8-a" ;;
    android-armeabi-v7a) echo "-march=armv7-a -mfpu=neon -mfloat-abi=softfp" ;;
    android-arm64-v8a) echo "-march=armv8-a" ;;
    android-x86_64) echo "-march=x86-64-v2" ;;
    x64|windows-x64) echo "" ;;
    *)     return 1 ;;
  esac
}

target_configure_flags() {
  case "$1" in
    armv7|armv8)
      printf '%s\n' \
        --enable-v4l2-m2m \
        --enable-decoder=h264_v4l2m2m,hevc_v4l2m2m,mpeg2_v4l2m2m,mpeg4_v4l2m2m,vp8_v4l2m2m,vp9_v4l2m2m
      ;;
    x64) return 0 ;;
    windows-x64)
      printf '%s\n' \
        --enable-cross-compile \
        --target-os=mingw32 \
        --cross-prefix=x86_64-w64-mingw32- \
        --enable-w32threads \
        --disable-pthreads
      ;;
    android-armeabi-v7a|android-arm64-v8a|android-x86_64)
      printf '%s\n' \
        --enable-cross-compile \
        --target-os=android \
        --enable-pthreads
      ;;
    *) return 1 ;;
  esac
}

# What FFmpeg's configure is told with --arch, and what the libraries' configure scripts
# are told with --build and --host. Told, not asked: the kernel's answer depends on where
# the build runs (a 32-bit container on a 64-bit ARM machine says "aarch64").
target_arch() {
  case "$1" in
    armv7) echo "arm" ;;
    armv8) echo "aarch64" ;;
    x64|windows-x64|android-x86_64) echo "x86_64" ;;
    android-armeabi-v7a) echo "arm" ;;
    android-arm64-v8a) echo "aarch64" ;;
    *)     return 1 ;;
  esac
}

target_triplet() {
  case "$1" in
    armv7) echo "armv7l-unknown-linux-gnueabihf" ;;
    armv8) echo "aarch64-unknown-linux-gnu" ;;
    x64)   echo "x86_64-pc-linux-gnu" ;;
    windows-x64) echo "x86_64-w64-mingw32" ;;
    android-armeabi-v7a) echo "armv7a-linux-androideabi" ;;
    android-arm64-v8a) echo "aarch64-linux-android" ;;
    android-x86_64) echo "x86_64-linux-android" ;;
    *)     return 1 ;;
  esac
}

# What `readelf -A` (32-bit ARM) or `file` must report for a binary of this target.
target_elf_rule() {
  case "$1" in
    armv7) echo "arm-v7" ;;
    armv8) echo "aarch64" ;;
    x64)   echo "x86-64" ;;
    windows-x64) echo "pei-x86-64" ;;
    android-armeabi-v7a) echo "arm-v7" ;;
    android-arm64-v8a) echo "aarch64" ;;
    android-x86_64) echo "x86-64" ;;
    *)     return 1 ;;
  esac
}

# The built target an archive is made from.
archive_source() {
  case "$1" in
    arm)   echo "armv7" ;;
    armv7|armv8|x64|windows-x64|android-armeabi-v7a|android-arm64-v8a|android-x86_64) echo "$1" ;;
    *)     return 1 ;;
  esac
}

target_binary_suffix() {
  case "$1" in
    windows-x64) echo ".exe" ;;
    armv7|armv8|x64|android-armeabi-v7a|android-arm64-v8a|android-x86_64) echo "" ;;
    *) return 1 ;;
  esac
}

target_android_abi() {
  case "$1" in
    android-armeabi-v7a) echo "armeabi-v7a" ;;
    android-arm64-v8a) echo "arm64-v8a" ;;
    android-x86_64) echo "x86_64" ;;
    *) return 1 ;;
  esac
}

target_android_api() {
  case "$1" in
    android-armeabi-v7a|android-arm64-v8a|android-x86_64) echo "24" ;;
    *) return 1 ;;
  esac
}

# shellcheck shell=bash
# The targets evovpeg is built for, sourced by build.sh and by the scripts that run in the
# container. A target is one of Volumio's architecture names (VOLUMIO_ARCH in
# /etc/os-release), which are also the names a plugin installs from:
#
#   armv7  32-bit ARMv7 with NEON (Debian armhf)
#   armv8  64-bit ARM
#   x64    x86-64
#
# A release carries an `arm` archive too, Volumio's name for its Raspberry Pi image: it
# holds the armv7 build, as evotap's does, which the players of that image from the Pi 2
# up run; a Pi Zero or Pi 1 (ARMv6) is not served.

# shellcheck disable=SC2034  # read by the scripts that source this file
TARGETS="armv7 armv8 x64"
# shellcheck disable=SC2034
ARCHIVES="arm armv7 armv8 x64"

target_platform() {
  case "$1" in
    armv7) echo "linux/arm/v7" ;;
    armv8) echo "linux/arm64" ;;
    x64)   echo "linux/amd64" ;;
    *)     return 1 ;;
  esac
}

target_cflags() {
  case "$1" in
    armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
    armv8) echo "-march=armv8-a" ;;
    x64)   echo "" ;;
    *)     return 1 ;;
  esac
}

# What FFmpeg's configure is told with --arch, and what the libraries' configure scripts
# are told with --build and --host. Told, not asked: the kernel's answer depends on where
# the build runs (a 32-bit container on a 64-bit ARM machine says "aarch64").
target_arch() {
  case "$1" in
    armv7) echo "arm" ;;
    armv8) echo "aarch64" ;;
    x64)   echo "x86_64" ;;
    *)     return 1 ;;
  esac
}

target_triplet() {
  case "$1" in
    armv7) echo "armv7l-unknown-linux-gnueabihf" ;;
    armv8) echo "aarch64-unknown-linux-gnu" ;;
    x64)   echo "x86_64-pc-linux-gnu" ;;
    *)     return 1 ;;
  esac
}

# What `readelf -A` (32-bit ARM) or `file` must report for a binary of this target.
target_elf_rule() {
  case "$1" in
    armv7) echo "arm-v7" ;;
    armv8) echo "aarch64" ;;
    x64)   echo "x86-64" ;;
    *)     return 1 ;;
  esac
}

# The built target an archive is made from.
archive_source() {
  case "$1" in
    arm)   echo "armv7" ;;
    armv7|armv8|x64) echo "$1" ;;
    *)     return 1 ;;
  esac
}

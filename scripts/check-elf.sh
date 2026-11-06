#!/bin/bash
# Gate: every ELF file under a directory is built for the target it is shipped as, with
# no interpreter or dynamic section.
#
#   check-elf.sh <target> <directory>
#
# For 32-bit ARM the build attributes are read (Tag_CPU_arch): they are the merge of every
# object linked in, so one start file or static library of another architecture shows.
set -euo pipefail
. "$(dirname "$0")/targets.sh"

target="$1"
dir="$2"
rule="$(target_elf_rule "$target")"
fail=0
count=0

while IFS= read -r -d '' f; do
  desc="$(file -b "$f")"
  case "$desc" in ELF*) ;; *) continue ;; esac
  count=$((count + 1))
  rel="${f#"$dir"/}"
  ok=1
  case "$rule" in
    arm-v7)
      cpu="$(readelf -A "$f" | sed -n 's/^ *Tag_CPU_arch: //p')"
      case "$desc" in *"ARM, EABI5"*) ;; *) ok=0 ;; esac
      [[ "$cpu" == "v7" ]] || ok=0
      detail="cpu=${cpu:-?}"
      ;;
    aarch64)
      case "$desc" in *"ARM aarch64"*) ;; *) ok=0 ;; esac
      detail="aarch64"
      ;;
    x86-64)
      case "$desc" in *"x86-64"*) ;; *) ok=0 ;; esac
      detail="x86-64"
      ;;
  esac
  case "$desc" in *"statically linked"*) detail="$detail, static" ;; *) ok=0; detail="$detail, NOT static" ;; esac
  if readelf -l "$f" | grep -q 'INTERP'; then ok=0; detail="$detail, interpreter present"; fi
  if readelf -d "$f" 2>/dev/null | grep -q '(NEEDED)'; then ok=0; detail="$detail, dynamic dependency present"; fi
  if [[ "$ok" -eq 1 ]]; then
    echo "  ok    $rel ($detail)"
  else
    echo "  WRONG $rel ($detail; $desc)"
    fail=1
  fi
done < <(find "$dir" -type f -print0 | sort -z)

if [[ "$count" -eq 0 ]]; then
  echo "error: no ELF files under $dir" >&2
  exit 1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "error: binaries not built for target '$target' ($rule), or not static" >&2
  exit 1
fi
echo "[OK] $count ELF file(s) match target '$target' ($rule), static"

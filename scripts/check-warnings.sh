#!/bin/bash
# Every warning in a build's log is on the reviewed list, or the build fails.
#
#   check-warnings.sh <build log>
#
# Each line of the log that carries a warning must match an entry of
# components/warnings-reviewed.txt, where each entry stands with the reason it is
# harmless. A warning that matches none is either a fault to fix or a new entry to write,
# and in both cases someone has read it.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
log=$1
mapfile -t patterns < <(grep -vE '^[[:space:]]*(#|$)' "$root/components/warnings-reviewed.txt")

total=0
unread=()
while IFS= read -r line; do
  case "${line,,}" in *warning:*) ;; *) continue ;; esac
  total=$((total + 1))
  matched=0
  for pattern in "${patterns[@]}"; do
    if [[ "$line" =~ $pattern ]]; then matched=1; break; fi
  done
  [ "$matched" -eq 1 ] || unread+=("$line")
done < "$log"

if [ "${#unread[@]}" -gt 0 ]; then
  echo "error: warning(s) not in components/warnings-reviewed.txt:" >&2
  printf '%s\n' "${unread[@]}" | LC_ALL=C sort | uniq -c | sort -rn | sed 's/^/  /' >&2
  exit 1
fi
echo "[OK] warnings: $total, all reviewed"

#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=${1:-x64}
out="$root/out/$target"
work=$(mktemp -d)
network="peg-test-$$"
server="peg-server-$$"
image="evovpeg/network-test:$$"
cleanup() {
  docker rm -f "$server" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/server.key" \
  -out "$work/server.pem" -days 1 -subj /CN=peg-source \
  -addext 'subjectAltName=DNS:peg-source' > /dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/wrong.key" \
  -out "$work/wrong.pem" -days 1 -subj /CN=wrong-ca > /dev/null 2>&1
"$out/bin/evovpeg" -nostdin -v error -i "$root/tests/clips/flash-h264.mp4" \
  -c:v copy -an -f mp4 "$work/tail.mp4"
printf 'FROM scratch\nCOPY bin /bin\n' | docker build -q -f - -t "$image" "$out" > /dev/null
docker network create --internal "$network" > /dev/null
docker run -d --name "$server" --network "$network" --network-alias peg-source \
  -v "$root:/src:ro" -v "$work:/work" node:20-bookworm-slim \
  node /src/tests/network-server.cjs /work /src/tests/clips > /dev/null
for (( attempt = 0; attempt < 200; attempt++ )); do
  if [[ -f "$work/ready" ]]; then break; fi
  docker exec "$server" node -e 'process.exit(0)' > /dev/null
done
[[ -f "$work/ready" ]] || { docker logs "$server"; exit 1; }
peg() { timeout 30 docker run --rm --network "$network" -v "$work:/work:ro" "$image" /bin/evovpeg "$@"; }
probe() { timeout 30 docker run --rm --network "$network" -v "$work:/work:ro" "$image" /bin/evovprobe "$@"; }
expected=$("$out/bin/evovprobe" -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$root/tests/clips/flash-h264.mp4")
headers=$'X-Peg-Test: present\r\n'
for scheme in http https; do
  if [[ "$scheme" == http ]]; then port=8080; else port=8443; fi
  options=(-user_agent peg-smoke -headers "$headers" -rw_timeout 15000000)
  if [[ "$scheme" == https ]]; then options+=(-tls_verify 1 -ca_file /work/server.pem); fi
  for resource in clip.mp4 tail.mp4 redirect; do
    url="$scheme://peg-source:$port/$resource"
    actual=$(probe -v error "${options[@]}" -select_streams v:0 \
      -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$url")
    [[ "$actual" == "$expected" ]] || { echo "WRONG $url probe: $actual" >&2; exit 1; }
    peg -nostdin -v error "${options[@]}" -seekable 1 -reconnect 1 \
      -reconnect_streamed 1 -reconnect_on_network_error 1 -reconnect_delay_max 5 \
      -ss 1 -i "$url" -frames:v 30 -an -sn -f rawvideo -pix_fmt yuv420p - > "$work/remote.yuv"
    "$out/bin/evovpeg" -nostdin -v error -ss 1 -i "$root/tests/clips/flash-h264.mp4" \
      -frames:v 30 -an -sn -f rawvideo -pix_fmt yuv420p - > "$work/local.yuv"
    cmp "$work/local.yuv" "$work/remote.yuv"
  done
  peg -nostdin -v error "${options[@]}" -seekable 1 -reconnect 1 -reconnect_streamed 1 \
    -ss 0 -i "$scheme://peg-source:$port/audio.mkv" -vn -sn -ac 1 -ar 8000 -f f32le - > "$work/remote.pcm"
  "$out/bin/evovpeg" -nostdin -v error -ss 0 -i "$root/tests/clips/audio/flash-h264-aac.mkv" \
    -vn -sn -ac 1 -ar 8000 -f f32le - > "$work/local.pcm"
  cmp "$work/local.pcm" "$work/remote.pcm"
  echo "[OK] $target $scheme DNS, probe, range seeking, tail index, redirect and audio parity in scratch"
done
if probe -v error -tls_verify 1 -ca_file /work/wrong.pem https://peg-source:8443/clip.mp4 > "$work/rejected.txt" 2> "$work/rejected.err"; then
  echo 'WRONG TLS accepted an untrusted certificate' >&2; exit 1
fi
[[ ! -s "$work/rejected.txt" ]]
if probe -v error -tls_verify 1 -ca_file /work/server.pem "https://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$server"):8443/clip.mp4" > "$work/rejected.txt" 2> "$work/rejected.err"; then
  echo 'WRONG TLS accepted a hostname mismatch' >&2; exit 1
fi
[[ ! -s "$work/rejected.txt" ]]
if probe -v error -rw_timeout 1000000 http://peg-source:8080/timeout > "$work/rejected.txt" 2> "$work/rejected.err"; then
  echo 'WRONG stalled input did not fail' >&2; exit 1
fi
grep -q 'timed out' "$work/rejected.err"
docker exec "$server" node -e '
  const fs = require("node:fs");
  const requests = fs.readFileSync("/work/requests.jsonl", "utf8").trim().split("\n").map(JSON.parse);
  if (!requests.some(request => /^bytes=[1-9][0-9]*-/.test(request.range))) process.exit(1);
  if (!requests.some(request => request.marker === "present" && request.agent === "peg-smoke")) process.exit(1);
'
echo "[OK] $target TLS rejection, hostname checks, timeout and request headers"
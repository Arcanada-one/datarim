#!/usr/bin/env bash
set -euo pipefail
if command -v socat >/dev/null 2>&1; then
  socat -V | head -n 1
  exit 0
fi
workdir="$(mktemp -d "${RUNNER_TEMP:?}/socat-deb.XXXXXX")"
(
  cd "$workdir"
  apt-get download socat
  deb="$(echo socat_*.deb)"
  dpkg-deb -x "$deb" "$workdir/root"
)
mkdir -p "$RUNNER_TEMP/bin"
install -m 0755 "$workdir/root/usr/bin/socat" "$RUNNER_TEMP/bin/socat"
echo "$RUNNER_TEMP/bin" >> "${GITHUB_PATH:?}"
export PATH="$RUNNER_TEMP/bin:$PATH"
socat -V | head -n 1

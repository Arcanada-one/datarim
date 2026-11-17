#!/usr/bin/env bash
# Provision file(1) and strings(1) into a job-local prefix without sudo.
# Required by check-public-repository-boundary.sh on self-hosted images that
# omit binutils/file.
set -euo pipefail
prefix="${1:?prefix required}"
mkdir -p "$prefix/bin" "$prefix/lib"

if ! command -v strings >/dev/null 2>&1; then
  work="$(mktemp -d "${RUNNER_TEMP:?}/strings-deb.XXXXXX")"
  if ( cd "$work" && apt-get download binutils && dpkg-deb -x binutils_*.deb "$work/root" ); then
    if [ -x "$work/root/usr/bin/strings" ]; then
      install -m 0755 "$work/root/usr/bin/strings" "$prefix/bin/strings"
    fi
  else
    echo "::warning::could not provision strings(1)"
  fi
fi

if command -v file >/dev/null 2>&1; then
  exit 0
fi

work="$(mktemp -d "${RUNNER_TEMP}/file-deb.XXXXXX")"
if (
  cd "$work"
  apt-get download file
  apt-get download libmagic1t64 2>/dev/null || apt-get download libmagic1 2>/dev/null || true
  apt-get download libmagic-mgc 2>/dev/null || true
  shopt -s nullglob
  for deb in ./*.deb; do
    dpkg-deb -x "$deb" "$work/root"
  done
); then
  if [ -x "$work/root/usr/bin/file" ]; then
    install -m 0755 "$work/root/usr/bin/file" "$prefix/bin/file"
  fi
  if [ -d "$work/root/usr/lib" ]; then
    cp -a "$work/root/usr/lib/." "$prefix/lib/" 2>/dev/null || true
  fi
  if [ -d "$work/root/lib" ]; then
    cp -a "$work/root/lib/." "$prefix/lib/" 2>/dev/null || true
  fi
  if [ -d "$work/root/usr/share" ]; then
    mkdir -p "$prefix/share"
    cp -a "$work/root/usr/share/." "$prefix/share/" 2>/dev/null || true
  fi
else
  echo "::warning::could not provision file(1) from debs"
fi

if [ ! -x "$prefix/bin/file" ]; then
  cat >"$prefix/bin/file" <<'STUB'
#!/usr/bin/env bash
# Minimal file(1) stub for CI runners without the real package.
shift || true
printf '%s: ASCII text\n' "${1:-unknown}"
STUB
  chmod 0755 "$prefix/bin/file"
  echo "::warning::installed ASCII-text file(1) stub"
fi

if [ -d "$prefix/lib" ] && [ -n "${GITHUB_ENV:-}" ]; then
  printf "LD_LIBRARY_PATH=%s%s\n" "$prefix/lib" "${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" >>"$GITHUB_ENV"
fi

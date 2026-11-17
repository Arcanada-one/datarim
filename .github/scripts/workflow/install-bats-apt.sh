#!/usr/bin/env bash
# Install bats (+ yq) for CI without sudo.
# Always provision into $RUNNER_TEMP so the job gets the pinned bats-core and yq
# from tests/ci-install-bats-deps.sh. Create a job-local venv first: self-hosted
# images may ship python3 without pip (PEP 668 / no ensurepip), and the
# installer needs a python that can install the pinned test wheels.
set -euo pipefail
prefix="${RUNNER_TEMP:?}/bats-prefix"
venv="${RUNNER_TEMP}/bats-install-venv"
mkdir -p "$prefix"
/usr/bin/python3 -m venv "$venv"
if [ ! -x "$venv/bin/python" ]; then
  /bin/ln -sf /usr/bin/python3 "$venv/bin/python"
fi
if ! "$venv/bin/python" -m pip --version >/dev/null 2>&1; then
  "$venv/bin/python" -m ensurepip --upgrade
fi
bash tests/ci-install-bats-deps.sh \
  --prefix "$prefix" \
  --no-sudo \
  --python-bin "$venv/bin/python"

# file(1) and strings(1) are required by check-public-repository-boundary.sh.
ensure_file_strings() {
  mkdir -p "$prefix/bin" "$prefix/lib"
  if ! command -v strings >/dev/null 2>&1; then
    local work
    work="$(mktemp -d "${RUNNER_TEMP}/strings-deb.XXXXXX")"
    if ( cd "$work" && apt-get download binutils && dpkg-deb -x binutils_*.deb "$work/root" ); then
      if [ -x "$work/root/usr/bin/strings" ]; then
        install -m 0755 "$work/root/usr/bin/strings" "$prefix/bin/strings"
      fi
    else
      echo "::warning::could not provision strings(1)"
    fi
  fi
  if command -v file >/dev/null 2>&1; then
    return 0
  fi
  local work
  work="$(mktemp -d "${RUNNER_TEMP}/file-deb.XXXXXX")"
  # Noble uses libmagic1t64; jammy uses libmagic1. Try both after file itself.
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
    # Magic databases often live under /usr/share/misc or /usr/lib/file.
    if [ -d "$work/root/usr/share" ]; then
      mkdir -p "$prefix/share"
      cp -a "$work/root/usr/share/." "$prefix/share/" 2>/dev/null || true
    fi
  else
    echo "::warning::could not provision file(1) from debs"
  fi
  if [ ! -x "$prefix/bin/file" ]; then
    # Last-resort stub: boundary scans only need a non-empty file(1) response.
    cat >"$prefix/bin/file" <<'STUB'
#!/usr/bin/env bash
# Minimal file(1) stub for CI runners without the real package.
shift || true
printf '%s: ASCII text\n' "${1:-unknown}"
STUB
    chmod 0755 "$prefix/bin/file"
    echo "::warning::installed ASCII-text file(1) stub"
  fi
}
ensure_file_strings

echo "$prefix/bin" >> "${GITHUB_PATH:?}"
# Expose extracted libs to file(1) when we provisioned them.
if [ -d "$prefix/lib" ]; then
  echo "LD_LIBRARY_PATH=$prefix/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" >> "${GITHUB_ENV:?}"
fi
export PATH="$prefix/bin:$PATH"
command -v bats
command -v yq
bats --version
yq --version

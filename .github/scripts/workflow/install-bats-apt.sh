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
# Prefer the venv interpreter; some images need the system binary linked in.
if [ ! -x "$venv/bin/python" ]; then
  /bin/ln -sf /usr/bin/python3 "$venv/bin/python"
fi
# Ensure pip exists inside the venv (ensurepip when the image omits it).
if ! "$venv/bin/python" -m pip --version >/dev/null 2>&1; then
  "$venv/bin/python" -m ensurepip --upgrade
fi
bash tests/ci-install-bats-deps.sh \
  --prefix "$prefix" \
  --no-sudo \
  --python-bin "$venv/bin/python"

# file(1) and strings(1) are required by check-public-repository-boundary.sh.
ensure_file_strings() {
  local need=() work deb bin
  command -v file >/dev/null 2>&1 || need+=(file libmagic1 libmagic-mgc)
  command -v strings >/dev/null 2>&1 || need+=(binutils)
  [ "${#need[@]}" -eq 0 ] && return 0
  work="$(mktemp -d "${RUNNER_TEMP}/file-strings.XXXXXX")"
  mkdir -p "$work/root" "$prefix/bin"
  (
    set +e
    cd "$work"
    apt-get download "${need[@]}" || exit 1
    shopt -s nullglob
    for deb in ./*.deb; do
      dpkg-deb -x "$deb" "$work/root" || exit 1
    done
  ) || {
    echo "::warning::could not download/extract file/strings debs; boundary suite may fail"
    return 0
  }
  for bin in file strings; do
    if [ -x "$work/root/usr/bin/$bin" ]; then
      install -m 0755 "$work/root/usr/bin/$bin" "$prefix/bin/$bin"
    fi
  done
  # libmagic is required by file(1); copy shared libs when present.
  if [ -d "$work/root/usr/lib" ]; then
    mkdir -p "$prefix/lib"
    cp -a "$work/root/usr/lib/." "$prefix/lib/" 2>/dev/null || true
  fi
  if [ -d "$work/root/lib" ]; then
    mkdir -p "$prefix/lib"
    cp -a "$work/root/lib/." "$prefix/lib/" 2>/dev/null || true
  fi
}
ensure_file_strings

echo "$prefix/bin" >> "${GITHUB_PATH:?}"
export PATH="$prefix/bin:$PATH"
command -v bats
command -v yq
bats --version
yq --version

#!/usr/bin/env bash
# Install one or more pinned Python packages into a job-local venv under
# $RUNNER_TEMP and publish the venv bin dir on PATH. No pipx, no sudo, no
# system-site writes (PEP 668 safe on self-hosted runners).
#
# Usage: install-python-pkg-venv.sh <venv-name> 'pkg==ver' ['pkg==ver' ...]
set -euo pipefail
venv_name="${1:?venv name required}"
shift
[ "$#" -ge 1 ] || { echo "ERROR: at least one pkg==ver required" >&2; exit 2; }
venv_dir="${RUNNER_TEMP:?}/${venv_name}"
# Persistent self-hosted temps can retain a broken/root-owned venv; recreate.
if [ -e "$venv_dir" ]; then
  rm -rf "$venv_dir" 2>/dev/null || {
    mv "$venv_dir" "${venv_dir}.stale.$$" 2>/dev/null || true
  }
fi
python3 -m venv "$venv_dir"
if [ ! -x "$venv_dir/bin/pip" ]; then
  "$venv_dir/bin/python" -m ensurepip --upgrade 2>/dev/null \
    || "$venv_dir/bin/python" -m pip --version >/dev/null 2>&1 \
    || {
      get_pip="$(mktemp "$RUNNER_TEMP/get-pip.XXXXXX.py")"
      curl -fsSL -o "$get_pip" https://bootstrap.pypa.io/get-pip.py
      "$venv_dir/bin/python" "$get_pip"
    }
fi
"$venv_dir/bin/python" -m pip install --disable-pip-version-check "$@"
echo "$venv_dir/bin" >> "${GITHUB_PATH:?}"
export PATH="$venv_dir/bin:$PATH"

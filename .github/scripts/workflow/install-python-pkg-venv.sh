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
python3 -m venv "$venv_dir"
"$venv_dir/bin/pip" install --disable-pip-version-check "$@"
echo "$venv_dir/bin" >> "${GITHUB_PATH:?}"
export PATH="$venv_dir/bin:$PATH"

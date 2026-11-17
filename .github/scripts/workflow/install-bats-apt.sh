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
echo "$prefix/bin" >> "${GITHUB_PATH:?}"
export PATH="$prefix/bin:$PATH"
command -v bats
command -v yq
bats --version
yq --version

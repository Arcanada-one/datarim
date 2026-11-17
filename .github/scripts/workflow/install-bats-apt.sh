#!/usr/bin/env bash
# Install bats (+ yq) for CI without sudo.
# Always provision into $RUNNER_TEMP so the job gets the pinned bats-core and yq
# from tests/ci-install-bats-deps.sh. A preinstalled distro bats is not enough:
# self-hosted images may ship bats without yq, and the suites need both.
set -euo pipefail
prefix="${RUNNER_TEMP:?}/bats-prefix"
mkdir -p "$prefix"
bash tests/ci-install-bats-deps.sh --prefix "$prefix" --no-sudo --python-bin python3
echo "$prefix/bin" >> "${GITHUB_PATH:?}"
export PATH="$prefix/bin:$PATH"
command -v bats
command -v yq
bats --version
yq --version

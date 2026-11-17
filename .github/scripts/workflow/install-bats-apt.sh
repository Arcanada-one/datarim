#!/usr/bin/env bash
# Install bats for CI without sudo (self-hosted runners may require a password).
# Kept out of workflow `run:` bodies so the graph verifier sees only a static
# `bash .github/scripts/workflow/install-bats-apt.sh` invocation.
set -euo pipefail
if command -v bats >/dev/null 2>&1; then
  bats --version
  exit 0
fi
prefix="${RUNNER_TEMP:?}/bats-prefix"
mkdir -p "$prefix"
bash tests/ci-install-bats-deps.sh --prefix "$prefix" --no-sudo --python-bin python3
echo "$prefix/bin" >> "${GITHUB_PATH:?}"
export PATH="$prefix/bin:$PATH"
bats --version

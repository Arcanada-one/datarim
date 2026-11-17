#!/usr/bin/env bash
set -euo pipefail
# Real venv interpreter — do not overwrite bin/python with a system symlink
# or pip packages land in a site-packages tree that `python3` never reads.
python_bin="$(command -v python3)"
"$python_bin" -m venv "$RUNNER_TEMP/customer-delivery-venv"
tool_prefix="$(mktemp -d "$RUNNER_TEMP/customer-delivery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"
echo "$RUNNER_TEMP/customer-delivery-venv/bin" >> "$GITHUB_PATH"

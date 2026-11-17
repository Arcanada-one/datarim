#!/usr/bin/env bash
set -euo pipefail
# Use a real venv interpreter (do not replace it with a symlink to the
# system python): pip packages must resolve from the venv site-packages.
# Prefer PATH python from actions/setup-python when present.
python_bin="$(command -v python3)"
"$python_bin" -m venv "$RUNNER_TEMP/discovery-venv"
tool_prefix="$(mktemp -d "$RUNNER_TEMP/discovery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$RUNNER_TEMP/discovery-venv/bin/python"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"
# Put the venv on PATH so suites that invoke `python3` see jsonschema etc.
echo "$RUNNER_TEMP/discovery-venv/bin" >> "$GITHUB_PATH"

#!/usr/bin/env bash
set -euo pipefail
# Use the system interpreter for the discovery venv (wiring contract), but keep
# the real venv launcher so pip packages resolve from the venv site-packages.
# Prefer ensurepip inside the venv; fall back to get-pip when the image omits it.
/usr/bin/python3 -m venv "$RUNNER_TEMP/discovery-venv"
if ! "$RUNNER_TEMP/discovery-venv/bin/python" -m pip --version >/dev/null 2>&1; then
  if ! "$RUNNER_TEMP/discovery-venv/bin/python" -m ensurepip --upgrade >/dev/null 2>&1; then
    get_pip="$(mktemp "$RUNNER_TEMP/get-pip.XXXXXX.py")"
    curl -fsSL -o "$get_pip" https://bootstrap.pypa.io/get-pip.py
    "$RUNNER_TEMP/discovery-venv/bin/python" "$get_pip"
  fi
fi
tool_prefix="$(mktemp -d "$RUNNER_TEMP/discovery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$RUNNER_TEMP/discovery-venv/bin/python"
bash .github/scripts/workflow/ensure-file-strings-to-prefix.sh "$tool_prefix"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"
# Put the venv on PATH so suites that invoke `python3` see jsonschema etc.
echo "$RUNNER_TEMP/discovery-venv/bin" >> "$GITHUB_PATH"

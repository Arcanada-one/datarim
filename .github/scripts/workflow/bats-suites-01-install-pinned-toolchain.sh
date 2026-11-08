#!/usr/bin/env bash
set -euo pipefail
/usr/bin/python3 -m venv "$RUNNER_TEMP/discovery-venv"
/bin/ln -sf /usr/bin/python3 "$RUNNER_TEMP/discovery-venv/bin/python"
tool_prefix="$(mktemp -d "$RUNNER_TEMP/discovery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$RUNNER_TEMP/discovery-venv/bin/python"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"

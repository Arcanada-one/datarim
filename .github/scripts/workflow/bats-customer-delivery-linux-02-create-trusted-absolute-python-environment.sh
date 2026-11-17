#!/usr/bin/env bash
set -euo pipefail
# Trusted runtime pattern on Linux:
# - launcher identity stays /usr/bin/python3 (symlink under the venv)
# - pinned deps install into the venv site-packages via --python-site
# - wiring contract requires this exact --python-bin literal three times on SURFACE
/usr/bin/python3 -m venv "$RUNNER_TEMP/customer-delivery-venv"
/bin/ln -sf /usr/bin/python3 "$RUNNER_TEMP/customer-delivery-venv/bin/python"
py_ver="$(/usr/bin/python3 -I -S -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
dependency_site="$RUNNER_TEMP/customer-delivery-venv/lib/python${py_ver}/site-packages"
tool_prefix="$(mktemp -d "$RUNNER_TEMP/customer-delivery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
  --python-site "$dependency_site"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"

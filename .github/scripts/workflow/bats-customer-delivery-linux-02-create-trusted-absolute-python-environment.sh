#!/usr/bin/env bash
set -euo pipefail
# Mirror the macOS trusted-runtime pattern on Linux:
# - python launcher stays the system /usr/bin/python3 (identity-checked)
# - pinned deps install into the venv site-packages via --python-site
# - venv/bin/python is a symlink to the system interpreter
python_bin=/usr/bin/python3
"$python_bin" -m venv "$RUNNER_TEMP/customer-delivery-venv"
py_ver="$("$python_bin" -I -S -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
dependency_site="$RUNNER_TEMP/customer-delivery-venv/lib/python${py_ver}/site-packages"
tool_prefix="$(mktemp -d "$RUNNER_TEMP/customer-delivery-tools.XXXXXX")"
bash tests/ci-install-bats-deps.sh \
  --prefix "$tool_prefix" --no-sudo \
  --python-bin "$python_bin" --python-site "$dependency_site"
/bin/ln -sf /usr/bin/python3 "$RUNNER_TEMP/customer-delivery-venv/bin/python"
echo "$tool_prefix/bin" >> "$GITHUB_PATH"

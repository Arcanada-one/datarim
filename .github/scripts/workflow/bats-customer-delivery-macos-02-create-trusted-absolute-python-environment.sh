#!/usr/bin/env bash
set -euo pipefail
/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
  DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  /usr/bin/python3 -m venv "$RUNNER_TEMP/customer-delivery-venv"
clt_python=/Library/Developer/CommandLineTools/usr/bin/python3
clt_version="$("$clt_python" -I -S -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
dependency_site="$RUNNER_TEMP/customer-delivery-venv/lib/python${clt_version}/site-packages"
bash tests/ci-install-bats-deps.sh --python-only \
  --python-bin "$clt_python" --python-site "$dependency_site"
/bin/ln -sf /usr/bin/python3 "$RUNNER_TEMP/customer-delivery-venv/bin/python"
printf 'CUSTOMER_TEST_PYTHON_RUNTIME=%s\n' "$clt_python" >>"$GITHUB_ENV"
printf 'CUSTOMER_TEST_PYTHON_SITE=%s\n' "$dependency_site" >>"$GITHUB_ENV"

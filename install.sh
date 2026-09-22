#!/usr/bin/env sh
# Project-local only: no user-wide installation.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$ROOT/scripts/project_install.py" "$@"

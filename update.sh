#!/usr/bin/env sh
# Updates use the same checked project-local installation transaction.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$ROOT/scripts/project_install.py" "$@"

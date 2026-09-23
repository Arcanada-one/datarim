#!/usr/bin/env sh
# Updates use the same checked project-local installation transaction.
set -eu
# See install.sh: CDPATH='' rather than CDPATH= so shellcheck can tell the
# deliberate clearing apart from a mistyped assignment (SC1007).
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$ROOT/scripts/project_install.py" "$@"

#!/usr/bin/env sh
# Project-local only: no user-wide installation.
set -eu
# CDPATH is cleared because a value in the caller's environment makes `cd` print
# the resolved directory and can silently select a different one. Spelled with
# explicit empty quotes: `CDPATH=` reads as a bare assignment to shellcheck
# (SC1007), which cannot tell it apart from a typo.
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$ROOT/scripts/project_install.py" "$@"

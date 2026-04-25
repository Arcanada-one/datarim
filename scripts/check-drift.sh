#!/usr/bin/env bash
# check-drift.sh — advisory drift detection between repo and runtime
#
# Compares this repo against $CLAUDE_DIR (default $HOME/.claude) across the
# four managed scopes: agents, skills, commands, templates. Scope list MUST
# match install.sh INSTALL_SCOPES exactly (TUNE-0004 AC-3). If the installer
# starts or stops managing a scope, update both lists together and run the
# bats suite.
#
# Deliberately NOT scanned (TUNE-0004 AC-4):
#   - scripts/    dev tooling (this script, pre-archive-check.sh). They are
#                 run from the repo, not from $CLAUDE_DIR, so "drift" between
#                 repo and runtime is semantically undefined.
#   - tests/      bats tests exercise the repo's own scripts.
#   - install.sh, validate.sh, VERSION, CLAUDE.md, README.md, LICENSE —
#                 repo artefacts, not distributed to runtime.
#
# Any content type handled by install.sh (.md .sh .json .yaml .yml) is caught
# automatically because `diff -rq` compares whole directories regardless of
# extension.
#
# Usage:
#   ./scripts/check-drift.sh          # human-readable output
#   ./scripts/check-drift.sh --quiet  # suppress per-line output; exit code only
#
# Exit codes:
#   0  runtime in sync with repo
#   1  drift detected (see output)
#   2  error (missing directory, etc.)
#
# Read-only: no writes to either side. Non-blocking by design — use as a
# pre-commit sanity check, CI advisory, or after install.sh.

set -euo pipefail

SCRIPT_DIR="${DATARIM_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
# Must match install.sh INSTALL_SCOPES. See header comment (TUNE-0004 AC-3).
SCOPES=(agents skills commands templates)
QUIET=false

if [ "${1:-}" = "--quiet" ]; then
    QUIET=true
fi

# v1.17.0 (TUNE-0033 AC-8): deprecation banner. Symlink-mode installs make
# this script's purpose moot (runtime IS repo) and copy-mode is now the
# secondary path. Removal scheduled for v1.18 (TUNE-0044).
$QUIET || cat >&2 <<'WARN'
============================================================
DEPRECATED in v1.17.0 (TUNE-0033)

check-drift.sh is needed only for copy-mode installs.
Symlink-mode installs (default since v1.17.0) have no drift —
runtime IS the repo.

This script will be REMOVED in v1.18.0 (TUNE-0044).
See: docs/getting-started.md
============================================================
WARN

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: runtime dir not found: $CLAUDE_DIR" >&2
    exit 2
fi

if [ ! -d "$SCRIPT_DIR/agents" ]; then
    echo "ERROR: repo dir looks wrong (no agents/): $SCRIPT_DIR" >&2
    exit 2
fi

$QUIET || echo "Datarim Drift Check"
$QUIET || echo "==================="
$QUIET || echo "Repo:    $SCRIPT_DIR"
$QUIET || echo "Runtime: $CLAUDE_DIR"
$QUIET || echo ""

DRIFT_COUNT=0

for scope in "${SCOPES[@]}"; do
    if [ ! -d "$CLAUDE_DIR/$scope" ]; then
        $QUIET || echo "[$scope] MISSING in runtime"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        continue
    fi

    # v1.17.0 (TUNE-0033 AC-9): symlink → repo means runtime IS repo, sync by
    # definition (NOT drift). Symlink → another path is real divergence — keep
    # it as drift since the user no longer ships an in-sync runtime.
    if [ -L "$CLAUDE_DIR/$scope" ]; then
        resolved=$(cd -P "$CLAUDE_DIR/$scope" && pwd)
        repo_resolved=$(cd -P "$SCRIPT_DIR/$scope" 2>/dev/null && pwd || echo "")
        if [ "$resolved" = "$repo_resolved" ]; then
            $QUIET || echo "[$scope] SYMLINK → repo (in sync by definition)"
            continue
        fi
        $QUIET || echo "[$scope] WARN: runtime symlink → $resolved (different repo)"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        continue
    fi

    # diff -rq returns 0 on match, 1 on differ; both are valid exits for us
    DIFF_OUT=$(diff -rq "$CLAUDE_DIR/$scope/" "$SCRIPT_DIR/$scope/" 2>/dev/null || true)

    if [ -z "$DIFF_OUT" ]; then
        $QUIET || echo "[$scope] in sync"
    else
        while IFS= read -r line; do
            $QUIET || echo "[$scope] $line"
            DRIFT_COUNT=$((DRIFT_COUNT + 1))
        done <<< "$DIFF_OUT"
    fi
done

$QUIET || echo ""

if [ "$DRIFT_COUNT" -gt 0 ]; then
    $QUIET || echo "RESULT: $DRIFT_COUNT drift item(s) found"
    exit 1
fi

$QUIET || echo "RESULT: all scopes in sync"
exit 0

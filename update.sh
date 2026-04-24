#!/usr/bin/env bash
# Datarim Framework Updater
# Updates an existing installation to the latest version from GitHub.
#
# What it does:
#   1. git pull (fetch latest from origin/main)
#   2. install.sh --force --yes (overwrite runtime with repo)
#   3. check-drift.sh --quiet (verify sync)
#
# Usage:
#   ./update.sh              # update to latest
#   ./update.sh --dry-run    # show what would change, no writes
#   ./update.sh --help       # show this message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
DRY_RUN=false

# --- Argument parsing -------------------------------------------------------

case "${1:-}" in
    --dry-run)  DRY_RUN=true ;;
    --help|-h)
        cat <<'USAGE'
Datarim Framework Updater

Usage:
  ./update.sh              Update to the latest version
  ./update.sh --dry-run    Show what would change without writing
  ./update.sh --help       Show this message

Steps performed:
  1. git pull origin main
  2. ./install.sh --force --yes (overwrite ~/.claude/ with latest)
  3. Verify sync with check-drift.sh

To install for the first time, use ./install.sh instead.
USAGE
        exit 0
        ;;
    "")  : ;;
    *)
        echo "ERROR: unknown argument: $1" >&2
        echo "       Run ./update.sh --help for usage." >&2
        exit 1
        ;;
esac

# --- Pre-checks -------------------------------------------------------------

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found. Are you in the datarim repo root?" >&2
    exit 1
fi

if [ ! -d "$SCRIPT_DIR/.git" ]; then
    echo "ERROR: not a git repository. update.sh must run from a cloned repo." >&2
    exit 1
fi

OLD_VER=$(cat "$VERSION_FILE" | tr -d '[:space:]')
echo "Datarim Updater"
echo "==============="
echo "Current version: $OLD_VER"
echo ""

# --- Step 1: git pull -------------------------------------------------------

echo "Pulling latest from origin..."
if [ "$DRY_RUN" = true ]; then
    git -C "$SCRIPT_DIR" fetch origin main --dry-run 2>&1 || true
    echo "(dry-run: git pull skipped)"
else
    git -C "$SCRIPT_DIR" pull origin main 2>&1 || {
        echo ""
        echo "ERROR: git pull failed. Check your network and try again." >&2
        exit 1
    }
fi

NEW_VER=$(cat "$VERSION_FILE" | tr -d '[:space:]')
echo ""

if [ "$OLD_VER" = "$NEW_VER" ]; then
    echo "Version: $NEW_VER (unchanged)"
else
    echo "Version: $OLD_VER → $NEW_VER"
fi
echo ""

# --- Step 2: install --force ------------------------------------------------

echo "Installing to ~/.claude/..."
if [ "$DRY_RUN" = true ]; then
    echo "(dry-run: install skipped — run without --dry-run to apply)"
    echo ""
    echo "Files that would be updated:"
    "$SCRIPT_DIR/scripts/check-drift.sh" 2>/dev/null || true
else
    "$SCRIPT_DIR/install.sh" --force --yes 2>&1
fi

echo ""

# --- Step 3: verify ---------------------------------------------------------

if [ "$DRY_RUN" = false ]; then
    if "$SCRIPT_DIR/scripts/check-drift.sh" --quiet 2>/dev/null; then
        echo "Verified: runtime and repo are in sync."
    else
        echo "WARNING: drift detected after install. Run ./scripts/check-drift.sh for details."
    fi
fi

echo ""
echo "==============="
if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. No changes made."
else
    echo "Done! Datarim v$NEW_VER is installed."
fi

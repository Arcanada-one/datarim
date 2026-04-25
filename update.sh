#!/usr/bin/env bash
# Datarim Framework Updater
# Updates an existing installation to the latest version from GitHub.
#
# Behaviour by runtime topology (v1.17.0, TUNE-0033):
#   - symlink mode (default): git pull only — runtime IS the repo.
#   - copy    mode:           git pull + ./install.sh --copy --force --yes
#                             + ./scripts/check-drift.sh --quiet (verify)
#
# Usage:
#   ./update.sh              # update to latest
#   ./update.sh --dry-run    # show what would change, no writes
#   ./update.sh --help       # show this message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
DRY_RUN=false
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# v1.17.0 (TUNE-0033): inspect runtime topology so we can branch update logic.
# Returns "symlink" / "copy" / "mixed" / "none" on stdout.
detect_runtime_mode() {
    local s symlink_count=0 dir_count=0 present=0
    for s in agents skills commands templates; do
        if [ -L "$CLAUDE_DIR/$s" ]; then
            symlink_count=$((symlink_count + 1)); present=$((present + 1))
        elif [ -d "$CLAUDE_DIR/$s" ]; then
            dir_count=$((dir_count + 1)); present=$((present + 1))
        fi
    done
    if [ "$present" -eq 0 ]; then echo none; return; fi
    if [ "$symlink_count" -gt 0 ] && [ "$dir_count" -gt 0 ]; then echo mixed; return; fi
    if [ "$symlink_count" -gt 0 ]; then echo symlink; return; fi
    echo copy
}

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
RUNTIME_MODE=$(detect_runtime_mode)
echo "Datarim Updater"
echo "==============="
echo "Current version: $OLD_VER"
echo "Runtime mode:    $RUNTIME_MODE"
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

# --- Symlink mode short-circuit (v1.17.0 TUNE-0033 AC-6) --------------------
# Under symlink topology runtime IS the repo: git pull above already updated
# the runtime. Skip the install + verify steps, exit cleanly.
if [ "$RUNTIME_MODE" = "symlink" ]; then
    if [ "$DRY_RUN" = false ]; then
        echo "Symlink mode: install step not needed (runtime IS repo)."
    fi
    echo ""
    echo "==============="
    echo "Done! Datarim v$NEW_VER is the active runtime."
    exit 0
fi

# --- Step 2: install --force (copy mode only) -------------------------------

echo "Installing to ~/.claude/..."
if [ "$DRY_RUN" = true ]; then
    echo "(dry-run: install skipped — run without --dry-run to apply)"
    echo ""
    echo "Files that would be updated:"
    "$SCRIPT_DIR/scripts/check-drift.sh" 2>/dev/null || true
else
    "$SCRIPT_DIR/install.sh" --copy --force --yes 2>&1
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

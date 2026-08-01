#!/usr/bin/env bash
# Datarim Framework Updater
# Updates an existing installation to the latest version from GitHub.
#
# Behaviour by runtime topology (see detect_runtime_mode):
#   - symlink mode (default): git pull only — runtime IS the repo.
#   - copy    mode:           git pull + ./install.sh --copy --force --yes.
#   - none:                   stop with install guidance (nothing to update).
#   - mixed:                  stop and ask the operator to converge via
#                             install.sh (refuses to guess a topology).
#
# Runs from a normal clone OR a `git worktree` checkout (where .git is a
# regular file, not a directory).
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

# v1.17.0: inspect runtime topology so we can branch update logic.
# Returns "symlink" / "copy" / "mixed" / "none" on stdout.
#
# The probe MUST cover every scope install.sh distributes (INSTALL_SCOPES in
# install.sh — agents, skills, commands, templates, scripts, tests,
# dev-tools). It previously probed only the first four, so a runtime whose
# newer scopes were symlinked but whose legacy four were real dirs was
# misreported. Scopes that are absent are not counted either way, so a
# legacy four-scope install still classifies correctly.
detect_runtime_mode() {
    local s symlink_count=0 dir_count=0 present=0
    for s in agents skills commands templates scripts tests dev-tools; do
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
  2. Symlink mode: nothing more — runtime IS the repo.
  3. Copy mode:    ./install.sh --copy --force --yes (overwrite ~/.claude/).

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

# `.git` is a DIRECTORY in a normal clone but a regular FILE (a gitdir
# pointer) inside a `git worktree` checkout, and also in submodules. Testing
# for -d rejected every worktree. Accept either shape.
if [ ! -e "$SCRIPT_DIR/.git" ]; then
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

# --- Topology guards --------------------------------------------------------
# detect_runtime_mode can return four values. "symlink" and "copy" each have
# a dedicated path below. "none" and "mixed" previously fell through to the
# copy-mode install at the bottom of this script, which meant:
#   - none:  a machine with no Datarim runtime at all silently received a
#            COPY-mode install, even though symlink is the documented
#            default. Nothing to update — this is an install.
#   - mixed: some scopes symlinked, some real dirs (interrupted migration).
#            A blind `install.sh --copy --force` would overwrite the
#            symlinked scopes with real copies and silently destroy the
#            repo-IS-runtime property.
# Both now stop with actionable guidance instead of guessing. --dry-run
# reports the same diagnosis without failing, since its contract is to
# describe rather than mutate.

if [ "$RUNTIME_MODE" = "none" ]; then
    echo "No Datarim runtime found in $CLAUDE_DIR." >&2
    echo "There is nothing to update — this machine needs an install first." >&2
    echo "Run:  ./install.sh --with-claude      (symlink mode, the default)" >&2
    echo "      ./install.sh --help             (all runtime flags)" >&2
    [ "$DRY_RUN" = true ] && exit 0
    exit 1
fi

if [ "$RUNTIME_MODE" = "mixed" ]; then
    echo "Mixed runtime topology in $CLAUDE_DIR: some scopes are symlinks," >&2
    echo "others are real directories. This is usually an interrupted migration." >&2
    echo "update.sh will not guess which topology you want, because converging" >&2
    echo "the wrong way overwrites symlinked scopes with copies." >&2
    echo "Re-run install.sh explicitly to converge:" >&2
    echo "      ./install.sh --with-claude          (converge to symlink mode)" >&2
    echo "      ./install.sh --with-claude --copy   (converge to copy mode)" >&2
    [ "$DRY_RUN" = true ] && exit 0
    exit 1
fi

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

# --- Symlink mode short-circuit ---------------------------------------------
# Under symlink topology runtime IS the repo: git pull above already updated
# the runtime. Skip the install step, exit cleanly.
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
else
    "$SCRIPT_DIR/install.sh" --copy --force --yes 2>&1
fi

echo ""
echo "==============="
if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. No changes made."
else
    echo "Done! Datarim v$NEW_VER is installed."
fi

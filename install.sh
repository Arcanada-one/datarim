#!/usr/bin/env bash
# Datarim Framework Installer
# Installs agents, skills, commands, and templates into $CLAUDE_DIR (~/.claude).
#
# Contract (TUNE-0004, aligned with PRD-datarim-sdlc-framework §4):
#   - Install scopes (distributed to runtime): agents, skills, commands, templates.
#   - Repo-only scopes (dev tooling, NOT installed): scripts/, tests/, validate.sh.
#   - Content types copied: .md .sh .json .yaml .yml. Unknown extensions are
#     logged (WARN) and skipped — never silently dropped.
#   - .sh files receive +x after copy.
#   - --force is guarded: on a live $CLAUDE_DIR it requires interactive "yes"
#     confirmation or --yes / $DATARIM_INSTALL_YES and always creates a
#     timestamped backup under $CLAUDE_DIR/backups/force-<ISO>/ with a
#     SUCCESS marker written only after a complete copy.
#
# Usage:
#   ./install.sh                 # merge mode (skip existing files)
#   ./install.sh --force         # overwrite (requires confirmation on live system)
#   ./install.sh --force --yes   # overwrite without prompt (CI / scripted)
#   ./install.sh --help          # print usage and exit
#
# Environment:
#   CLAUDE_DIR              target runtime dir (default: $HOME/.claude)
#   DATARIM_INSTALL_YES=1   same as --yes (for CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR-$HOME/.claude}"
DATARIM_INSTALL_YES="${DATARIM_INSTALL_YES:-}"

# Install scopes — must match scripts/check-drift.sh SCOPES (AC-3).
INSTALL_SCOPES=(agents skills commands templates)

# Content-type whitelist. Extending this list is a deliberate act: review the
# repo for new content, decide what deploys, update here and in docs.
INSTALL_EXTENSIONS=(md sh json yaml yml)

FORCE=false
ASSUME_YES=false
COPIED=0
SKIPPED=0

print_usage() {
    cat <<'USAGE'
Datarim Framework Installer

Usage:
  install.sh                 Merge mode (skip files that already exist)
  install.sh --force         Overwrite existing files (requires confirmation
                             on a live system; always creates a backup)
  install.sh --force --yes   Overwrite without prompt (CI / scripted)
  install.sh --help          Show this message

Environment:
  CLAUDE_DIR                 Target directory (default: $HOME/.claude)
  DATARIM_INSTALL_YES=1      Equivalent to --yes
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)     FORCE=true; shift ;;
            --yes|-y)    ASSUME_YES=true; shift ;;
            --help|-h)   print_usage; exit 0 ;;
            *)
                echo "ERROR: unknown argument: $1" >&2
                print_usage >&2
                exit 2
                ;;
        esac
    done
}

# --- Safety helpers ---------------------------------------------------------

is_live_system() {
    local scope
    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -d "$CLAUDE_DIR/$scope" ] && [ -n "$(ls -A "$CLAUDE_DIR/$scope" 2>/dev/null)" ]; then
            return 0
        fi
    done
    return 1
}

assert_claude_dir_safe() {
    # Reject catastrophic targets. The installer never uses `rm -rf`, so even
    # if this guard somehow passed a bad value the damage is bounded to copy/
    # mkdir operations — but fail-closed is the rule.
    if [ -z "$CLAUDE_DIR" ] || [ "$CLAUDE_DIR" = "/" ] || [ "$CLAUDE_DIR" = "$HOME" ]; then
        echo "ERROR: CLAUDE_DIR is unsafe: '$CLAUDE_DIR'" >&2
        echo "       Must be a dedicated directory (e.g. \$HOME/.claude), not /, empty, or \$HOME itself." >&2
        exit 2
    fi
}

force_safety_guard() {
    assert_claude_dir_safe

    if ! is_live_system; then
        return 0  # fresh target — --force is safe, no backup needed.
    fi

    echo "WARNING: --force on a live system will overwrite $CLAUDE_DIR"
    echo "         TUNE-0003 incident: --force previously destroyed 9 runtime evolutions."
    echo ""

    if [ "$ASSUME_YES" = true ] || [ -n "$DATARIM_INSTALL_YES" ]; then
        echo "Auto-consent via --yes / DATARIM_INSTALL_YES."
    else
        if [ ! -t 0 ]; then
            echo "ERROR: non-TTY environment — refuse to prompt without --yes." >&2
            echo "       Re-run with --yes (or DATARIM_INSTALL_YES=1) if this is intentional." >&2
            exit 1
        fi
        printf "Type 'yes' to proceed (anything else aborts): "
        read -r confirm
        confirm="${confirm%$'\r'}"
        if [ "$confirm" != "yes" ]; then
            echo "Aborted by user."
            exit 1
        fi
    fi

    create_backup
}

create_backup() {
    local ts backup_dir scope
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_dir="$CLAUDE_DIR/backups/force-$ts"
    mkdir -p "$backup_dir"

    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -d "$CLAUDE_DIR/$scope" ]; then
            cp -R "$CLAUDE_DIR/$scope" "$backup_dir/"
        fi
    done

    # Marker is written last — its presence signals a complete backup. Tests
    # and operators can rely on SUCCESS to distinguish a partial copy from a
    # usable snapshot.
    {
        echo "backup_created_at=$ts"
        echo "source=$CLAUDE_DIR"
        echo "scopes=${INSTALL_SCOPES[*]}"
    } > "$backup_dir/SUCCESS"

    echo "Backup created: $backup_dir"
    echo ""
}

# --- Copy logic -------------------------------------------------------------

has_allowed_extension() {
    local name="$1" ext allowed
    # Skip dotfiles and files with no extension.
    case "$name" in
        .*)       return 1 ;;
        *.*)      ext="${name##*.}" ;;
        *)        return 1 ;;
    esac
    for allowed in "${INSTALL_EXTENSIONS[@]}"; do
        if [ "$ext" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}

copy_scope_tree() {
    local src_dir="$1"
    local dst_dir="$2"
    local depth="${3:-0}"
    local count=0
    local entry bname

    mkdir -p "$dst_dir"

    for entry in "$src_dir"/*; do
        [ -e "$entry" ] || continue
        bname="$(basename "$entry")"

        # Paranoia: basename should never contain /, refuse if it does.
        case "$bname" in
            */*) echo "  SKIP (unsafe name): $bname" >&2; continue ;;
        esac

        if [ -d "$entry" ]; then
            echo "  DIR:  ${bname}/"
            copy_scope_tree "$entry" "$dst_dir/$bname" $((depth + 1))
            count=$((count + 1))
            continue
        fi

        if ! has_allowed_extension "$bname"; then
            case "$bname" in
                .*) : ;;  # silently ignore dotfiles (.DS_Store, editor temps)
                *)  echo "  WARN (unknown extension, skipped): $bname" ;;
            esac
            continue
        fi

        if [ "$FORCE" = false ] && [ -f "$dst_dir/$bname" ]; then
            echo "  SKIP (exists): $bname"
            SKIPPED=$((SKIPPED + 1))
        else
            cp "$entry" "$dst_dir/$bname"
            case "$bname" in
                *.sh) chmod +x "$dst_dir/$bname" 2>/dev/null || true ;;
            esac
            echo "  COPY: $bname"
            COPIED=$((COPIED + 1))
        fi
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ] && [ "$depth" -eq 0 ]; then
        echo "  (no files found in $src_dir)"
    fi
}

# --- Main -------------------------------------------------------------------

parse_args "$@"

VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
echo "Datarim Framework Installer v$VERSION"
echo "================================="
echo ""
echo "Source:  $SCRIPT_DIR"
echo "Target:  $CLAUDE_DIR"
if [ "$FORCE" = true ]; then
    echo "Mode:    force (overwrite)"
else
    echo "Mode:    merge (skip existing)"
fi
echo ""

if [ "$FORCE" = true ]; then
    force_safety_guard
else
    # In merge mode we still want CLAUDE_DIR to be non-catastrophic, but we
    # do not need --force-class confirmation because nothing gets overwritten.
    if [ -z "$CLAUDE_DIR" ]; then
        echo "ERROR: CLAUDE_DIR is empty." >&2
        exit 2
    fi
fi

for scope in "${INSTALL_SCOPES[@]}"; do
    mkdir -p "$CLAUDE_DIR/$scope"
done

for scope in "${INSTALL_SCOPES[@]}"; do
    echo "Installing $scope..."
    copy_scope_tree "$SCRIPT_DIR/$scope" "$CLAUDE_DIR/$scope"
    echo ""
done

echo "================================="
echo "Done! Copied: $COPIED, Skipped: $SKIPPED"
echo ""
echo "Next steps:"
echo "  1. Copy CLAUDE.md to your project root:"
echo "     cp $SCRIPT_DIR/CLAUDE.md /path/to/your/project/"
echo ""
echo "  2. Customize the project-specific section at the bottom of CLAUDE.md"
echo ""
echo "  3. Start Claude Code and run: /dr-init <task description>"
echo ""

if [ "$SKIPPED" -gt 0 ] && [ "$FORCE" = false ]; then
    echo "Note: $SKIPPED file(s) were skipped because they already exist."
    echo "      Use --force to overwrite (safe: a backup is taken automatically"
    echo "      on live systems): ./install.sh --force"
    echo ""
fi

#!/usr/bin/env bash
# curate-runtime.sh — copy drifted files from runtime ($CLAUDE_DIR) into repo
#
# Companion to check-drift.sh (read-only advisory). This script performs the
# actual copy: runtime → repo, with optional patch-bump of VERSION/CLAUDE.md/
# README.md. Three modes: --dry-run, --auto, --interactive (default).
#
# SCOPES must match check-drift.sh and install.sh (TUNE-0004 AC-3).
#
# Usage:
#   ./scripts/curate-runtime.sh                # interactive (default)
#   ./scripts/curate-runtime.sh --dry-run      # show plan, no writes
#   ./scripts/curate-runtime.sh --auto         # copy differ+new, skip delete
#   ./scripts/curate-runtime.sh --no-bump      # skip version patch-bump
#   ./scripts/curate-runtime.sh --help
#
# Environment:
#   CLAUDE_DIR          runtime dir (default: $HOME/.claude)
#   DATARIM_REPO_DIR    repo dir override (default: derived from script location;
#                       used by bats tests to point at a temp mock repo)
#
# Exit codes:
#   0  success (changes made or nothing to do)
#   1  error (missing dir, bad args)
#   2  user abort

set -euo pipefail

SCRIPT_DIR="${DATARIM_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SCOPES=(agents skills commands templates)

MODE="interactive"  # interactive | dry-run | auto
DO_BUMP=true
COPIED=0
NEW_COPIED=0
DELETED=0
SKIPPED=0

# --- Argument parsing -------------------------------------------------------

print_usage() {
    cat <<'USAGE'
curate-runtime.sh — copy drifted runtime files into repo

Usage:
  curate-runtime.sh                 Interactive mode (default)
  curate-runtime.sh --dry-run       Show what would be done, no writes
  curate-runtime.sh --auto          Copy differ+new files, skip deletes
  curate-runtime.sh --interactive   Same as default
  curate-runtime.sh --no-bump       Skip version patch-bump
  curate-runtime.sh --help          Show this message

Environment:
  CLAUDE_DIR         Runtime directory (default: $HOME/.claude)
  DATARIM_REPO_DIR   Repo directory override (default: derived from script path)
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      MODE="dry-run"; shift ;;
        --auto)         MODE="auto"; shift ;;
        --interactive)  MODE="interactive"; shift ;;
        --no-bump)      DO_BUMP=false; shift ;;
        --help|-h)      print_usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# v1.17.0 (TUNE-0033 AC-8): deprecation banner. With symlink-mode installs the
# concept of "curate runtime → repo" is empty (runtime IS the repo). Copy-mode
# users still need this until v1.18 (TUNE-0044) when both scripts go away.
cat >&2 <<'WARN'
============================================================
DEPRECATED in v1.17.0 (TUNE-0033)

curate-runtime.sh is needed only for copy-mode installs.
Symlink-mode installs (default since v1.17.0) have no drift —
runtime IS the repo. Edit files in the repo, then 'git commit'.

This script will be REMOVED in v1.18.0 (TUNE-0044).
See: docs/getting-started.md
============================================================
WARN

# --- Validation -------------------------------------------------------------

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: runtime dir not found: $CLAUDE_DIR" >&2
    exit 1
fi

if [ ! -d "$SCRIPT_DIR/agents" ]; then
    echo "ERROR: repo dir looks wrong (no agents/): $SCRIPT_DIR" >&2
    exit 1
fi

# --- TTY check (interactive mode requires terminal) --------------------------

if [ "$MODE" = "interactive" ] && [ ! -t 0 ]; then
    echo "ERROR: interactive mode requires a TTY (stdin is not a terminal)." >&2
    echo "       Use --auto for non-interactive environments, or --dry-run to preview." >&2
    exit 1
fi

echo "Datarim Curation: runtime → repo"
echo "================================="
echo "Runtime: $CLAUDE_DIR"
echo "Repo:    $SCRIPT_DIR"
echo "Mode:    $MODE"
echo ""

# --- Prompt helper (interactive mode) ----------------------------------------

ACCEPT_ALL=false

prompt_action() {
    local label="$1"
    if [ "$ACCEPT_ALL" = true ]; then return 0; fi

    while true; do
        # Prompt via printf to stdout (not read -p which uses stderr —
        # some terminals like Amazon WorkSpaces / IDE terminals don't show stderr prompts)
        printf "  %s? (y)es/(n)o/(a)ll/(s)kip-rest: " "$label"
        read -r choice || {
            echo ""
            echo "  EOF on stdin — aborting." >&2
            exit 2
        }
        choice="${choice%$'\r'}"  # Strip trailing CR (CRLF terminals)
        case "$choice" in
            y|Y|yes)  return 0 ;;
            n|N|no)   return 1 ;;
            a|A|all)  ACCEPT_ALL=true; return 0 ;;
            s|S|skip) return 2 ;;
            *)        echo "  Please enter y, n, a, or s." ;;
        esac
    done
}

# --- Process each scope -----------------------------------------------------

for scope in "${SCOPES[@]}"; do
    runtime_dir="$CLAUDE_DIR/$scope"
    repo_dir="$SCRIPT_DIR/$scope"

    if [ ! -d "$runtime_dir" ]; then
        echo "[$scope] SKIP — not in runtime"
        continue
    fi

    # Symlink detection: if runtime dir is a symlink pointing at repo dir,
    # diff -rq compares a directory with itself and always says "in sync".
    if [ -L "$runtime_dir" ]; then
        resolved=$(cd -P "$runtime_dir" && pwd)
        repo_resolved=$(cd -P "$repo_dir" 2>/dev/null && pwd || echo "")
        if [ "$resolved" = "$repo_resolved" ]; then
            echo "[$scope] SYMLINK → repo (same directory, drift detection impossible)"
            echo "         Tip: remove symlink and run install.sh to create real copies"
            continue
        fi
        echo "[$scope] NOTE: runtime is a symlink → $resolved"
    fi

    mkdir -p "$repo_dir"

    DIFF_OUT=$(diff -rq "$runtime_dir/" "$repo_dir/" 2>/dev/null || true)
    if [ -z "$DIFF_OUT" ]; then
        echo "[$scope] in sync"
        continue
    fi

    while IFS= read -r line; do
        # Pattern: "Files <A> and <B> differ"
        if [[ "$line" =~ ^Files\ (.+)\ and\ (.+)\ differ$ ]]; then
            src="${BASH_REMATCH[1]}"
            dst="${BASH_REMATCH[2]}"
            # Validate paths
            if [[ "$src" != "$runtime_dir/"* ]] || [[ "$dst" != "$repo_dir/"* ]]; then
                echo "  WARN: unexpected paths in diff output, skipping: $line"
                continue
            fi
            relpath="${src#"$runtime_dir/"}"

            case "$MODE" in
                dry-run)
                    echo "  [DRY-RUN] COPY $scope/$relpath"
                    SKIPPED=$((SKIPPED + 1))
                    ;;
                auto)
                    mkdir -p "$(dirname "$dst")"
                    cp "$src" "$dst"
                    echo "  COPY $scope/$relpath"
                    COPIED=$((COPIED + 1))
                    ;;
                interactive)
                    prompt_action "COPY $scope/$relpath" && rc=0 || rc=$?
                    if [ "$rc" -eq 0 ]; then
                        mkdir -p "$(dirname "$dst")"
                        cp "$src" "$dst"
                        echo "  COPIED $scope/$relpath"
                        COPIED=$((COPIED + 1))
                    elif [ "$rc" -eq 2 ]; then
                        echo "  SKIP-REST (remaining in $scope)"
                        SKIPPED=$((SKIPPED + 1))
                        break
                    else
                        echo "  SKIP $scope/$relpath"
                        SKIPPED=$((SKIPPED + 1))
                    fi
                    ;;
            esac

        # Pattern: "Only in <dir>: <name>"
        elif [[ "$line" =~ ^Only\ in\ (.+):\ (.+)$ ]]; then
            dir="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"

            if [[ "$dir" == "$runtime_dir"* ]]; then
                # File exists in runtime but not in repo → NEW
                subdir="${dir#"$runtime_dir"}"
                subdir="${subdir#/}"
                relpath="${subdir:+$subdir/}$name"

                case "$MODE" in
                    dry-run)
                        echo "  [DRY-RUN] NEW  $scope/$relpath"
                        SKIPPED=$((SKIPPED + 1))
                        ;;
                    auto)
                        mkdir -p "$repo_dir/${subdir:-.}"
                        cp -R "$runtime_dir/$relpath" "$repo_dir/$relpath"
                        echo "  NEW  $scope/$relpath"
                        NEW_COPIED=$((NEW_COPIED + 1))
                        ;;
                    interactive)
                        prompt_action "NEW  $scope/$relpath (copy from runtime)" && rc=0 || rc=$?
                        if [ "$rc" -eq 0 ]; then
                            mkdir -p "$repo_dir/${subdir:-.}"
                            cp -R "$runtime_dir/$relpath" "$repo_dir/$relpath"
                            echo "  ADDED $scope/$relpath"
                            NEW_COPIED=$((NEW_COPIED + 1))
                        elif [ "$rc" -eq 2 ]; then
                            echo "  SKIP-REST (remaining in $scope)"
                            SKIPPED=$((SKIPPED + 1))
                            break
                        else
                            echo "  SKIP $scope/$relpath"
                            SKIPPED=$((SKIPPED + 1))
                        fi
                        ;;
                esac

            elif [[ "$dir" == "$repo_dir"* ]]; then
                # File exists in repo but not in runtime → DELETED
                subdir="${dir#"$repo_dir"}"
                subdir="${subdir#/}"
                relpath="${subdir:+$subdir/}$name"

                case "$MODE" in
                    dry-run)
                        echo "  [DRY-RUN] DELETE $scope/$relpath (gone from runtime)"
                        SKIPPED=$((SKIPPED + 1))
                        ;;
                    auto)
                        echo "  WARN: $scope/$relpath gone from runtime — skipped (use --interactive to delete)"
                        SKIPPED=$((SKIPPED + 1))
                        ;;
                    interactive)
                        prompt_action "DELETE $scope/$relpath (gone from runtime)" && rc=0 || rc=$?
                        if [ "$rc" -eq 0 ]; then
                            rm -f "$repo_dir/$relpath"
                            echo "  DELETED $scope/$relpath"
                            DELETED=$((DELETED + 1))
                        elif [ "$rc" -eq 2 ]; then
                            echo "  SKIP-REST (remaining in $scope)"
                            SKIPPED=$((SKIPPED + 1))
                            break
                        else
                            echo "  SKIP $scope/$relpath"
                            SKIPPED=$((SKIPPED + 1))
                        fi
                        ;;
                esac
            fi
        fi
    done <<< "$DIFF_OUT"
done

# --- Patch-bump --------------------------------------------------------------

TOTAL_CHANGES=$((COPIED + NEW_COPIED + DELETED))

if [ "$TOTAL_CHANGES" -gt 0 ] && [ "$DO_BUMP" = true ]; then
    VERSION_FILE="$SCRIPT_DIR/VERSION"
    if [ -f "$VERSION_FILE" ]; then
        OLD_VER=$(cat "$VERSION_FILE" | tr -d '[:space:]')
        IFS='.' read -r major minor patch <<< "$OLD_VER"
        NEW_VER="$major.$minor.$((patch + 1))"
        echo "$NEW_VER" > "$VERSION_FILE"

        # Update CLAUDE.md (portable sed: temp file + mv, works on both BSD and GNU)
        CLAUDE_FILE="$SCRIPT_DIR/CLAUDE.md"
        if [ -f "$CLAUDE_FILE" ]; then
            sed "s/> \*\*Version:\*\* $OLD_VER/> **Version:** $NEW_VER/" "$CLAUDE_FILE" > "$CLAUDE_FILE.tmp" && mv "$CLAUDE_FILE.tmp" "$CLAUDE_FILE"
        fi

        # Update README.md badge (two occurrences on badge line)
        README_FILE="$SCRIPT_DIR/README.md"
        if [ -f "$README_FILE" ]; then
            sed "s/$OLD_VER/$NEW_VER/g" "$README_FILE" > "$README_FILE.tmp" && mv "$README_FILE.tmp" "$README_FILE"
        fi

        echo ""
        echo "Version bumped: $OLD_VER → $NEW_VER"
    fi
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "================================="
echo "Summary: $COPIED copied, $NEW_COPIED new, $DELETED deleted, $SKIPPED skipped"

if [ "$TOTAL_CHANGES" -gt 0 ]; then
    echo ""
    echo "Run ./scripts/check-drift.sh to verify sync."
fi

exit 0

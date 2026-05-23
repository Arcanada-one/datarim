#!/usr/bin/env bash
# cli/install.sh — standalone Datarim CLI installer (TUNE-0271 D-C).
#
# Contract:
#   1) Print bilingual AAL 3 warning every run (idempotent).
#   2) Validate accepted-risk-aal.yml entry tune-0268-aal3-cli present + not expired.
#   3) Symlink code/datarim/cli/datarim → $TARGET_BIN/datarim.
#      Default $TARGET_BIN = /usr/local/bin (writable) or $HOME/.local/bin (fallback).
#   4) `--uninstall` removes the symlink and prints residual cleanup hint.
#   5) `--dry-run` prints planned actions without writing.
#
# Exit codes:
#   0   ok
#   2   usage error
#   23  accepted-risk-aal entry missing/expired

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WARNING="$SCRIPT_DIR/install-warning.sh"
VALIDATOR="$REPO_ROOT/dev-tools/check-accepted-risk-aal.sh"
BIN_SRC="$SCRIPT_DIR/datarim"

mode=install
dry_run=0
target_bin=""

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) mode=uninstall; shift ;;
        --dry-run) dry_run=1; shift ;;
        --target-bin) target_bin="${2:-}"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: cli/install.sh [--uninstall] [--dry-run] [--target-bin DIR]
EOF
            exit 0 ;;
        *) printf '[install] unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
done

_resolve_target_bin() {
    if [ -n "$target_bin" ]; then printf '%s' "$target_bin"; return 0; fi
    for cand in /usr/local/bin "$HOME/.local/bin"; do
        if [ -d "$cand" ] && [ -w "$cand" ]; then
            printf '%s' "$cand"; return 0
        fi
    done
    mkdir -p "$HOME/.local/bin"
    printf '%s' "$HOME/.local/bin"
}

bin_dir="$(_resolve_target_bin)"
target_link="$bin_dir/datarim"

[ -x "$WARNING" ] && "$WARNING" || cat "$WARNING"

if [ "$mode" = "uninstall" ]; then
    if [ "$dry_run" = "1" ]; then
        printf '[install] dry-run: would remove %s\n' "$target_link"
        exit 0
    fi
    rm -f "$target_link"
    printf '[install] removed: %s\n' "$target_link"
    printf '[install] residual cleanup (manual):\n'
    printf '          ~/.config/datarim-cli/HALT (if present)\n'
    printf '          datarim/audit/cli-audit-*.jsonl (workspace-level, gitignored)\n'
    exit 0
fi

# Install path — validate accepted-risk-aal before symlink.
if [ ! -x "$VALIDATOR" ]; then
    printf '[install] validator not found: %s\n' "$VALIDATOR" >&2
    exit 1
fi
if ! "$VALIDATOR" --task TUNE-0268; then
    rc=$?
    printf '[install] accepted-risk-aal validation failed (exit %s); refusing install\n' "$rc" >&2
    exit "$rc"
fi

if [ "$dry_run" = "1" ]; then
    printf '[install] dry-run: would symlink %s → %s\n' "$BIN_SRC" "$target_link"
    exit 0
fi

ln -sfn "$BIN_SRC" "$target_link"
chmod +x "$BIN_SRC" 2>/dev/null || true
printf '[install] symlinked: %s → %s\n' "$target_link" "$BIN_SRC"
printf '[install] next: set DATARIM_CLI_AGENT_ID to a UUID v7 (see docs/cli.md)\n'

#!/usr/bin/env bash
# dr-plugin.sh — Datarim Plugin System CLI (TUNE-0101, Phase A scaffold).
#
# Subcommands implemented in this slice:
#   list      — show active plugins (bootstraps datarim-core on first run)
#   --help    — usage
#
# Subcommands deferred to next /dr-do round (Phase A3-D):
#   enable / disable / sync / doctor
#
# Environment:
#   DR_PLUGIN_WORKSPACE     — workspace root containing datarim/ (default: cwd
#                             walk-up). Honoured by tests for sandboxed runs.
#   DR_PLUGIN_RUNTIME_ROOT  — symlink target root (default: $HOME/.claude/local).
#                             Honoured by tests for sandboxed runs.
#
# Exit codes:
#   0   success
#   1   recoverable error (validation, conflict)
#   2   IO / filesystem error
#   3   concurrent invocation (lock held)
#   64  usage error
#
# Source: PRD-TUNE-0101, plans/TUNE-0101-plan.md § Phase A.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/plugin-system.sh
. "$SCRIPT_DIR/lib/plugin-system.sh"

# --- workspace resolution ----------------------------------------------------

resolve_workspace() {
    if [ -n "${DR_PLUGIN_WORKSPACE:-}" ]; then
        echo "$DR_PLUGIN_WORKSPACE"
        return 0
    fi
    # Walk up from cwd looking for datarim/ marker.
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/datarim" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "dr-plugin: datarim/ not found in cwd or any parent. Run /dr-init." >&2
    return 2
}

resolve_runtime_root() {
    if [ -n "${DR_PLUGIN_RUNTIME_ROOT:-}" ]; then
        echo "$DR_PLUGIN_RUNTIME_ROOT"
    else
        echo "$HOME/.claude/local"
    fi
}

resolve_repo_root() {
    # Datarim repo root: contains code/datarim/{templates,VERSION} when invoked
    # in a workspace, or this script's grandparent dir otherwise.
    local ws="$1"
    if [ -d "$ws/code/datarim/templates" ] && [ -f "$ws/code/datarim/VERSION" ]; then
        echo "$ws/code/datarim"
    else
        # Repo-mode: this script lives at <repo>/scripts/dr-plugin.sh.
        echo "$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
}

# --- usage -------------------------------------------------------------------

usage() {
    cat <<'EOF'
dr-plugin — Datarim Plugin System CLI (TUNE-0101)

USAGE:
  dr-plugin <command> [args]

COMMANDS:
  list                  Show active plugins (bootstraps datarim-core on first run)
  enable <id|path|url>  Activate a plugin (Phase A3 — not yet implemented)
  disable <id>          Deactivate a plugin (Phase A3 — not yet implemented)
  sync                  Reconcile filesystem with manifest (Phase C — not yet implemented)
  doctor [--fix]        Diagnose inconsistent state (Phase D — not yet implemented)
  --help                Show this message

EXIT CODES:
  0   success
  1   validation/conflict error
  2   I/O / filesystem error
  3   concurrent invocation (lock held)
  64  usage error

Source: PRD-TUNE-0101, plans/TUNE-0101-plan.md.
EOF
}

# --- first-run bootstrap -----------------------------------------------------

bootstrap_manifest_if_missing() {
    local manifest="$1"
    local repo_root="$2"

    if [ -f "$manifest" ]; then
        return 0
    fi

    local version
    if [ -f "$repo_root/VERSION" ]; then
        version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
    else
        version="unknown"
    fi
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    mkdir -p "$(dirname "$manifest")"

    cat > "$manifest" <<EOF
# Enabled Plugins

<!-- Managed by /dr-plugin (TUNE-0101). Manual edits → run /dr-plugin sync. -->

## Active

- id: datarim-core
  source: builtin
  version: $version
  enabled_at: $now
  protected: true
  file_inventory:
    skills: []
    agents: []
    commands: []
    templates: []
EOF

    echo "dr-plugin: bootstrapped $manifest with protected datarim-core entry." >&2
}

# --- list subcommand ---------------------------------------------------------

cmd_list() {
    local ws repo_root manifest
    ws="$(resolve_workspace)"
    repo_root="$(resolve_repo_root "$ws")"
    manifest="$ws/datarim/enabled-plugins.md"

    bootstrap_manifest_if_missing "$manifest" "$repo_root"

    echo "Active plugins (manifest: $manifest):"
    echo

    # Render each "- id: <foo>" block with key fields. Bash 3.2 friendly: no
    # associative arrays, just sequential awk walk emitting one line per plugin.
    awk '
        BEGIN { id=""; src=""; ver=""; prot="" }
        /^- id:/ {
            if (id != "") {
                printf "  - %-24s  source=%-12s  version=%-12s  %s\n", id, src, ver, (prot=="true"?"[protected]":"")
                id=""; src=""; ver=""; prot=""
            }
            sub(/^- id:[[:space:]]*/, "")
            id = $0
            next
        }
        /^[[:space:]]+source:/ {
            line = $0
            sub(/^[[:space:]]+source:[[:space:]]*/, "", line)
            src = line
            next
        }
        /^[[:space:]]+version:/ {
            line = $0
            sub(/^[[:space:]]+version:[[:space:]]*/, "", line)
            ver = line
            next
        }
        /^[[:space:]]+protected:/ {
            line = $0
            sub(/^[[:space:]]+protected:[[:space:]]*/, "", line)
            prot = line
            next
        }
        END {
            if (id != "") {
                printf "  - %-24s  source=%-12s  version=%-12s  %s\n", id, src, ver, (prot=="true"?"[protected]":"")
            }
        }
    ' "$manifest"
}

# --- main dispatcher ---------------------------------------------------------

main() {
    if [ $# -eq 0 ]; then
        usage >&2
        exit 64
    fi

    local cmd="$1"
    shift || true

    case "$cmd" in
        list)
            cmd_list "$@"
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        enable|disable|sync|doctor)
            echo "dr-plugin: '$cmd' not yet implemented (TUNE-0101 Phase A3+)." >&2
            exit 1
            ;;
        *)
            echo "dr-plugin: unknown subcommand: $cmd" >&2
            usage >&2
            exit 64
            ;;
    esac
}

main "$@"

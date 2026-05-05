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

# --- enable subcommand ------------------------------------------------------

DR_PLUGIN_LOCK_TIMEOUT="${DR_PLUGIN_LOCK_TIMEOUT:-60}"

_lock_path() {
    local ws="$1"
    echo "$ws/datarim/.locks/plugin.lock"
}

_categories_allowed() {
    case "$1" in
        skills|agents|commands|templates) return 0 ;;
        *) return 1 ;;
    esac
}

_collect_inventory_for() {
    # Echo basenames of regular files under <src>/<cat>/, skipping dotfiles.
    local src="$1" cat="$2"
    local cat_dir="$src/$cat"
    [ -d "$cat_dir" ] || return 0
    local f bn
    for f in "$cat_dir"/*; do
        [ -f "$f" ] || continue
        bn="$(basename "$f")"
        case "$bn" in .*) continue ;; esac
        echo "$bn"
    done
}

cmd_enable() {
    local src_arg="${1:-}"
    if [ -z "$src_arg" ]; then
        echo "dr-plugin enable: source path required" >&2
        return 64
    fi

    case "$src_arg" in
        *..*)
            echo "dr-plugin enable: path traversal not allowed: $src_arg" >&2
            return 1
            ;;
    esac

    local src
    case "$src_arg" in
        /*)  src="$src_arg" ;;
        https://*|http://*)
            echo "dr-plugin enable: git URL clone not yet implemented (Phase A4)" >&2
            return 1
            ;;
        *)
            echo "dr-plugin enable: source must be absolute path: $src_arg" >&2
            return 1
            ;;
    esac

    if [ ! -d "$src" ]; then
        echo "dr-plugin enable: source directory not found: $src" >&2
        return 1
    fi

    local yaml="$src/plugin.yaml"
    if [ ! -f "$yaml" ]; then
        echo "dr-plugin enable: plugin.yaml not found in $src" >&2
        return 1
    fi

    local schema_v
    schema_v="$(parse_plugin_yaml "$yaml" schema_version)"
    if [ "$schema_v" != "1" ]; then
        echo "dr-plugin enable: unsupported schema_version: '$schema_v' (expected 1)" >&2
        return 1
    fi

    local id
    id="$(parse_plugin_yaml "$yaml" id)"
    if ! validate_plugin_id "$id"; then
        return 1
    fi

    local ws repo manifest
    ws="$(resolve_workspace)"
    repo="$(resolve_repo_root "$ws")"
    manifest="$ws/datarim/enabled-plugins.md"
    bootstrap_manifest_if_missing "$manifest" "$repo"

    local lock_dir
    lock_dir="$(_lock_path "$ws")"
    mkdir -p "$(dirname "$lock_dir")"
    if ! acquire_plugin_lock "$lock_dir" "$DR_PLUGIN_LOCK_TIMEOUT"; then
        echo "dr-plugin enable: lock busy: $lock_dir" >&2
        return 3
    fi
    # shellcheck disable=SC2064
    trap "release_plugin_lock '$lock_dir'" EXIT INT TERM

    if manifest_has_entry "$manifest" "$id"; then
        local existing
        existing="$(manifest_field "$manifest" "$id" source)"
        if [ "$existing" = "$src" ]; then
            echo "dr-plugin enable: $id already enabled (idempotent)." >&2
            return 0
        fi
        echo "dr-plugin enable: $id already enabled with different source: $existing" >&2
        return 1
    fi

    local runtime
    runtime="$(resolve_runtime_root)"

    local cats cat
    cats="$(parse_yaml_list "$yaml" categories)"

    # Validate categories.
    for cat in $cats; do
        if ! _categories_allowed "$cat"; then
            echo "dr-plugin enable: unknown category: $cat" >&2
            return 1
        fi
    done

    # Pre-scan conflict.
    local target_dir target bn
    for cat in $cats; do
        target_dir="$runtime/$cat/$id"
        # Reject if a non-directory exists at the target dir path.
        if [ -e "$runtime/$cat/$id" ] && [ ! -d "$runtime/$cat/$id" ]; then
            echo "dr-plugin enable: conflict at $runtime/$cat/$id (regular file blocks plugin namespace)" >&2
            return 1
        fi
        # Per-file conflict: target file exists but is not our own symlink.
        local files
        files="$(_collect_inventory_for "$src" "$cat")"
        for bn in $files; do
            target="$target_dir/$bn"
            if [ -e "$target" ] && [ ! -L "$target" ]; then
                echo "dr-plugin enable: conflict: $target already exists" >&2
                return 1
            fi
        done
    done

    # Apply: create symlinks.
    local files src_file
    for cat in $cats; do
        files="$(_collect_inventory_for "$src" "$cat")"
        [ -n "$files" ] || continue
        target_dir="$runtime/$cat/$id"
        mkdir -p "$target_dir"
        for bn in $files; do
            src_file="$src/$cat/$bn"
            ln -sfn "$src_file" "$target_dir/$bn"
        done
    done

    # Build inventory strings (for inline list YAML).
    local skills_inv agents_inv commands_inv templates_inv
    skills_inv="$(_collect_inventory_for "$src" skills | paste -sd ',' - | sed 's/,/, /g')"
    agents_inv="$(_collect_inventory_for "$src" agents | paste -sd ',' - | sed 's/,/, /g')"
    commands_inv="$(_collect_inventory_for "$src" commands | paste -sd ',' - | sed 's/,/, /g')"
    templates_inv="$(_collect_inventory_for "$src" templates | paste -sd ',' - | sed 's/,/, /g')"

    local now version depends dep
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    version="$(parse_plugin_yaml "$yaml" version)"
    depends="$(parse_yaml_list "$yaml" depends_on)"

    {
        echo ""
        echo "- id: $id"
        echo "  source: $src"
        echo "  version: $version"
        echo "  enabled_at: $now"
        if [ -n "$depends" ]; then
            echo "  depends_on:"
            for dep in $depends; do
                echo "    - $dep"
            done
        fi
        echo "  file_inventory:"
        echo "    skills: [$skills_inv]"
        echo "    agents: [$agents_inv]"
        echo "    commands: [$commands_inv]"
        echo "    templates: [$templates_inv]"
    } >> "$manifest"

    echo "dr-plugin: enabled $id (source: $src)" >&2
    return 0
}

# --- disable subcommand -----------------------------------------------------

cmd_disable() {
    local id="${1:-}"
    if [ -z "$id" ]; then
        echo "dr-plugin disable: plugin id required" >&2
        return 64
    fi
    if ! validate_plugin_id "$id"; then
        return 1
    fi

    local ws repo manifest
    ws="$(resolve_workspace)"
    repo="$(resolve_repo_root "$ws")"
    manifest="$ws/datarim/enabled-plugins.md"
    bootstrap_manifest_if_missing "$manifest" "$repo"

    local lock_dir
    lock_dir="$(_lock_path "$ws")"
    mkdir -p "$(dirname "$lock_dir")"
    if ! acquire_plugin_lock "$lock_dir" "$DR_PLUGIN_LOCK_TIMEOUT"; then
        echo "dr-plugin disable: lock busy: $lock_dir" >&2
        return 3
    fi
    # shellcheck disable=SC2064
    trap "release_plugin_lock '$lock_dir'" EXIT INT TERM

    if ! manifest_has_entry "$manifest" "$id"; then
        echo "dr-plugin disable: $id not enabled" >&2
        return 1
    fi

    local protected
    protected="$(manifest_field "$manifest" "$id" protected)"
    if [ "$protected" = "true" ]; then
        echo "dr-plugin disable: $id is protected (e.g. datarim-core)" >&2
        return 1
    fi

    local deps
    deps="$(manifest_dependents_of "$manifest" "$id")"
    if [ -n "$deps" ]; then
        echo "dr-plugin disable: $id has active dependents:" >&2
        local d
        for d in $deps; do
            echo "  - $d" >&2
        done
        return 1
    fi

    # Remove symlinks (whole plugin subdir under each category).
    local runtime cat target_dir
    runtime="$(resolve_runtime_root)"
    for cat in skills agents commands templates; do
        target_dir="$runtime/$cat/$id"
        [ -d "$target_dir" ] || continue
        rm -rf "$target_dir"
    done

    manifest_remove_entry "$manifest" "$id"
    echo "dr-plugin: disabled $id" >&2
    return 0
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
        enable)
            cmd_enable "$@"
            ;;
        disable)
            cmd_disable "$@"
            ;;
        sync|doctor)
            echo "dr-plugin: '$cmd' not yet implemented (TUNE-0101 Phase C/D)." >&2
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

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

# Set of core skills/agents/commands whose override should warn the operator.
# Override is allowed but flagged because shadowing these can break workflow
# integrity (history-agnostic gate, evolution loop, archive contract).
DR_PLUGIN_CRITICAL_CORE="evolution datarim-system pre-archive-check"

_is_override_basename() {
    # Return 0 if basename's stem (everything before final dot) is in the
    # space-separated overrides list.
    local bn="$1"
    local overrides="$2"
    local stem="${bn%.*}"
    case " $overrides " in
        *" $stem "*) return 0 ;;
        *)           return 1 ;;
    esac
}

_manifest_overrides_of() {
    # Echo each "  - <ov>" line under <id>'s "  overrides:" key.
    local manifest="$1" id="$2"
    [ -f "$manifest" ] || return 1
    awk -v id="$id" '
        BEGIN { in_block = 0; in_ov = 0 }
        /^- id: / {
            in_block = ($0 == "- id: " id) ? 1 : 0
            in_ov = 0
            next
        }
        in_block && /^[[:space:]]+overrides:[[:space:]]*$/ { in_ov = 1; next }
        in_ov && /^[[:space:]]+-[[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]+-[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            next
        }
        in_ov && /^[[:space:]]+[a-z_]+:/ { in_ov = 0 }
    ' "$manifest"
}

_warn_critical_core_overrides() {
    local id="$1" overrides="$2" ov
    for ov in $overrides; do
        case " $DR_PLUGIN_CRITICAL_CORE " in
            *" $ov "*)
                echo "WARNING: plugin '$id' overrides critical core skill '$ov' — shadowing this can break framework workflow integrity" >&2
                ;;
        esac
    done
}

_validate_overrides_shipped() {
    # For each override stem, verify a file <stem>.<ext> exists in at least one
    # of the plugin's declared categories. Returns 0 on success, 1 on missing.
    local src="$1" cats="$2" overrides="$3"
    local ov cat found f
    for ov in $overrides; do
        found=0
        for cat in $cats; do
            for f in "$src/$cat/$ov".*; do
                [ -e "$f" ] && { found=1; break; }
            done
            [ $found -eq 1 ] && break
        done
        if [ $found -ne 1 ]; then
            echo "dr-plugin enable: override '$ov' has no matching shipped file in plugin's category dirs" >&2
            return 1
        fi
    done
    return 0
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

    # Snapshot pre-mutation state so we can roll back on mid-apply failure
    # (TUNE-0101 Phase C, V-8). Snapshot is taken after lock acquisition so
    # concurrent invocations cannot race the snapshot itself.
    local _snap=""
    local runtime_pre
    runtime_pre="$(resolve_runtime_root)"
    _snap="$(snapshot_create "$ws" "$runtime_pre" "$manifest")" || {
        echo "dr-plugin enable: snapshot failed" >&2
        return 2
    }

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

    # Parse overrides + validate they are shipped by the plugin.
    local overrides_list
    overrides_list="$(parse_yaml_list "$yaml" overrides)"
    if [ -n "$overrides_list" ]; then
        if ! _validate_overrides_shipped "$src" "$cats" "$overrides_list"; then
            return 1
        fi
        _warn_critical_core_overrides "$id" "$overrides_list"
    fi

    # Pre-scan conflict.
    local target_dir target bn target_pos files
    for cat in $cats; do
        target_dir="$runtime/$cat/$id"
        # Reject if a non-directory exists at the target dir path.
        if [ -e "$runtime/$cat/$id" ] && [ ! -d "$runtime/$cat/$id" ]; then
            echo "dr-plugin enable: conflict at $runtime/$cat/$id (regular file blocks plugin namespace)" >&2
            return 1
        fi
        files="$(_collect_inventory_for "$src" "$cat")"
        for bn in $files; do
            if _is_override_basename "$bn" "$overrides_list"; then
                # Override path: root position competes with core via local overlay.
                target="$runtime/$cat/$bn"
            else
                target="$target_dir/$bn"
            fi
            if [ -e "$target" ] && [ ! -L "$target" ]; then
                echo "dr-plugin enable: conflict: $target already exists (regular file)" >&2
                return 1
            fi
            # Symlink already pointing somewhere outside this plugin's source → conflict.
            if [ -L "$target" ]; then
                local existing_target
                existing_target="$(readlink "$target")"
                case "$existing_target" in
                    "$src"/*) : ;;  # ours, idempotent path
                    *)
                        echo "dr-plugin enable: override conflict: $target already symlinked to $existing_target" >&2
                        return 1
                        ;;
                esac
            fi
        done
    done

    # Apply: create symlinks at correct position per override status.
    local src_file
    for cat in $cats; do
        files="$(_collect_inventory_for "$src" "$cat")"
        [ -n "$files" ] || continue
        target_dir="$runtime/$cat/$id"
        for bn in $files; do
            src_file="$src/$cat/$bn"
            if _is_override_basename "$bn" "$overrides_list"; then
                target_pos="$runtime/$cat/$bn"
            else
                mkdir -p "$target_dir"
                target_pos="$target_dir/$bn"
            fi
            ln -sfn "$src_file" "$target_pos"
        done
    done

    # Fault injection: fail right after symlinks created, before manifest write.
    if [ "${DR_PLUGIN_FAULT_INJECT:-}" = "after_symlinks" ]; then
        if [ -n "$_snap" ]; then
            restore_from_snapshot "$_snap" "$runtime_pre" "$manifest" || true
        fi
        echo "dr-plugin enable: fault injected (after_symlinks) — restored from $_snap" >&2
        return 2
    fi

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
        if [ -n "$overrides_list" ]; then
            echo "  overrides:"
            local ov
            for ov in $overrides_list; do
                echo "    - $ov"
            done
        fi
        echo "  file_inventory:"
        echo "    skills: [$skills_inv]"
        echo "    agents: [$agents_inv]"
        echo "    commands: [$commands_inv]"
        echo "    templates: [$templates_inv]"
    } >> "$manifest"

    # Fault injection (testing only): simulate post-apply failure to verify
    # snapshot rollback. DR_PLUGIN_FAULT_INJECT honoured values:
    #   after_symlinks  — fail before manifest is finalised (already applied
    #                     symlinks must be undone via snapshot restore).
    #   after_manifest  — fail after manifest is finalised (full rollback).
    # Production callers leave the variable unset.
    if [ -n "${DR_PLUGIN_FAULT_INJECT:-}" ]; then
        case "$DR_PLUGIN_FAULT_INJECT" in
            after_manifest|after_symlinks)
                if [ -n "$_snap" ]; then
                    restore_from_snapshot "$_snap" "$runtime_pre" "$manifest" || true
                fi
                echo "dr-plugin enable: fault injected ($DR_PLUGIN_FAULT_INJECT) — restored from $_snap" >&2
                return 2
                ;;
        esac
    fi

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

    # Remove namespaced symlinks (whole plugin subdir under each category).
    local runtime cat target_dir
    runtime="$(resolve_runtime_root)"
    for cat in skills agents commands templates; do
        target_dir="$runtime/$cat/$id"
        [ -d "$target_dir" ] || continue
        rm -rf "$target_dir"
    done

    # Remove root-positioned override symlinks. Read overrides list from manifest
    # entry; for each <ov>, scan all categories for `<runtime>/<cat>/<ov>.*` and
    # unlink only if symlink points back into our source dir (defensive check).
    local plugin_src ov f
    plugin_src="$(manifest_field "$manifest" "$id" source)"
    local overrides_in_manifest
    overrides_in_manifest="$(_manifest_overrides_of "$manifest" "$id")"
    for ov in $overrides_in_manifest; do
        for cat in skills agents commands templates; do
            for f in "$runtime/$cat/$ov".*; do
                [ -L "$f" ] || continue
                local linked
                linked="$(readlink "$f")"
                case "$linked" in
                    "$plugin_src"/*) rm -f "$f" ;;
                esac
            done
        done
    done

    manifest_remove_entry "$manifest" "$id"
    echo "dr-plugin: disabled $id" >&2
    return 0
}

# --- sync subcommand --------------------------------------------------------
#
# Reconciles runtime symlink tree with manifest. Three branches:
#   1. orphan  : symlink in runtime not declared by any active plugin → remove
#   2. broken  : declared inventory entry missing/dangling → recreate (ln -sfn)
#   3. disabled-orphan : <stem>.<id>.disabled backup whose plugin is gone → restore
#
# Idempotent. Acquires plugin lock.
# Source: plans/TUNE-0101-plan.md § Phase C, V-9.

cmd_sync() {
    local ws repo manifest runtime
    ws="$(resolve_workspace)"
    repo="$(resolve_repo_root "$ws")"
    manifest="$ws/datarim/enabled-plugins.md"
    bootstrap_manifest_if_missing "$manifest" "$repo"
    runtime="$(resolve_runtime_root)"

    local lock_dir
    lock_dir="$(_lock_path "$ws")"
    mkdir -p "$(dirname "$lock_dir")"
    if ! acquire_plugin_lock "$lock_dir" "$DR_PLUGIN_LOCK_TIMEOUT"; then
        echo "dr-plugin sync: lock busy: $lock_dir" >&2
        return 3
    fi
    # shellcheck disable=SC2064
    trap "release_plugin_lock '$lock_dir'" EXIT INT TERM

    local active_ids active_ids_padded id
    active_ids="$(manifest_active_ids "$manifest")"
    active_ids_padded=" $(echo $active_ids | tr '\n' ' ')"

    # Build inventory map: each line is "cat|key|src_path|mode" where
    # mode=root (override → runtime/<cat>/<basename>) or
    # mode=ns   (namespaced → runtime/<cat>/<id>/<basename>); key is the
    # rel-path under runtime/<cat>/.
    local inv_file
    inv_file="$(mktemp -t dr-plugin-inv.XXXXXX)"
    : > "$inv_file"

    for id in $active_ids; do
        local plugin_src overrides_list cat files bn
        plugin_src="$(manifest_field "$manifest" "$id" source)"
        overrides_list="$(_manifest_overrides_of "$manifest" "$id" | tr '\n' ' ')"
        for cat in skills agents commands templates; do
            files="$(manifest_inventory_of "$manifest" "$id" "$cat")"
            for bn in $files; do
                if _is_override_basename "$bn" "$overrides_list"; then
                    printf '%s|%s|%s|root\n' "$cat" "$bn" "$plugin_src/$cat/$bn" >> "$inv_file"
                else
                    printf '%s|%s|%s|ns\n' "$cat" "$id/$bn" "$plugin_src/$cat/$bn" >> "$inv_file"
                fi
            done
        done
    done

    local removed=0 recreated=0 restored=0

    # Phase 1: orphan scan — root-position symlinks under runtime/<cat>/
    local cat
    for cat in skills agents commands templates; do
        [ -d "$runtime/$cat" ] || continue
        local link bn
        for link in "$runtime/$cat"/*; do
            [ -L "$link" ] || continue
            bn="$(basename "$link")"
            if ! grep -qE "^${cat}\|${bn}\|" "$inv_file"; then
                rm -f "$link"
                removed=$((removed+1))
            fi
        done
        # Phase 1b: namespaced subdirs
        local sub sub_id
        for sub in "$runtime/$cat"/*/; do
            [ -d "$sub" ] || continue
            sub_id="$(basename "$sub")"
            case "$active_ids_padded" in
                *" $sub_id "*) ;;
                *)
                    rm -rf "$sub"
                    removed=$((removed+1))
                    continue
                    ;;
            esac
            local nlink nbn
            for nlink in "$sub"*; do
                [ -L "$nlink" ] || [ -e "$nlink" ] || continue
                nbn="$(basename "$nlink")"
                if ! grep -qE "^${cat}\|${sub_id}/${nbn}\|" "$inv_file"; then
                    rm -f "$nlink"
                    removed=$((removed+1))
                fi
            done
            # Drop empty subdirs.
            rmdir "$sub" 2>/dev/null || true
        done
    done

    # Phase 2: broken-symlink recreate from inventory.
    local cat_f key src_f mode target
    while IFS='|' read -r cat_f key src_f mode; do
        [ -n "$cat_f" ] || continue
        target="$runtime/$cat_f/$key"
        if [ "$mode" = "ns" ]; then
            mkdir -p "$(dirname "$target")"
        fi
        if [ ! -L "$target" ] || [ ! -e "$target" ]; then
            ln -sfn "$src_f" "$target"
            recreated=$((recreated+1))
        fi
    done < "$inv_file"

    rm -f "$inv_file"

    # Phase 3: disabled-orphan restore.
    local f fname id_part orig
    for cat in skills agents commands templates; do
        [ -d "$runtime/$cat" ] || continue
        for f in "$runtime/$cat"/*.disabled; do
            [ -e "$f" ] || continue
            fname="$(basename "$f")"
            id_part="$(echo "$fname" | awk -F. '{ if (NF >= 3) print $(NF-1); else print "" }')"
            [ -n "$id_part" ] || continue
            case "$active_ids_padded" in
                *" $id_part "*) ;;
                *)
                    orig="${f%.${id_part}.disabled}"
                    if [ ! -e "$orig" ]; then
                        mv "$f" "$orig"
                        restored=$((restored+1))
                    fi
                    ;;
            esac
        done
    done

    echo "dr-plugin sync: removed=$removed recreated=$recreated restored=$restored" >&2
    return 0
}

# --- doctor subcommand (TUNE-0101 Phase D) ----------------------------------
#
# Diagnoses inconsistent state and (with --fix) attempts repair.
#
# Eight checks (per plan TUNE-0101 § Phase D) + Check 9 skill-registry:
#   1. manifest-syntax        (error,   no auto-fix)
#   2. inventory-consistency  (error,   --fix → cmd_sync)
#   3. broken-symlinks        (error,   --fix → cmd_sync)
#   4. orphan-files           (warning, --fix → cmd_sync)
#   5. override-integrity     (error,   --fix → cmd_sync)
#   6. dependency-graph       (error,   no auto-fix)
#   7. git-state              (warning, no auto-fix)
#   8. snapshot-cleanup >Nd   (warning, --fix → snapshot_purge_old)
#   9. skill-registry         (warning, no auto-fix; closes dr-archive symptom)
#
# Exit codes: 0=clean, 1=warnings only, 2=errors found, 3=fatal.

DR_PLUGIN_SNAPSHOT_AGE_DAYS="${DR_PLUGIN_SNAPSHOT_AGE_DAYS:-30}"

_doctor_emit() {
    # Args: <severity> <message>
    local sev="$1"; shift
    echo "  [${sev}] $*" >&2
}

# Internal: build the runtime/<cat>/<key>|src|mode inventory map (file form
# matches cmd_sync). Echoes lines on stdout via temp file path.
_doctor_build_inventory() {
    local manifest="$1" out="$2"
    local active_ids id cat files bn overrides_list plugin_src
    active_ids="$(manifest_active_ids "$manifest")"
    : > "$out"
    for id in $active_ids; do
        plugin_src="$(manifest_field "$manifest" "$id" source)"
        overrides_list="$(_manifest_overrides_of "$manifest" "$id" | tr '\n' ' ')"
        for cat in skills agents commands templates; do
            files="$(manifest_inventory_of "$manifest" "$id" "$cat")"
            for bn in $files; do
                if _is_override_basename "$bn" "$overrides_list"; then
                    printf '%s|%s|%s|root|%s\n' "$cat" "$bn" "$plugin_src/$cat/$bn" "$id" >> "$out"
                else
                    printf '%s|%s|%s|ns|%s\n' "$cat" "$id/$bn" "$plugin_src/$cat/$bn" "$id" >> "$out"
                fi
            done
        done
    done
}

_doctor_check_manifest_syntax() {
    # Returns issue count via stdout.
    local manifest="$1"
    local id issues=0
    if [ ! -f "$manifest" ]; then
        _doctor_emit error "manifest missing: $manifest"
        echo 1
        return 0
    fi
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        # Pipe stderr from validator into our [error] emit format.
        local err_buf
        err_buf="$(manifest_validate_entry "$manifest" "$id" 2>&1 1>/dev/null || true)"
        if [ -n "$err_buf" ]; then
            while IFS= read -r line; do
                _doctor_emit error "${line#  }"
                issues=$((issues + 1))
            done < <(printf '%s\n' "$err_buf")
        fi
    done < <(manifest_active_ids "$manifest")
    echo "$issues"
}

_doctor_check_inventory_consistency() {
    # Args: <inv_file> <runtime>
    # Each declared inventory entry must have a symlink at the right position.
    local inv_file="$1" runtime="$2"
    local issues=0 cat key src mode owner target
    while IFS='|' read -r cat key src mode owner; do
        [ -n "$cat" ] || continue
        target="$runtime/$cat/$key"
        if [ ! -L "$target" ]; then
            _doctor_emit error "missing symlink: $target (owner: $owner)"
            issues=$((issues + 1))
        fi
    done < "$inv_file"
    echo "$issues"
}

_doctor_check_broken_symlinks() {
    # Args: <inv_file> <runtime>
    # Declared symlinks that exist but point to a missing target.
    local inv_file="$1" runtime="$2"
    local issues=0 cat key src mode owner target
    while IFS='|' read -r cat key src mode owner; do
        [ -n "$cat" ] || continue
        target="$runtime/$cat/$key"
        if [ -L "$target" ] && [ ! -e "$target" ]; then
            _doctor_emit error "broken symlink: $target → $(readlink "$target")"
            issues=$((issues + 1))
        fi
    done < "$inv_file"
    echo "$issues"
}

_doctor_check_orphan_files() {
    # Args: <inv_file> <runtime> <active_ids_padded>
    local inv_file="$1" runtime="$2" active_ids_padded="$3"
    local issues=0 cat link bn sub sub_id nlink nbn
    for cat in skills agents commands templates; do
        [ -d "$runtime/$cat" ] || continue
        for link in "$runtime/$cat"/*; do
            [ -L "$link" ] || continue
            bn="$(basename "$link")"
            if ! grep -qE "^${cat}\|${bn}\|" "$inv_file"; then
                _doctor_emit warning "orphan symlink: $runtime/$cat/$bn"
                issues=$((issues + 1))
            fi
        done
        for sub in "$runtime/$cat"/*/; do
            [ -d "$sub" ] || continue
            sub_id="$(basename "$sub")"
            case "$active_ids_padded" in
                *" $sub_id "*)
                    for nlink in "$sub"*; do
                        [ -L "$nlink" ] || continue
                        nbn="$(basename "$nlink")"
                        if ! grep -qE "^${cat}\|${sub_id}/${nbn}\|" "$inv_file"; then
                            _doctor_emit warning "orphan symlink: $sub$nbn"
                            issues=$((issues + 1))
                        fi
                    done
                    ;;
                *)
                    _doctor_emit warning "orphan namespaced subdir: $sub (no plugin '$sub_id' in manifest)"
                    issues=$((issues + 1))
                    ;;
            esac
        done
    done
    echo "$issues"
}

_doctor_check_override_integrity() {
    # Args: <manifest>
    # For each plugin's overrides list:
    #  (a) basename must appear in plugin's file_inventory (some category).
    #  (b) the source plugin dir must contain the file (validated indirectly
    #      via inventory consistency upstream).
    local manifest="$1"
    local issues=0 id ovr cat invs found
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        while IFS= read -r ovr; do
            [ -n "$ovr" ] || continue
            found=0
            for cat in skills agents commands templates; do
                invs=" $(manifest_inventory_of "$manifest" "$id" "$cat" | tr '\n' ' ') "
                case "$invs" in
                    *" $ovr "*) found=1; break ;;
                esac
            done
            if [ "$found" -eq 0 ]; then
                _doctor_emit error "override '$ovr' declared by '$id' but not in any file_inventory"
                issues=$((issues + 1))
            fi
        done < <(_manifest_overrides_of "$manifest" "$id")
    done < <(manifest_active_ids "$manifest")
    echo "$issues"
}

_doctor_check_dependency_graph() {
    # Args: <manifest>
    local manifest="$1"
    local issues=0 line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            "dangling "*)
                _doctor_emit error "${line}"
                issues=$((issues + 1))
                ;;
            "cycle "*)
                _doctor_emit error "${line}"
                issues=$((issues + 1))
                ;;
        esac
    done < <(manifest_dep_graph_check "$manifest")
    echo "$issues"
}

_doctor_check_git_state() {
    # Args: <workspace> <manifest>
    local ws="$1" manifest="$2"
    [ -d "$ws/.git" ] || { echo 0; return 0; }
    command -v git >/dev/null 2>&1 || { echo 0; return 0; }
    # `git status --porcelain` exits 0 even if not a repo when given -C; use
    # rev-parse to gate cleanly.
    if ! git -C "$ws" rev-parse --git-dir >/dev/null 2>&1; then
        echo 0
        return 0
    fi
    local rel
    rel="${manifest#"$ws/"}"
    local status_out
    status_out="$(git -C "$ws" status --porcelain -- "$rel" 2>/dev/null)"
    if [ -n "$status_out" ]; then
        _doctor_emit warning "manifest has uncommitted changes: $rel"
        echo 1
        return 0
    fi
    echo 0
}

_doctor_check_snapshot_cleanup() {
    # Args: <workspace>
    local ws="$1"
    local snap_d
    snap_d="$(snapshot_dir "$ws")"
    [ -d "$snap_d" ] || { echo 0; return 0; }
    local old
    old="$(snapshot_list_old "$snap_d" "$DR_PLUGIN_SNAPSHOT_AGE_DAYS" | wc -l | tr -d ' ')"
    if [ "$old" -gt 0 ]; then
        _doctor_emit warning "snapshots older than ${DR_PLUGIN_SNAPSHOT_AGE_DAYS}d: $old in $snap_d"
        echo "$old"
        return 0
    fi
    echo 0
}

_doctor_check_skill_registry() {
    # Args: <runtime>
    # For each runtime/skills/*.md (root + namespaced), verify the linked
    # file has a YAML frontmatter `name:` field matching the basename
    # (without `.md`). Mismatch → Skill tool cannot resolve by name.
    # Closes the dr-archive symptom logged in Round 4: skills missing
    # frontmatter are invisible to the Skill tool even if discoverable as
    # slash commands.
    local runtime="$1"
    [ -d "$runtime/skills" ] || { echo 0; return 0; }
    local issues=0 link bn name expected target sub sub_id nlink
    for link in "$runtime/skills"/*; do
        [ -L "$link" ] || continue
        bn="$(basename "$link")"
        case "$bn" in *.md) ;; *) continue ;; esac
        target="$(readlink "$link")"
        case "$target" in /*) ;; *) target="$runtime/skills/$target" ;; esac
        [ -e "$target" ] || continue
        expected="${bn%.md}"
        name="$(skill_frontmatter_name "$target")"
        if [ -z "$name" ]; then
            _doctor_emit warning "skill missing frontmatter 'name:' — $link (Skill tool cannot resolve)"
            issues=$((issues + 1))
        elif [ "$name" != "$expected" ]; then
            _doctor_emit warning "skill frontmatter name mismatch: '$name' ≠ basename '$expected' ($link)"
            issues=$((issues + 1))
        fi
    done
    for sub in "$runtime/skills"/*/; do
        [ -d "$sub" ] || continue
        sub_id="$(basename "$sub")"
        for nlink in "$sub"*.md; do
            [ -L "$nlink" ] || continue
            bn="$(basename "$nlink")"
            target="$(readlink "$nlink")"
            case "$target" in /*) ;; *) target="$sub$target" ;; esac
            [ -e "$target" ] || continue
            expected="${bn%.md}"
            name="$(skill_frontmatter_name "$target")"
            if [ -z "$name" ]; then
                _doctor_emit warning "skill missing frontmatter 'name:' — $nlink"
                issues=$((issues + 1))
            elif [ "$name" != "$expected" ]; then
                _doctor_emit warning "skill frontmatter name mismatch: '$name' ≠ basename '$expected' ($nlink)"
                issues=$((issues + 1))
            fi
        done
    done
    echo "$issues"
}

cmd_doctor() {
    local fix=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --fix)        fix=1 ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                echo "dr-plugin doctor: unknown flag: $1" >&2
                return 64
                ;;
        esac
        shift
    done

    local ws repo manifest runtime
    ws="$(resolve_workspace)"
    repo="$(resolve_repo_root "$ws")"
    manifest="$ws/datarim/enabled-plugins.md"
    bootstrap_manifest_if_missing "$manifest" "$repo"
    runtime="$(resolve_runtime_root)"

    local active_ids active_ids_padded
    active_ids="$(manifest_active_ids "$manifest")"
    active_ids_padded=" $(echo $active_ids | tr '\n' ' ')"

    local inv_file
    inv_file="$(mktemp -t dr-plugin-doctor-inv.XXXXXX)"
    _doctor_build_inventory "$manifest" "$inv_file"

    local errors=0 warnings=0 c

    echo "[1/9] manifest-syntax" >&2
    c="$(_doctor_check_manifest_syntax "$manifest")"
    [ "$c" -gt 0 ] && errors=$((errors + c))

    echo "[2/9] inventory-consistency" >&2
    c="$(_doctor_check_inventory_consistency "$inv_file" "$runtime")"
    [ "$c" -gt 0 ] && errors=$((errors + c))

    echo "[3/9] broken-symlinks" >&2
    c="$(_doctor_check_broken_symlinks "$inv_file" "$runtime")"
    [ "$c" -gt 0 ] && errors=$((errors + c))

    echo "[4/9] orphan-files" >&2
    c="$(_doctor_check_orphan_files "$inv_file" "$runtime" "$active_ids_padded")"
    [ "$c" -gt 0 ] && warnings=$((warnings + c))

    echo "[5/9] override-integrity" >&2
    c="$(_doctor_check_override_integrity "$manifest")"
    [ "$c" -gt 0 ] && errors=$((errors + c))

    echo "[6/9] dependency-graph" >&2
    c="$(_doctor_check_dependency_graph "$manifest")"
    [ "$c" -gt 0 ] && errors=$((errors + c))

    echo "[7/9] git-state" >&2
    c="$(_doctor_check_git_state "$ws" "$manifest")"
    [ "$c" -gt 0 ] && warnings=$((warnings + c))

    echo "[8/9] snapshot-cleanup (>${DR_PLUGIN_SNAPSHOT_AGE_DAYS}d)" >&2
    local old_snaps
    old_snaps="$(_doctor_check_snapshot_cleanup "$ws")"
    [ "$old_snaps" -gt 0 ] && warnings=$((warnings + old_snaps))

    echo "[9/9] skill-registry" >&2
    c="$(_doctor_check_skill_registry "$runtime")"
    [ "$c" -gt 0 ] && warnings=$((warnings + c))

    rm -f "$inv_file"

    # Auto-fix path: errors 2,3,5 → cmd_sync; warning 4 → cmd_sync;
    # warning 8 → snapshot_purge_old.
    if [ "$fix" -eq 1 ]; then
        if [ "$errors" -gt 0 ] || [ "$warnings" -gt 0 ]; then
            echo "dr-plugin doctor: --fix → running sync + snapshot purge" >&2
            cmd_sync >&2 || true
            local snap_d purged
            snap_d="$(snapshot_dir "$ws")"
            purged="$(snapshot_purge_old "$snap_d" "$DR_PLUGIN_SNAPSHOT_AGE_DAYS" 2>/dev/null || echo 0)"
            echo "dr-plugin doctor: purged $purged stale snapshot(s)" >&2
        fi
    fi

    if [ "$errors" -gt 0 ]; then
        echo "dr-plugin doctor: $errors error(s), $warnings warning(s)" >&2
        return 2
    fi
    if [ "$warnings" -gt 0 ]; then
        echo "dr-plugin doctor: 0 errors, $warnings warning(s)" >&2
        return 1
    fi
    echo "dr-plugin doctor: clean (9/9 checks passed)" >&2
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
        sync)
            cmd_sync "$@"
            ;;
        doctor)
            cmd_doctor "$@"
            ;;
        *)
            echo "dr-plugin: unknown subcommand: $cmd" >&2
            usage >&2
            exit 64
            ;;
    esac
}

main "$@"

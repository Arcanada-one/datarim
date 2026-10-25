#!/usr/bin/env bash
# Resolve the persisted product-discovery selector without enabling the plugin.
set -euo pipefail

usage() {
    printf 'Usage: read-product-profile.sh --root <workspace-root> --task <task-id> --runtime <runtime-root>\n' >&2
    exit 64
}

ROOT='' TASK='' RUNTIME=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root|--task|--runtime)
            [ "$#" -ge 2 ] || usage
            case "$1" in
                --root) ROOT=$2 ;;
                --task) TASK=$2 ;;
                --runtime) RUNTIME=$2 ;;
            esac
            shift 2
            ;;
        *) usage ;;
    esac
done
if [ -z "$ROOT" ] || [ -z "$TASK" ] || [ -z "$RUNTIME" ]; then
    usage
fi
case "$ROOT:$RUNTIME" in /*:/*) ;; *) usage ;; esac
case "$TASK" in *[!A-Za-z0-9._-]*|'') usage ;; esac

DESCRIPTION="$ROOT/datarim/tasks/$TASK-task-description.md"
ENABLED="$ROOT/datarim/enabled-plugins.md"
SKILL="$RUNTIME/skills/product-discovery/product-framing/SKILL.md"
if [ ! -f "$DESCRIPTION" ] || [ -L "$DESCRIPTION" ]; then
    printf 'profile_not_selected\n'
    exit 0
fi

# Count profile selector lines only inside the dedicated body section. Preserve
# the complete value so malformed/unknown selectors cannot activate the pack.
selector_data=$(awk '
    /^## Profile[[:space:]]*$/ { in_profile=1; next }
    /^##?[[:space:]]/ { in_profile=0 }
    in_profile && /^profile:/ {
        value=$0
        sub(/^profile:/, "", value)
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        count++
        if (count == 1) first=value
    }
    END { printf "%d\t%s\n", count+0, first }
' "$DESCRIPTION")
IFS=$'\t' read -r selector_count selector_value <<<"$selector_data"
if [ "$selector_count" -eq 0 ]; then
    printf 'profile_not_selected\n'
    exit 0
fi
if [ "$selector_count" -gt 1 ]; then
    printf 'profile_ambiguous\n'
    exit 0
fi
if [ "$selector_value" != product-discovery ]; then
    printf 'profile_unknown\n'
    exit 0
fi

enabled=0
if [ -f "$ENABLED" ] && [ ! -L "$ENABLED" ]; then
    enabled=$(awk '
        /^## Active[[:space:]]*$/ { in_active=1; next }
        /^##?[[:space:]]/ { in_active=0 }
        in_active && /^- id: product-discovery[[:space:]]*$/ { found=1 }
        END { print found+0 }
    ' "$ENABLED")
fi
if [ "$enabled" -ne 1 ] || [ ! -r "$SKILL" ]; then
    printf 'profile_unavailable\n'
    exit 0
fi
printf 'profile_active\n'

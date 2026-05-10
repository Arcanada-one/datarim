#!/usr/bin/env bash
# network-exposure-gate.sh — tiered-gate decision for Datarim pipeline commands.
#
# Reads the YAML frontmatter of a task description file (priority + type) and
# emits one of: hard_block | advisory_warn | skip.  Implements the Option C
# tiered-gate algorithm (P0 absolute floor + type refinement + fail-closed on
# malformed).  Source-of-truth contract: skills/network-exposure-baseline.md
# § Tiered Gate Rules.
#
# Inputs:
#   --task-description PATH   YAML-frontmatter task file (required).
#   --network-diff            Set when caller already detected a touched
#                             networking surface (compose / redis / postgres /
#                             systemd .socket / firewall).  Promotes P2/P3
#                             from skip to advisory_warn.
#   --quiet                   Print decision only (no rationale).
#
# Output:
#   stdout: decision token (hard_block | advisory_warn | skip)
#   stderr: rationale on non-skip decisions; warnings on malformed frontmatter.
#
# Exit codes:
#   0 — decision rendered (any of the three tokens)
#   2 — usage error / file not readable
#
set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="network-exposure-gate.sh"

# Canonical sec/infra type set.  Sync with skill rule table.
SEC_INFRA_TYPES=(
    security-incident
    infrastructure
    framework-hardening
    security-baseline
    auth-mandate
)

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME --task-description PATH [--network-diff] [--quiet]
       $SCRIPT_NAME --version
       $SCRIPT_NAME -h | --help

Decisions:
  hard_block      — gate MUST block the pipeline step.
  advisory_warn   — gate emits a warning but does not block.
  skip            — gate is silent (no networking surface).
EOF
}

# extract_frontmatter_field <file> <key>
# Echoes the value of <key> from the first YAML frontmatter block.  Strips
# surrounding quotes/spaces.  Empty output => key missing.
extract_frontmatter_field() {
    local file="$1"
    local key="$2"
    awk -v key="$key" '
        BEGIN { in_fm = 0; seen = 0 }
        /^---[[:space:]]*$/ {
            if (in_fm) { exit }
            in_fm = 1
            next
        }
        in_fm && $0 ~ "^"key":[[:space:]]" {
            sub("^"key":[[:space:]]+", "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            gsub(/^["\047]|["\047]$/, "")
            print
            seen = 1
            exit
        }
    ' "$file"
}

decide() {
    local priority="$1"
    local task_type="$2"
    local network_diff="$3"

    case "$priority" in
        P0)
            echo hard_block
            return
            ;;
        P1)
            for t in "${SEC_INFRA_TYPES[@]}"; do
                if [[ "$task_type" == "$t" ]]; then
                    echo hard_block
                    return
                fi
            done
            echo advisory_warn
            return
            ;;
        P2|P3)
            if [[ "$network_diff" == "1" ]]; then
                echo advisory_warn
            else
                echo skip
            fi
            return
            ;;
        "")
            echo "WARN: missing priority frontmatter — fail-closed to hard_block" >&2
            echo hard_block
            return
            ;;
        *)
            echo "WARN: malformed priority '$priority' — fail-closed to hard_block" >&2
            echo hard_block
            return
            ;;
    esac
}

main() {
    local task_file=""
    local network_diff="0"
    local quiet="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task-description)
                shift
                [[ $# -gt 0 ]] || { echo "ERROR: --task-description requires PATH" >&2; exit 2; }
                task_file="$1"
                ;;
            --network-diff)
                network_diff="1"
                ;;
            --quiet)
                quiet="1"
                ;;
            --version)
                echo "$SCRIPT_NAME $VERSION"
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "ERROR: unknown flag '$1'" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done

    if [[ -z "$task_file" ]]; then
        echo "ERROR: --task-description PATH is required" >&2
        usage >&2
        exit 2
    fi

    if [[ ! -r "$task_file" ]]; then
        echo "ERROR: cannot read task description: $task_file" >&2
        exit 2
    fi

    local priority
    local task_type
    priority=$(extract_frontmatter_field "$task_file" priority)
    task_type=$(extract_frontmatter_field "$task_file" type)

    local decision
    decision=$(decide "$priority" "$task_type" "$network_diff")

    if [[ "$quiet" != "1" && "$decision" != "skip" ]]; then
        echo "gate: priority=${priority:-<missing>} type=${task_type:-<missing>} network_diff=${network_diff} -> ${decision}" >&2
    fi

    echo "$decision"
}

main "$@"

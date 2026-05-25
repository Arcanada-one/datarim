#!/usr/bin/env bash
# cli/subcommands/audit.sh — datarim audit (log|halt|resume|purge|stats).
# Source: TUNE-0271 plan § Implementation Steps Batch 2.

set -u

audit_subcommand() {
    local CLI_DIR LIB_DIR
    CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    LIB_DIR="$CLI_DIR/lib"
    # shellcheck source=cli/lib/kill-switch.sh
    . "$LIB_DIR/kill-switch.sh"
    # shellcheck source=cli/lib/audit.sh
    . "$LIB_DIR/audit.sh"

    local sub="${1:-log}"; shift || true
    case "$sub" in
        log)
            local day f
            day="${1:-$(date -u +%F)}"
            f="$(cli_audit_dir)/cli-audit-$day.jsonl"
            if [ -f "$f" ]; then cat "$f"; else
                printf '[audit] no audit file for %s\n' "$day" >&2
                return 1
            fi
            ;;
        halt)
            kill_switch_engage ;;
        resume)
            kill_switch_disengage ;;
        purge)
            audit_purge ;;
        stats)
            local f day count total
            day="$(date -u +%F)"
            f="$(cli_audit_dir)/cli-audit-$day.jsonl"
            count=0
            if [ -f "$f" ]; then count=$(wc -l < "$f" | tr -d ' '); fi
            total=$(find "$(cli_audit_dir)" -maxdepth 1 -name 'cli-audit-*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
            printf 'audit_dir: %s\ntoday_lines: %s\nfile_count: %s\n' "$(cli_audit_dir)" "$count" "$total"
            ;;
        *)
            printf '[audit] unknown subcommand: %s\nUsage: datarim audit log|halt|resume|purge|stats\n' "$sub" >&2
            return 2 ;;
    esac
}

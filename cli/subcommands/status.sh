#!/usr/bin/env bash
# status.sh — `datarim status` native file reader.
# Source: creative-TUNE-0268-architecture-status-format.md (Option C).
# Reads: <ws>/datarim/activeContext.md, <ws>/datarim/backlog.md,
#        <ws>/documentation/archive/**/archive-*.md
#
# Output (plain default):
#   === Active Tasks ===
#   <thin one-liners>
#   === Backlog ===
#   count=<n> pending=<p> deferred=<d>
#   === Recently completed ===
#   <top-5 archive IDs by mtime>
#   === Next step ===
#   <fixed CTA>
#
# --json: foundation envelope с data.{active, backlog, recent, next}.

set -u

_STATUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_STATUS_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=../lib/markdown-parser.sh
source "$LIB_DIR/markdown-parser.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"

OUTPUT_MODE="plain"
while (( $# > 0 )); do
    case "$1" in
        --json) OUTPUT_MODE=json; shift ;;
        --help|-h)
            cat <<'USAGE'
usage: datarim status [--json]

Emits 4-section snapshot of the workspace:
  Active Tasks       — datarim/activeContext.md § Active Tasks
  Backlog            — datarim/backlog.md (count by status)
  Recently completed — top-5 archive entries by mtime
  Next step          — recommended CTA

Plain text default; --json emits foundation envelope.
USAGE
            exit 0
            ;;
        *)
            output_emit_error 2 MISUSE "unknown arg '$1'"
            ;;
    esac
done
export OUTPUT_MODE
export DATARIM_CLI_CMD="status"

# Resolve workspace root (walk-up from cwd; env override wins).
WS="$(ws_resolve)"
ACTIVE_CTX="$WS/datarim/activeContext.md"
BACKLOG_MD="$WS/datarim/backlog.md"
ARCHIVE_DIR="$WS/documentation/archive"

[[ -f "$ACTIVE_CTX" ]] || output_emit_error 31 NOT_FOUND "activeContext.md not found at $ACTIVE_CTX"

# --- Section 1: Active Tasks (parse activeContext.md § Active Tasks) ---
# Extract lines between `## Active Tasks` heading и next `##` heading.
_extract_section() {
    local file="$1" heading="$2"
    awk -v h="$heading" '
        $0 ~ "^## "h"$" { capture=1; next }
        capture && /^## / { exit }
        capture { print }
    ' "$file"
}

active_section_md="$(mktemp -t status-active.XXXXXX)"
_extract_section "$ACTIVE_CTX" "Active Tasks" > "$active_section_md"

active_json="$(parse_thin_file "$active_section_md")" || {
    rm -f "$active_section_md"
    output_emit_error 30 STATE_MISMATCH "failed to parse Active Tasks section in $ACTIVE_CTX"
}
rm -f "$active_section_md"

# --- Section 2: Backlog counts ---
backlog_total=0
backlog_pending=0
backlog_deferred=0
backlog_blocked=0
if [[ -f "$BACKLOG_MD" ]]; then
    backlog_json="$(parse_thin_file "$BACKLOG_MD")"
    backlog_total="$(echo "$backlog_json" | jq 'length')"
    backlog_pending="$(echo "$backlog_json" | jq '[.[] | select(.status == "pending")] | length')"
    backlog_deferred="$(echo "$backlog_json" | jq '[.[] | select(.status == "deferred")] | length')"
    backlog_blocked="$(echo "$backlog_json" | jq '[.[] | select(.status == "blocked")] | length')"
fi

# --- Section 3: Recently completed (top-5 archive files by mtime) ---
# `ls -t` is portable (BSD + GNU); `find ... | xargs stat` would diverge on macOS vs Linux.
recent_json='[]'
if [[ -d "$ARCHIVE_DIR" ]]; then
    # shellcheck disable=SC2012  # ls -t is intentional here (mtime sort across subdirs).
    recent_paths="$(find "$ARCHIVE_DIR" -name 'archive-*.md' -type f -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -5)"
    if [[ -n "$recent_paths" ]]; then
        recent_json="$(echo "$recent_paths" | jq -R -s '
            split("\n")
            | map(select(. != ""))
            | map({path: ., id: (capture("archive-(?<id>[A-Z][A-Z0-9]+-[0-9]+[A-Z]?)") | .id // "?")})
        ')"
    fi
fi

# --- Section 4: Next step (fixed CTA based on active task count) ---
active_count="$(echo "$active_json" | jq 'length')"
if [[ "$active_count" -gt 0 ]]; then
    next_cmd="/dr-continue"
    next_msg="$active_count active task(s) — resume via /dr-continue or /dr-status"
else
    next_cmd="/dr-init"
    next_msg="no active tasks — start one via /dr-init"
fi

if [[ "$OUTPUT_MODE" == "json" ]]; then
    data="$(jq -n \
        --argjson active "$active_json" \
        --argjson recent "$recent_json" \
        --argjson total "$backlog_total" \
        --argjson pending "$backlog_pending" \
        --argjson deferred "$backlog_deferred" \
        --argjson blocked "$backlog_blocked" \
        --arg cmd "$next_cmd" \
        --arg msg "$next_msg" \
        '{
            active: $active,
            backlog: {count: $total, pending: $pending, deferred: $deferred, blocked: $blocked},
            recent: $recent,
            next: {command: $cmd, message: $msg}
        }')"
    output_emit_json "$data"
else
    output_emit_plain "=== Active Tasks ==="
    if [[ "$active_count" -eq 0 ]]; then
        output_emit_plain "(none)"
    else
        echo "$active_json" | jq -r '.[] | "  \(.id) · \(.status) · \(.priority) · \(.complexity) · \(.title)"'
    fi
    output_emit_plain ""
    output_emit_plain "=== Backlog ==="
    output_emit_plain "  total=$backlog_total  pending=$backlog_pending  deferred=$backlog_deferred  blocked=$backlog_blocked"
    output_emit_plain ""
    output_emit_plain "=== Recently completed ==="
    if [[ "$(echo "$recent_json" | jq 'length')" -eq 0 ]]; then
        output_emit_plain "(none)"
    else
        echo "$recent_json" | jq -r '.[] | "  \(.id)"'
    fi
    output_emit_plain ""
    output_emit_plain "=== Next step ==="
    output_emit_plain "  $next_cmd — $next_msg"
fi

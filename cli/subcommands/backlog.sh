#!/usr/bin/env bash
# backlog.sh — `datarim backlog {list|add}`.
# list  — Phase 1 read-only enumeration (parses thin-schema entries).
# add   — Phase 2 write op: ID-collision probe → flock-guarded append → audit JSONL.

set -u

_BACKLOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_BACKLOG_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=../lib/markdown-parser.sh
source "$LIB_DIR/markdown-parser.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"

OUTPUT_MODE="plain"
SUBCMD=""
PREFIX=""
ADD_ID=""
ADD_PRIORITY=""
ADD_COMPLEXITY=""
ADD_TITLE=""

usage() {
    cat <<'USAGE'
usage:
  datarim backlog list [--prefix PFX] [--json]
  datarim backlog add  --id <ID> --priority <P1..P4> --complexity <L1..L4> \
                       --title <TEXT> [--json]
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        list|add) SUBCMD="$1"; shift ;;
        --json)   OUTPUT_MODE=json; shift ;;
        --prefix) PREFIX="${2:-}"; shift 2 ;;
        --id)         ADD_ID="${2:-}"; shift 2 ;;
        --priority)   ADD_PRIORITY="${2:-}"; shift 2 ;;
        --complexity) ADD_COMPLEXITY="${2:-}"; shift 2 ;;
        --title)      ADD_TITLE="${2:-}"; shift 2 ;;
        --help|-h)    usage; exit 0 ;;
        *)
            export DATARIM_CLI_CMD="backlog"; export OUTPUT_MODE
            output_emit_error 2 MISUSE "unknown arg '$1'"
            ;;
    esac
done

if [[ -z "$SUBCMD" ]]; then
    export DATARIM_CLI_CMD="backlog"; export OUTPUT_MODE
    output_emit_error 2 MISUSE "subcommand required: list | add"
fi
export OUTPUT_MODE
export DATARIM_CLI_CMD="backlog $SUBCMD"

WS="$(ws_resolve)"
BACKLOG_MD="$WS/datarim/backlog.md"

if [[ "$SUBCMD" == "list" ]]; then
    [[ -f "$BACKLOG_MD" ]] || output_emit_error 31 NOT_FOUND "backlog.md not found at $BACKLOG_MD"

    items_json="$(parse_thin_file "$BACKLOG_MD")"
    if [[ -n "$PREFIX" ]]; then
        items_json="$(echo "$items_json" | jq --arg p "$PREFIX" '[.[] | select(.id | startswith($p))]')"
    fi

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        data="$(jq -n --argjson items "$items_json" --arg prefix "$PREFIX" \
            '{items: $items, prefix: $prefix, count: ($items | length)}')"
        output_emit_json "$data"
    else
        count="$(echo "$items_json" | jq 'length')"
        echo "$items_json" | jq -r '.[] | "  \(.id) · \(.status) · \(.priority) · \(.complexity) · \(.title)"'
        printf 'total: %s\n' "$count"
    fi
    exit 0
fi

# ---- add -----------------------------------------------------------------

# Defense-in-depth kill-switch (dispatcher checks too; this guards direct invocation).
# shellcheck source=../lib/kill-switch.sh
source "$LIB_DIR/kill-switch.sh"
check_kill_switch || exit $?

# Required args validation (bash 3.2 compatible: no ${var^^} expansion).
[[ -z "$ADD_ID" ]]         && output_emit_error 2 MISUSE "missing required flag --id"
[[ -z "$ADD_PRIORITY" ]]   && output_emit_error 2 MISUSE "missing required flag --priority"
[[ -z "$ADD_COMPLEXITY" ]] && output_emit_error 2 MISUSE "missing required flag --complexity"
[[ -z "$ADD_TITLE" ]]      && output_emit_error 2 MISUSE "missing required flag --title"

ws_validate_task_id "$ADD_ID" || output_emit_error 2 MISUSE "invalid --id (must match PREFIX-NNNN[A])"

case "$ADD_PRIORITY" in P1|P2|P3|P4) ;; *)
    output_emit_error 2 MISUSE "invalid --priority (P1..P4)"
    ;;
esac
case "$ADD_COMPLEXITY" in L1|L2|L3|L4) ;; *)
    output_emit_error 2 MISUSE "invalid --complexity (L1..L4)"
    ;;
esac

# shellcheck source=../lib/id-collision-probe.sh
source "$LIB_DIR/id-collision-probe.sh"
# shellcheck source=../lib/audit.sh
source "$LIB_DIR/audit.sh"

start_ns="$(date +%s%N 2>/dev/null || echo 0)"
args_hash="$(audit_args_hash "$ADD_ID" "$ADD_PRIORITY" "$ADD_COMPLEXITY" "$ADD_TITLE")"

collisions="$(probe_collisions "$ADD_ID" "$WS")"
probe_rc=$?

if (( probe_rc == 28 )); then
    end_ns="$(date +%s%N 2>/dev/null || echo 0)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    audit_append "backlog add" "$args_hash" reversible error "$duration_ms" 28 || true
    output_emit_error_with_data 28 ID_COLLISION_DETECTED \
        "ID collision: $ADD_ID" \
        "$(jq -n --argjson c "$collisions" '{collisions: $c}')"
elif (( probe_rc == 29 )); then
    output_emit_warn "id-collision-probe timed out after ${DATARIM_PROBE_TIMEOUT_SEC:-5}s; aborting add (fail-closed for write op)"
    end_ns="$(date +%s%N 2>/dev/null || echo 0)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    audit_append "backlog add" "$args_hash" reversible error "$duration_ms" 29 || true
    output_emit_error 29 COLLISION_TIMEOUT "probe timeout"
fi

# Compose entry line (Phase 1 thin schema).
entry="- ${ADD_ID} · pending · ${ADD_PRIORITY} · ${ADD_COMPLEXITY} · ${ADD_TITLE} → tasks/${ADD_ID}-task-description.md"

# Ensure backlog.md + parent exists; create with bare header if absent.
mkdir -p "$(dirname "$BACKLOG_MD")"
if [[ ! -f "$BACKLOG_MD" ]]; then
    printf '# Backlog\n' > "$BACKLOG_MD"
fi

# flock-guarded append (creative D-4). macOS lacks flock(1); fall back to a
# python3 fcntl shim matching lib/audit.sh atomic-append pattern.
lock_file="${BACKLOG_MD}.lock"
if command -v flock >/dev/null 2>&1; then
    flock --exclusive --timeout 5 "$lock_file" \
        -c "printf '%s\n' \"\$1\" >> \"\$2\"" -- "$entry" "$BACKLOG_MD" \
        || output_emit_error 30 STATE_MISMATCH "flock contention on $lock_file"
else
    python3 - "$BACKLOG_MD" "$entry" <<'PY'
import fcntl, os, sys
backlog, entry = sys.argv[1], sys.argv[2]
fd = os.open(backlog, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    os.write(fd, (entry + "\n").encode("utf-8"))
finally:
    fcntl.flock(fd, fcntl.LOCK_UN)
    os.close(fd)
PY
fi

end_ns="$(date +%s%N 2>/dev/null || echo 0)"
duration_ms=$(( (end_ns - start_ns) / 1000000 ))
audit_append "backlog add" "$args_hash" reversible success "$duration_ms" 0 || true

if [[ "$OUTPUT_MODE" == "json" ]]; then
    data="$(jq -n --arg id "$ADD_ID" --arg entry "$entry" \
        '{id: $id, entry: $entry, appended: true}')"
    output_emit_json "$data"
else
    printf 'added: %s\n' "$entry"
fi

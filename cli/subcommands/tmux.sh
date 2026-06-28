#!/usr/bin/env bash
# cli/subcommands/tmux.sh — tmux pane control via /hooks/tmux HTTP proxy (Phase 4).
# Source: TUNE-0268 Phase 4 plan § Implementation Steps.
#
# Subcommands:
#   datarim tmux ls [--json]
#   datarim tmux attach <pane> [--task <TASK-ID>] [--json]
#   datarim tmux new --task <TASK-ID> --cmd "<allowed-cmd>" [--json]
#   datarim tmux kill <pane> [--force] [--json]
#   datarim tmux read <pane> [--lines N] [--json]

set -u

CLI_DIR_TMUX_SUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR_TMUX_SUB="$CLI_DIR_TMUX_SUB/lib"

# shellcheck source=cli/lib/kill-switch.sh
. "$LIB_DIR_TMUX_SUB/kill-switch.sh"
# shellcheck source=cli/lib/output.sh
. "$LIB_DIR_TMUX_SUB/output.sh"
# shellcheck source=cli/lib/audit.sh
. "$LIB_DIR_TMUX_SUB/audit.sh"
# shellcheck source=cli/lib/notify.sh
. "$LIB_DIR_TMUX_SUB/notify.sh"
# shellcheck source=cli/lib/exit-codes.sh
. "$LIB_DIR_TMUX_SUB/exit-codes.sh"
# shellcheck source=cli/lib/tmux-proxy.sh
. "$LIB_DIR_TMUX_SUB/tmux-proxy.sh"

# Determine output mode from args (--json sets OUTPUT_MODE=json).
_tmux_detect_json_mode() {
    local arg
    for arg in "$@"; do
        if [ "$arg" = "--json" ]; then
            export OUTPUT_MODE=json
            return 0
        fi
    done
}

# Extract `.data` field from a JSON body (defaulting to null when missing).
# Used to wrap dispatcher's `{"data": {...}}` response with our envelope.
_tmux_extract_data() {
    local body="$1"
    printf '%s' "$body" | python3 -c 'import json,sys; b=json.load(sys.stdin); print(json.dumps(b.get("data")))' 2>/dev/null || printf 'null'
}

# Emit response in current OUTPUT_MODE — plain via printer fn / json via envelope.
# Args: <body> <plain_printer_fn_name>
_tmux_emit_response() {
    local body="$1" plain_fn="$2"
    if [ "${OUTPUT_MODE:-plain}" = "json" ]; then
        local data
        data="$(_tmux_extract_data "$body")"
        output_emit_json "$data"
    else
        "$plain_fn" "$body"
    fi
}

# Notifier gate — required for irreversible ops (new, kill).
# Returns 0 on ACK, 18 NOTIFIER_DOWN on fail-soft, 19 TMUX_NOTIFIER_OFF when
# DATARIM_CLI_NOTIFIER_TARGETS is unset/empty.
_tmux_notifier_gate() {
    local op="$1" pane_or_cmd="$2"
    if [ -z "${DATARIM_CLI_NOTIFIER_TARGETS:-}" ]; then
        printf '[tmux] notifier not configured (DATARIM_CLI_NOTIFIER_TARGETS unset) — refusing irreversible op %s\n' "$op" >&2
        return "$(exit_code_of TMUX_NOTIFIER_OFF)"
    fi
    if ! notify_irreversible "warning" "datarim tmux $op" "target=$pane_or_cmd"; then
        return "$(exit_code_of NOTIFIER_DOWN)"
    fi
    return 0
}

# Audit append helper — auto-derives args_hash from action label + payload.
_tmux_audit() {
    local action="$1" reversibility="$2" outcome="$3" duration_ms="$4" exit_code="$5"; shift 5
    local hash
    hash="$(audit_args_hash "$action" "$@")"
    audit_append "tmux $action" "$hash" "$reversibility" "$outcome" "$duration_ms" "$exit_code" || true
}

# Plain-text printer for pane list. Input: JSON envelope with .data.panes[].
_tmux_print_pane_list() {
    local body="$1"
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    body = json.load(sys.stdin)
except Exception:
    print("(unparseable response)", file=sys.stderr); sys.exit(1)
panes = (body.get("data") or {}).get("panes") or []
if not panes:
    print("(no panes)"); sys.exit(0)
for p in panes:
    print("\t".join([
        str(p.get("id","")), str(p.get("session","")),
        str(p.get("cmd","")), str(p.get("pid","")),
    ]))
'
}

# Plain-text printer for read response: .data.lines[] + optional .data.truncated.
_tmux_print_read() {
    local body="$1"
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    body = json.load(sys.stdin)
except Exception:
    print("(unparseable response)", file=sys.stderr); sys.exit(1)
data = body.get("data") or {}
for line in data.get("lines") or []:
    print(line)
if data.get("truncated"):
    print("[truncated]", file=sys.stderr)
'
}

# Plain-text printer for new: prints pane + session + cmd from .data.
_tmux_print_new() {
    local body="$1"
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    body = json.load(sys.stdin)
except Exception:
    print("(unparseable response)", file=sys.stderr); sys.exit(1)
data = body.get("data") or {}
print("pane=" + str(data.get("pane","?")) + " session=" + str(data.get("session","?")) + " cmd=" + str(data.get("cmd","?")))
'
}

# Plain-text printer for kill: prints "killed <pane>" from .data.pane.
_tmux_print_kill() {
    local body="$1"
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    body = json.load(sys.stdin)
except Exception:
    print("(unparseable response)", file=sys.stderr); sys.exit(1)
data = body.get("data") or {}
print("killed " + str(data.get("pane","?")))
'
}

# Plain-text printer for attach: prints russian instructions + raw tmux_cmd.
_tmux_print_attach() {
    local body="$1"
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    body = json.load(sys.stdin)
except Exception:
    print("(unparseable response)", file=sys.stderr); sys.exit(1)
data = body.get("data") or {}
pane = data.get("pane","?"); session = data.get("session","?")
cmd  = data.get("tmux_cmd") or ""
print("Pane " + str(pane) + " в сессии " + str(session) + ".")
if cmd:
    print("Запусти локально:"); print(cmd)
'
}

# --- ls --------------------------------------------------------------------

_tmux_op_ls() {
    local start_ms end_ms duration_ms body exit_code
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    if body=$(tmux_proxy_sync "list" "{}"); then
        exit_code=0
        _tmux_emit_response "$body" _tmux_print_pane_list
    else
        exit_code=$?
    fi
    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local outcome
    if [ "$exit_code" -eq 0 ]; then outcome="success"; else outcome="error"; fi
    _tmux_audit "ls" "reversible" "$outcome" "$duration_ms" "$exit_code"
    return "$exit_code"
}

# --- attach <pane> [--task <TASK-ID>] --------------------------------------

_tmux_op_attach() {
    local pane="" task_id="" arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --task) task_id="${2:-}"; shift 2 ;;
            --json) shift ;;
            -*)     output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux attach: unknown flag $arg" ;;
            *)      [ -z "$pane" ] && pane="$arg" || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux attach: extra positional $arg"
                    shift ;;
        esac
    done
    [ -n "$pane" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux attach: pane id required"
    tmux_validate_pane "$pane" || output_emit_error "$(exit_code_of NOT_FOUND)" NOT_FOUND "tmux attach: invalid pane id '$pane' (expected ^%[0-9]+\$)"

    local params start_ms end_ms duration_ms body exit_code
    params=$(python3 -c "import json,sys; print(json.dumps({'pane':sys.argv[1],'task_id':sys.argv[2]}))" "$pane" "$task_id")
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    if body=$(tmux_proxy_sync "attach" "$params"); then
        exit_code=0
        _tmux_emit_response "$body" _tmux_print_attach
    else
        exit_code=$?
    fi
    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local outcome
    if [ "$exit_code" -eq 0 ]; then outcome="success"; else outcome="error"; fi
    _tmux_audit "attach" "reversible" "$outcome" "$duration_ms" "$exit_code" "$pane" "$task_id"
    return "$exit_code"
}

# --- new --task <TASK-ID> --cmd "<allowed>" -------------------------------

_tmux_op_new() {
    local task_id="" cmd="" arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --task) task_id="${2:-}"; shift 2 ;;
            --cmd)  cmd="${2:-}"; shift 2 ;;
            --json) shift ;;
            *) output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux new: unknown arg $arg" ;;
        esac
    done
    [ -n "$task_id" ] || output_emit_error "$(exit_code_of INVALID_COMMAND)" INVALID_COMMAND "tmux new: --task required"
    [ -n "$cmd" ] || output_emit_error "$(exit_code_of INVALID_COMMAND)" INVALID_COMMAND "tmux new: --cmd required"
    if ! tmux_validate_cmd "$cmd"; then
        output_emit_error "$(exit_code_of INVALID_COMMAND)" INVALID_COMMAND "tmux new: --cmd '$cmd' not in whitelist (see lib/tmux-command-whitelist.txt)"
    fi

    local gate_exit
    _tmux_notifier_gate "new" "task=$task_id cmd=$cmd"; gate_exit=$?
    if [ $gate_exit -ne 0 ]; then
        _tmux_audit "new" "irreversible" "abort" "0" "$gate_exit" "$task_id" "$cmd"
        case "$gate_exit" in
            "$(exit_code_of TMUX_NOTIFIER_OFF)") output_emit_error "$gate_exit" TMUX_NOTIFIER_OFF "notifier not configured; refusing tmux new" ;;
            "$(exit_code_of NOTIFIER_DOWN)") output_emit_error "$gate_exit" NOTIFIER_DOWN "notifier delivery failed; refusing tmux new" ;;
            *) exit "$gate_exit" ;;
        esac
    fi

    local params start_ms end_ms duration_ms body exit_code
    params=$(python3 -c "import json,sys; print(json.dumps({'task_id':sys.argv[1],'cmd':sys.argv[2]}))" "$task_id" "$cmd")
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    if body=$(tmux_proxy_async "new" "$params"); then
        exit_code=0
        _tmux_emit_response "$body" _tmux_print_new
    else
        exit_code=$?
    fi
    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local outcome
    if [ "$exit_code" -eq 0 ]; then outcome="success"; else outcome="error"; fi
    _tmux_audit "new" "irreversible" "$outcome" "$duration_ms" "$exit_code" "$task_id" "$cmd"
    return "$exit_code"
}

# --- kill <pane> [--force] ------------------------------------------------

_tmux_op_kill() {
    local pane="" force=0 arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --force) force=1; shift ;;
            --json)  shift ;;
            -*)      output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux kill: unknown flag $arg" ;;
            *)       [ -z "$pane" ] && pane="$arg" || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux kill: extra positional $arg"
                     shift ;;
        esac
    done
    [ -n "$pane" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux kill: pane id required"
    tmux_validate_pane "$pane" || output_emit_error "$(exit_code_of NOT_FOUND)" NOT_FOUND "tmux kill: invalid pane id '$pane'"

    # Notifier gate ALWAYS applied — --force does NOT bypass notifier requirement.
    local gate_exit
    _tmux_notifier_gate "kill" "pane=$pane force=$force"; gate_exit=$?
    if [ $gate_exit -ne 0 ]; then
        _tmux_audit "kill" "irreversible" "abort" "0" "$gate_exit" "$pane" "$force"
        case "$gate_exit" in
            "$(exit_code_of TMUX_NOTIFIER_OFF)") output_emit_error "$gate_exit" TMUX_NOTIFIER_OFF "notifier not configured; refusing tmux kill" ;;
            "$(exit_code_of NOTIFIER_DOWN)") output_emit_error "$gate_exit" NOTIFIER_DOWN "notifier delivery failed; refusing tmux kill" ;;
            *) exit "$gate_exit" ;;
        esac
    fi

    local params start_ms end_ms duration_ms body exit_code
    params=$(python3 -c "import json,sys; print(json.dumps({'pane':sys.argv[1],'force':bool(int(sys.argv[2]))}))" "$pane" "$force")
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    if body=$(tmux_proxy_sync "kill" "$params"); then
        exit_code=0
        _tmux_emit_response "$body" _tmux_print_kill
    else
        exit_code=$?
    fi
    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local outcome
    if [ "$exit_code" -eq 0 ]; then outcome="success"; else outcome="error"; fi
    _tmux_audit "kill" "irreversible" "$outcome" "$duration_ms" "$exit_code" "$pane" "$force"
    return "$exit_code"
}

# --- read <pane> [--lines N] ----------------------------------------------

_tmux_op_read() {
    local pane="" lines=50 arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --lines) lines="${2:-}"; shift 2 ;;
            --json)  shift ;;
            -*)      output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux read: unknown flag $arg" ;;
            *)       [ -z "$pane" ] && pane="$arg" || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux read: extra positional $arg"
                     shift ;;
        esac
    done
    [ -n "$pane" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "tmux read: pane id required"
    tmux_validate_pane "$pane" || output_emit_error "$(exit_code_of NOT_FOUND)" NOT_FOUND "tmux read: invalid pane id '$pane'"
    tmux_validate_lines "$lines" || output_emit_error "$(exit_code_of INVALID_COMMAND)" INVALID_COMMAND "tmux read: --lines must be integer in [1,1000], got '$lines'"

    local params start_ms end_ms duration_ms body exit_code
    params=$(python3 -c "import json,sys; print(json.dumps({'pane':sys.argv[1],'lines':int(sys.argv[2])}))" "$pane" "$lines")
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    if body=$(tmux_proxy_sync "read" "$params"); then
        exit_code=0
        _tmux_emit_response "$body" _tmux_print_read
    else
        exit_code=$?
    fi
    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local outcome
    if [ "$exit_code" -eq 0 ]; then outcome="success"; else outcome="error"; fi
    _tmux_audit "read" "reversible" "$outcome" "$duration_ms" "$exit_code" "$pane" "$lines"
    return "$exit_code"
}

# --- dispatcher -----------------------------------------------------------

tmux_subcommand() {
    export DATARIM_CLI_CMD="tmux"
    _tmux_detect_json_mode "$@"
    # Kill-switch FIRST (V-AC-27) — applies to every tmux subcommand.
    check_kill_switch || exit $?

    local op="${1:-}"; shift || true
    case "$op" in
        ls)     _tmux_op_ls "$@" ;;
        attach) _tmux_op_attach "$@" ;;
        new)    _tmux_op_new "$@" ;;
        kill)   _tmux_op_kill "$@" ;;
        read)   _tmux_op_read "$@" ;;
        ""|help|--help|-h)
            cat <<'EOF'
Usage: datarim tmux <op> [args]

Operations:
  ls [--json]
  attach <pane> [--task <TASK-ID>] [--json]
  new --task <TASK-ID> --cmd "<allowed-cmd>" [--json]
  kill <pane> [--force] [--json]
  read <pane> [--lines N] [--json]

See documentation/reference/cli.md § tmux for the full surface.
EOF
            ;;
        *)
            output_emit_error "$(exit_code_of MISUSE)" MISUSE "unknown tmux op: $op"
            ;;
    esac
}

# Allow direct script execution as well as source-and-call.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    tmux_subcommand "$@"
fi

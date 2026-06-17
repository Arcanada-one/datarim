#!/usr/bin/env bash
# content_consilium_fanout.sh — Fan a content brief out to N vendor CLIs in parallel.
#
# Usage:
#   content_consilium_fanout.sh --brief <path> --run-dir <dir> --config <yaml>
#                               [--stage write|edit|publish]
#
# In DR_FANOUT_TEST_MODE=1 the script runs vendor commands as direct subprocesses
# (no tmux sessions) so the test suite can run without a terminal.
#
# Exit codes:
#   0 — at least 2 vendors completed successfully (full or 2-of-3 degraded)
#   1 — fewer than 2 vendors completed (catastrophic degradation)
#   2 — usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
BRIEF=""
RUN_DIR=""
CONFIG=""
STAGE="write"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --brief)    BRIEF="$2";   shift 2 ;;
    --run-dir)  RUN_DIR="$2"; shift 2 ;;
    --config)   CONFIG="$2";  shift 2 ;;
    --stage)    export STAGE="$2";   shift 2 ;;
    *) echo "ERR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$BRIEF"   ]] || { echo "ERR: --brief required"   >&2; exit 2; }
[[ -n "$RUN_DIR" ]] || { echo "ERR: --run-dir required" >&2; exit 2; }
[[ -n "$CONFIG"  ]] || { echo "ERR: --config required"  >&2; exit 2; }
[[ -f "$BRIEF"   ]] || { echo "ERR: brief not found: $BRIEF" >&2; exit 2; }
[[ -f "$CONFIG"  ]] || { echo "ERR: config not found: $CONFIG" >&2; exit 2; }

mkdir -p "$RUN_DIR"

# ---------------------------------------------------------------------------
# YAML mini-parser: emits TSV lines SLOT<TAB>CMD<TAB>ARGS_SPACE_SEP
# Handles the simple indented YAML produced by the template.
# No yq/python required — pure awk.
# ---------------------------------------------------------------------------
parse_vendors() {
  local cfg="$1"
  awk '
    /^[[:space:]]*-[[:space:]]+slot:/ {
      if (slot != "") print slot "\t" cmd "\t" args
      slot = $NF; gsub(/["'"'"']/, "", slot)
      cmd = ""; args = ""; in_args_list = 0
    }
    /^[[:space:]]+cmd:/ {
      cmd = $NF; gsub(/["'"'"']/, "", cmd)
      in_args_list = 0
    }
    /^[[:space:]]+args:/ {
      in_args_list = 1
      # Inline args: args: ["val1", "val2"]
      line = $0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      gsub(/[\[\]"'"'"']/, "", line)
      # Remove commas, collapse spaces
      gsub(/,/, " ", line)
      gsub(/[[:space:]]+/, " ", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line != "null") { args = line; in_args_list = 0 }
      next
    }
    /^[[:space:]]+-[[:space:]]+/ && in_args_list && cmd != "" {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", item)
      gsub(/["'"'"'\[\]]/, "", item)
      if (args == "") args = item; else args = args " " item
    }
    END { if (slot != "") print slot "\t" cmd "\t" args }
  ' "$cfg"
}

# Read hang timeouts from config
HANG_IDLE="$(awk '/hang_idle_secs:/{print $NF}' "$CONFIG")"
HANG_DEADLINE="$(awk '/hang_deadline_secs:/{print $NF}' "$CONFIG")"
HANG_IDLE="${HANG_IDLE:-120}"
HANG_DEADLINE="${HANG_DEADLINE:-300}"

# ---------------------------------------------------------------------------
# JSON log helper
# ---------------------------------------------------------------------------
json_log_entry() {
  local slot="$1" status="$2" elapsed="$3" reason="${4:-}"
  if [[ -n "$reason" ]]; then
    printf '{"vendor_slot":"%s","status":"%s","elapsed_s":%s,"reason":"%s"}\n' \
      "$slot" "$status" "$elapsed" "$reason"
  else
    printf '{"vendor_slot":"%s","status":"%s","elapsed_s":%s}\n' \
      "$slot" "$status" "$elapsed"
  fi
}

# ---------------------------------------------------------------------------
# Run one vendor command, write output to draft-SLOT.md
# Returns 0 on success, 99 on hang, other non-zero on error.
# ---------------------------------------------------------------------------
run_vendor_direct() {
  local slot="$1" cmd="$2" args_str="$3" out="$4"
  if [[ -z "$args_str" ]]; then
    "$cmd" < /dev/null > "$out" 2>&1
  else
    # shellcheck disable=SC2086
    $cmd $args_str < /dev/null > "$out" 2>&1
  fi
}

run_vendor_tmux() {
  local slot="$1" cmd="$2" args_str="$3" out="$4"
  # shellcheck source=../scripts/tmux_manager.sh
  source "$SCRIPT_DIR/tmux_manager.sh"
  local session="consilium-${slot}-$$"
  session_spawn_interactive "$session" "$cmd" "" || return 1
  pane_send "$session" "$(cat "$BRIEF")" || { session_close "$session"; return 1; }

  local result=0
  pane_idle_check "$session" "$HANG_IDLE" "$HANG_DEADLINE" || result=$?
  if [[ "$result" -eq 2 ]]; then
    session_close "$session"
    return 99
  fi
  pane_capture_tail "$session" 100 > "$out" 2>&1
  session_close "$session"
  return 0
}

# ---------------------------------------------------------------------------
# Main fan-out loop
# ---------------------------------------------------------------------------
RUN_LOG="$RUN_DIR/run-log.jsonl"
: > "$RUN_LOG"

success_count=0
degraded=0
vendor_count=0

# Determine timeout binary for test-mode hang detection (macOS portable)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  TIMEOUT_BIN=""
fi

while IFS=$'\t' read -r slot cmd args_str; do
  [[ -z "$slot" ]] && continue
  (( vendor_count++ )) || true
  local_out="$RUN_DIR/draft-${slot}.md"
  start_ts="$(date +%s)"
  hung=0
  vendor_rc=0

  if [[ "${DR_FANOUT_TEST_MODE:-0}" == "1" ]]; then
    # Test mode: run directly, optionally under timeout for hang detection
    if [[ -n "$TIMEOUT_BIN" && "$HANG_DEADLINE" -gt 0 ]]; then
      "$TIMEOUT_BIN" "$HANG_DEADLINE" bash -c "
        set -uo pipefail
        out='$local_out'
        cmd='$cmd'
        args_str='$args_str'
        if [[ -z \"\$args_str\" ]]; then
          \"\$cmd\" < /dev/null > \"\$out\" 2>&1
        else
          \$cmd \$args_str < /dev/null > \"\$out\" 2>&1
        fi
      " 2>/dev/null
      vendor_rc=$?
      if [[ "$vendor_rc" -eq 124 ]]; then
        hung=1
      fi
    else
      run_vendor_direct "$slot" "$cmd" "$args_str" "$local_out"
      vendor_rc=$?
    fi
  else
    run_vendor_tmux "$slot" "$cmd" "$args_str" "$local_out"
    vendor_rc=$?
    [[ "$vendor_rc" -eq 99 ]] && hung=1
  fi

  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  if [[ "$hung" -eq 1 ]]; then
    json_log_entry "$slot" "hung" "$elapsed" "hang timeout exceeded" >> "$RUN_LOG"
    rm -f "$local_out"
    (( degraded++ )) || true
  elif [[ "$vendor_rc" -ne 0 ]]; then
    json_log_entry "$slot" "error" "$elapsed" "exit $vendor_rc" >> "$RUN_LOG"
    rm -f "$local_out"
    (( degraded++ )) || true
  else
    json_log_entry "$slot" "ok" "$elapsed" >> "$RUN_LOG"
    (( success_count++ )) || true
  fi
done < <(parse_vendors "$CONFIG")

# Write degradation note if any vendor failed
if [[ "$degraded" -gt 0 ]]; then
  {
    printf 'Consilium degradation: %d of %d vendors unavailable.\n' "$degraded" "$vendor_count"
    printf 'Reason: see run-log.jsonl for per-vendor status.\n'
    printf 'Judge will operate on %d draft(s).\n' "$success_count"
  } > "$RUN_DIR/degradation_note.txt"
fi

if [[ "$success_count" -lt 2 ]]; then
  echo "ERR: fewer than 2 vendors succeeded ($success_count of $vendor_count); catastrophic degradation" >&2
  exit 1
fi

exit 0

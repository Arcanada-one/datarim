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
#
# Emits one JSONL entry per vendor run. Fields:
#   vendor_slot  — uppercase slot label (A/B/C)
#   vendor       — CLI binary name (proves vendor-distinctness per plan §4.2)
#   cli          — same as vendor: the CLI command string (slot ≠ CLI; proves no aliasing)
#   session      — tmux session name in interactive mode; "direct" in test mode
#   status       — ok | error | hung
#   elapsed_s    — wall-clock seconds
#   reason       — optional failure reason
# ---------------------------------------------------------------------------
json_log_entry() {
  local slot="$1" status="$2" elapsed="$3"
  local vendor="${4:-unknown}" cli="${5:-unknown}" session="${6:-unknown}" reason="${7:-}"
  if [[ -n "$reason" ]]; then
    printf '{"vendor_slot":"%s","vendor":"%s","cli":"%s","session":"%s","status":"%s","elapsed_s":%s,"reason":"%s"}\n' \
      "$slot" "$vendor" "$cli" "$session" "$status" "$elapsed" "$reason"
  else
    printf '{"vendor_slot":"%s","vendor":"%s","cli":"%s","session":"%s","status":"%s","elapsed_s":%s}\n' \
      "$slot" "$vendor" "$cli" "$session" "$status" "$elapsed"
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
  LAST_SESSION_NAME="$session"   # exported for run-log provenance
  session_spawn_interactive "$session" "$cmd" "" || return 1

  # File-reference delivery (not a big inline paste). Pasting a large brief into
  # an interactive vendor TUI is unreliable: some vendors fold a large paste into
  # a collapsed "[Pasted Content N chars]" multi-line buffer that Enter will not
  # submit. Instead, the brief lives in a file the vendor pane can read ($BRIEF
  # is an absolute path), and we paste a SHORT instruction that tells the vendor
  # to read that file and do the task. A short single-line prompt submits cleanly
  # across vendors. The instruction is generated in the brief's own language by
  # the caller via FANOUT_FILEREF_PROMPT; default is English.
  # File-out harvesting: the vendor WRITES its draft to a file, and we read that
  # file — rather than scraping the pane. An interactive TUI redraws an ANSI
  # interface (splash, boxes, footers) and scrolls the answer out of the captured
  # viewport, so capture-pane is unreliable for harvesting a long structured
  # answer; it is only used here for liveness/idle detection. The instruction
  # tells the vendor to read the brief file and write the result to OUTFILE.
  local outfile="$RUN_DIR/draft-${slot}.out"
  rm -f "$outfile"
  local instr="${FANOUT_FILEREF_PROMPT:-Read the file at the first path below and carry out the task described in it in full.}"
  instr+=" Write the finished result (and nothing else — no preamble, no commentary) to this exact file path: ${outfile}"
  local fileref="${instr}"$'\n'"brief: $BRIEF"$'\n'"output: $outfile"
  local refpath
  refpath="$(mktemp)"
  printf '%s' "$fileref" > "$refpath"
  pane_send_content "$session" "$refpath" || { rm -f "$refpath"; session_close "$session"; return 1; }
  rm -f "$refpath"

  # Settle gate: an interactive vendor TUI needs a moment to ingest the pasted
  # brief and start thinking before idle-detection is meaningful. Without it,
  # idle-detection can fire on the pre-answer prompt.
  sleep "${FANOUT_SETTLE_SECS:-8}"

  # First-output gate. With file-reference delivery the vendor reads the brief
  # file silently for a while before emitting anything; that silent gap can be
  # longer than idle_secs and would trip a FALSE idle (capturing only the echoed
  # prompt). So before the idle loop, wait until the pane content has GROWN
  # beyond the post-settle baseline (real generation started) — or a bounded
  # first-output deadline elapses (the vendor may legitimately answer tersely).
  local baseline_lines fo_waited=0
  baseline_lines="$(pane_capture_tail "$session" "${FANOUT_CAPTURE_LINES:-600}" 2>/dev/null | wc -l | tr -d ' ')"
  while [[ "$fo_waited" -lt "${FANOUT_FIRST_OUTPUT_DEADLINE:-180}" ]]; do
    sleep "${FANOUT_POLL_SECS:-5}"
    fo_waited=$((fo_waited + ${FANOUT_POLL_SECS:-5}))
    local cur_lines
    cur_lines="$(pane_capture_tail "$session" "${FANOUT_CAPTURE_LINES:-600}" 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$cur_lines" -gt "$baseline_lines" ]] && break   # generation has begun
  done

  # Wait-for-stabilisation loop. pane_idle_check returns:
  #   0 — output unchanged for idle_secs (the agent finished) → capture
  #   1 — output still changing within the window (agent is writing) → keep waiting
  #   2 — never went idle and never produced fresh output before deadline → hung
  # A long content generation legitimately keeps changing for minutes, so a
  # single idle_check (which returns 1 the instant output changes) must not be
  # treated as "done" — loop until the agent actually goes quiet or the overall
  # deadline elapses.
  local poll="${FANOUT_POLL_SECS:-5}"
  local waited=0 result=0
  while [[ "$waited" -lt "$HANG_DEADLINE" ]]; do
    result=0
    pane_idle_check "$session" "$HANG_IDLE" "$HANG_DEADLINE" || result=$?
    if [[ "$result" -eq 0 ]]; then
      break                       # stabilised → agent done
    elif [[ "$result" -eq 2 ]]; then
      session_close "$session"
      return 99                   # hung past deadline with no output
    fi
    # result == 1: still actively writing — wait a slice and re-check.
    sleep "$poll"
    waited=$((waited + poll + 1))
  done

  # Harvest from the file the vendor was told to write, not from the pane. Give
  # the write a brief grace window (the agent may finish thinking and flush the
  # file a moment after the pane goes idle). If the file never appears, fall back
  # to a chrome-stripped pane capture so the run still yields *something* the
  # judge can see (and the run-log will show the weaker provenance).
  local harvest_waited=0
  while [[ "$harvest_waited" -lt "${FANOUT_HARVEST_GRACE:-30}" ]]; do
    [[ -s "$outfile" ]] && break
    sleep 3
    harvest_waited=$((harvest_waited + 3))
  done
  if [[ -s "$outfile" ]]; then
    cp "$outfile" "$out"
  else
    # Fallback: pane scrape with chrome stripped (best-effort; unreliable).
    pane_capture_tail "$session" "${FANOUT_CAPTURE_LINES:-600}" 2>&1 \
      | grep -vE '^[[:space:]]*[─╭╰│╮╯>❯]' \
      | grep -vE 'gpt-[0-9]|Claude Code v|Tip:|/model to change|ctx [0-9]|accept edits|Esc to|Enter to|Press enter|[Pp]asted Content|/fast|to interrupt' \
      > "$out" 2>/dev/null || true
  fi
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

LAST_SESSION_NAME=""   # set by run_vendor_tmux per invocation

while IFS=$'\t' read -r slot cmd args_str; do
  [[ -z "$slot" ]] && continue
  (( vendor_count++ )) || true
  local_out="$RUN_DIR/draft-${slot}.md"
  start_ts="$(date +%s)"
  hung=0
  vendor_rc=0
  # Derive vendor name from CLI binary basename (no path, no args)
  vendor_name="$(basename "$cmd")"
  LAST_SESSION_NAME="direct"   # default; overridden by run_vendor_tmux

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
  session_label="${LAST_SESSION_NAME:-direct}"

  if [[ "$hung" -eq 1 ]]; then
    json_log_entry "$slot" "hung" "$elapsed" \
      "$vendor_name" "$cmd" "$session_label" "hang timeout exceeded" >> "$RUN_LOG"
    rm -f "$local_out"
    (( degraded++ )) || true
  elif [[ "$vendor_rc" -ne 0 ]]; then
    json_log_entry "$slot" "error" "$elapsed" \
      "$vendor_name" "$cmd" "$session_label" "exit $vendor_rc" >> "$RUN_LOG"
    rm -f "$local_out"
    (( degraded++ )) || true
  else
    json_log_entry "$slot" "ok" "$elapsed" \
      "$vendor_name" "$cmd" "$session_label" >> "$RUN_LOG"
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

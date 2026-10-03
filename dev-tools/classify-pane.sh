#!/usr/bin/env bash
# classify-pane.sh — classify a delegated dispatch pane, read-only (TUNE-0490
# Phase 2). Joins two signals into one verdict about a `dr-<space>-<TASK-ID>`
# tmux session so the laptop-side monitor can tell DONE from DEAD-ORPHAN from a
# slow starter — a distinction a bare shell prompt CANNOT make on its own.
#
# The two signals (both supplied by the caller so this stays pure + testable):
#   1. Pane liveness — from `tmux capture-pane -p -S -50`: does the tail look
#      like a bare shell prompt, or is an agent actively printing?
#   2. Heartbeat status — the synced datarim/runtime/<TASK-ID>.status file
#      (state + age), read via lib/heartbeat-status.sh. Authoritative for
#      DONE/AWAITING; corroborated by the pane for STALLED/ORPHAN.
#
# Verdicts (printed to stdout, one word):
#   RUNNING       — agent active (fresh status in {init,in_progress} and/or the
#                   pane shows live agent output).
#   AWAITING      — status=awaiting_operator (a hard-gate is blocking; NEVER
#                   reap — the operator relay owns this).
#   STALLED       — a live agent child exists but the heartbeat is frozen
#                   (status age past the stale threshold while a child runs);
#                   escalate, never reap.
#   DONE          — status=done (task finished; the bare prompt is expected).
#   DEAD-ORPHAN   — no live child + bare prompt + status not done + stale (or no
#                   status at all across repeated probes): a first-fork failure
#                   that left an empty shell. The reaper (Phase 3) may clear it.
#   HOLD          — ambiguous but too fresh to judge (slow starter, or fewer
#                   than the required consecutive stale probes). Default-safe:
#                   the monitor holds and re-probes rather than mis-reaping.
#
# Safety contract (from the PRD, encoded here):
#   - A non-RUNNING/non-DONE reap-eligible verdict (DEAD-ORPHAN) is emitted ONLY
#     when the caller asserts >= STALE_PROBES consecutive stale observations
#     (--stale-count). A single stale read never yields DEAD-ORPHAN.
#   - awaiting_operator ALWAYS wins over any pane appearance — a blocked gate is
#     never reaped, even if the pane looks idle.
#   - A live child ALWAYS blocks DEAD-ORPHAN (a wedged-but-alive agent is
#     STALLED, escalated, never reaped).
#
# Inputs (flags, all optional except --root/--task-id):
#   --root <DIR>             workspace root (parent of datarim/)
#   --task-id <ID>           PREFIX-NNNN
#   --pane-file <F>          file holding the captured pane tail (default: read
#                            stdin; empty = treated as bare prompt)
#   --has-child <0|1>        1 if a live agent child exists under the pane pid
#                            (caller runs pgrep -P on the host); default 0
#   --stale-count <N>        consecutive stale probes the caller has seen (used
#                            to gate DEAD-ORPHAN); default 0
#   --stale-threshold <S>    seconds after which a heartbeat is "stale"
#                            (default 600 = 10min; ORPHAN_TTL is a monitor knob)
#   --now <EPOCH>            override wall-clock now (test hook; default date +%s)
#
# Exit codes: 0 verdict printed; 2 usage error. (The verdict is on stdout;
# exit status is NOT the verdict — callers read the word.)
# shellcheck shell=bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SELF_DIR}/lib/heartbeat-status.sh"

STALE_PROBES_REQUIRED=2   # >=2 consecutive stale reads before any reap verdict

_cp_usage() { echo "classify-pane: $*" >&2; exit 2; }

root=""; task=""; pane_file=""; has_child=0; stale_count=0
stale_threshold=600; now_override=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --task-id) task="$2"; shift 2 ;;
        --pane-file) pane_file="$2"; shift 2 ;;
        --has-child) has_child="$2"; shift 2 ;;
        --stale-count) stale_count="$2"; shift 2 ;;
        --stale-threshold) stale_threshold="$2"; shift 2 ;;
        --now) now_override="$2"; shift 2 ;;
        *) _cp_usage "unknown arg $1" ;;
    esac
done
[ -n "$root" ] && [ -n "$task" ] || _cp_usage "--root and --task-id required"
case "$has_child" in 0|1) : ;; *) _cp_usage "--has-child must be 0 or 1" ;; esac
case "$stale_count" in ''|*[!0-9]*) _cp_usage "--stale-count must be an integer" ;; esac
case "$stale_threshold" in ''|*[!0-9]*) _cp_usage "--stale-threshold must be an integer" ;; esac

# --- pane tail ---------------------------------------------------------------
pane_tail=""
if [ -n "$pane_file" ]; then
    [ -f "$pane_file" ] && pane_tail="$(cat "$pane_file")"
elif [ ! -t 0 ]; then
    pane_tail="$(cat)"
fi

# A "bare prompt" pane = the last non-empty line looks like an idle shell prompt
# and there is no agent-activity marker anywhere in the tail. Agent CLIs print a
# recognisable working/spinner/prompt marker; a dead shell shows only `$`/`#`/`>`
# / `❯` with nothing after it.
_pane_is_bare_prompt() {
    local tail="$1"
    # Agent-activity markers → definitely NOT bare (live or wedged agent output).
    if printf '%s' "$tail" | grep -qiE '(esc to interrupt|Working|tokens|✻|✽|●|╭─|▐|gpt-|claude|codex|/dr-)'; then
        return 1
    fi
    local last
    last="$(printf '%s' "$tail" | awk 'NF{l=$0} END{print l}')"
    # Empty tail = treat as bare (nothing printed = dead-or-not-started shell).
    [ -z "$last" ] && return 0
    # Trailing shell-prompt glyphs with nothing meaningful after them.
    case "$last" in
        *'$'|*'$ '|*'#'|*'# '|*'>'|*'> '|*'❯'|*'❯ '|'%'|*'% ') return 0 ;;
        *) return 1 ;;
    esac
}

# --- heartbeat status --------------------------------------------------------
now="${now_override:-$(date +%s)}"
state=""; age=""
if status_json="$(hb_read --root "$root" --task-id "$task" 2>/dev/null)"; then
    if command -v jq >/dev/null 2>&1; then
        state="$(printf '%s' "$status_json" | jq -r '.state // empty')"
        updated="$(printf '%s' "$status_json" | jq -r '.updated_at // empty')"
    else
        state="$(printf '%s' "$status_json" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')"
        updated="$(printf '%s' "$status_json" | sed -n 's/.*"updated_at":\([0-9]*\).*/\1/p')"
    fi
    [ -n "$updated" ] && age=$(( now - updated ))
fi

is_stale=0
if [ -n "$age" ] && [ "$age" -ge "$stale_threshold" ]; then is_stale=1; fi
bare=0; _pane_is_bare_prompt "$pane_tail" && bare=1

# --- decision (order matters — safety-first) ---------------------------------
# 1. awaiting_operator ALWAYS wins: a blocking hard-gate is never reaped.
if [ "$state" = "awaiting_operator" ]; then
    echo "AWAITING"; exit 0
fi
# 2. done: task finished, bare prompt is expected.
if [ "$state" = "done" ]; then
    echo "DONE"; exit 0
fi
# 3. live child present:
#    - fresh heartbeat OR active pane  → RUNNING
#    - frozen heartbeat (stale) + live child → STALLED (escalate, never reap)
if [ "$has_child" = "1" ]; then
    if [ "$is_stale" = "1" ]; then echo "STALLED"; else echo "RUNNING"; fi
    exit 0
fi
# 4. no live child. Fresh in-progress/init heartbeat with a live-looking pane
#    is still RUNNING (agent printing but child-detection may lag / be unknown).
if { [ "$state" = "in_progress" ] || [ "$state" = "init" ]; } && [ "$is_stale" = "0" ]; then
    echo "RUNNING"; exit 0
fi
# 5. Reap-eligible ONLY when: no child + bare prompt + not-done + (stale OR no
#    status) AND the caller has seen >= STALE_PROBES_REQUIRED consecutive stale
#    probes. Otherwise HOLD (slow starter / not enough evidence).
if [ "$bare" = "1" ] && { [ "$is_stale" = "1" ] || [ -z "$state" ]; }; then
    if [ "$stale_count" -ge "$STALE_PROBES_REQUIRED" ]; then
        echo "DEAD-ORPHAN"; exit 0
    fi
fi
echo "HOLD"; exit 0

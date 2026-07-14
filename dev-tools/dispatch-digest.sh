#!/usr/bin/env bash
# dispatch-digest.sh — aggregate all delegated-task heartbeats into ONE digest
# (TUNE-0490 Phase 2, the "30-min digest"). Reads every synced
# datarim/runtime/*.status, groups by state, and prints a compact per-task
# report. The digest is GENERATED FROM STATUS WRITES — never by prompting the
# operator — so an autonomous monitor timer (or host-side Hermes) can post it to
# OpsBot→Telegram on an interval without any interactive step.
#
# Degradation contract (from the PRD): if the newest status is itself older than
# the sync-stale threshold, the header is flagged `SYNC STALE` — the digest must
# NEVER report a stale-synced task as falsely DONE/finished. A missing runtime
# dir is reported as "no active delegated tasks", not an error.
#
# Output is plain text (Telegram/OpsBot-friendly). One header line + one line
# per task, sorted DONE/RUNNING/AWAITING/STALLED/HOLD/DEAD-ORPHAN last so the
# actionable states (AWAITING a gate, DEAD-ORPHAN to reap) are visible.
#
# Inputs:
#   --root <DIR>              workspace root (parent of datarim/); required
#   --stale-threshold <S>     per-task heartbeat stale threshold sec (default 600)
#   --sync-stale <S>          digest-level sync-stale threshold sec (default 1800
#                             = the 30-min cadence; newest status older than this
#                             ⇒ SYNC STALE header)
#   --now <EPOCH>             test hook (default date +%s)
#   --json                    emit a JSON summary instead of text
#
# Exit codes: 0 always (a monitor digest never fails the timer); 2 usage error.
# Identifier-free, English-only — public shipped surface.
# shellcheck shell=bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SELF_DIR}/lib/heartbeat-status.sh"

_dg_usage() { echo "dispatch-digest: $*" >&2; exit 2; }

root=""; stale_threshold=600; sync_stale=1800; now_override=""; as_json=0
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --stale-threshold) stale_threshold="$2"; shift 2 ;;
        --sync-stale) sync_stale="$2"; shift 2 ;;
        --now) now_override="$2"; shift 2 ;;
        --json) as_json=1; shift ;;
        *) _dg_usage "unknown arg $1" ;;
    esac
done
[ -n "$root" ] || _dg_usage "--root required"
case "$stale_threshold" in ''|*[!0-9]*) _dg_usage "--stale-threshold integer" ;; esac
case "$sync_stale" in ''|*[!0-9]*) _dg_usage "--sync-stale integer" ;; esac

now="${now_override:-$(date +%s)}"
runtime_dir="$root/datarim/runtime"

# jq-optional field reader for a status JSON string.
_dg_field() {
    local json="$1" field="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty'
    else
        case "$field" in
            updated_at|pid) printf '%s' "$json" | sed -n "s/.*\"$field\":\([0-9]*\).*/\1/p" | head -1 ;;
            *) printf '%s' "$json" | sed -n "s/.*\"$field\":\"\([^\"]*\)\".*/\1/p" | head -1 ;;
        esac
    fi
}

# Collect rows: "task<TAB>state<TAB>stage<TAB>age".
rows=""
newest_age=""      # smallest age across all tasks = freshest write
count=0
if [ -d "$runtime_dir" ]; then
    for f in "$runtime_dir"/*.status; do
        [ -e "$f" ] || continue
        json="$(cat "$f")"
        task="$(_dg_field "$json" task_id)"
        state="$(_dg_field "$json" state)"
        stage="$(_dg_field "$json" stage)"
        updated="$(_dg_field "$json" updated_at)"
        [ -n "$task" ] || continue
        age="?"
        if [ -n "$updated" ]; then
            age=$(( now - updated ))
            if [ -z "$newest_age" ] || [ "$age" -lt "$newest_age" ]; then newest_age="$age"; fi
        fi
        rows="${rows}${task}\t${state:-unknown}\t${stage:-}\t${age}\n"
        count=$((count + 1))
    done
fi

# Sync-stale determination: the FRESHEST write is older than the sync threshold
# ⇒ the whole synced view is stale (nothing has refreshed recently).
sync_flag=""
if [ "$count" -gt 0 ] && [ -n "$newest_age" ] && [ "$newest_age" -ge "$sync_stale" ]; then
    sync_flag="SYNC STALE"
fi

if [ "$as_json" -eq 1 ]; then
    # Minimal JSON summary — per-state counts + the flag.
    printf '{"count":%s,"sync_stale":%s,"tasks":[' "$count" "$([ -n "$sync_flag" ] && echo true || echo false)"
    first=1
    if [ "$count" -gt 0 ]; then
        printf '%b' "$rows" | while IFS=$'\t' read -r t s st a; do
            [ -n "$t" ] || continue
            [ "$first" -eq 1 ] || printf ','
            printf '{"task":"%s","state":"%s","stage":"%s","age":"%s"}' "$t" "$s" "$st" "$a"
            first=0
        done
    fi
    printf ']}\n'
    exit 0
fi

# --- text digest -------------------------------------------------------------
hdr="Datarim dispatch digest — ${count} delegated task(s)"
[ -n "$sync_flag" ] && hdr="${hdr}  [${sync_flag}]"
echo "$hdr"

if [ "$count" -eq 0 ]; then
    echo "  (no active delegated tasks — datarim/runtime is empty)"
    exit 0
fi

# Sort so actionable states surface: AWAITING and DEAD-ORPHAN pinned by a rank
# prefix, then stripped. RUNNING/DONE are informational.
printf '%b' "$rows" | while IFS=$'\t' read -r t s st a; do
    [ -n "$t" ] || continue
    rank=5
    case "$s" in
        awaiting_operator) rank=0 ;;
        in_progress|init) rank=2 ;;
        done) rank=4 ;;
        *) rank=3 ;;
    esac
    # flag per-task heartbeat staleness (independent of sync-stale)
    stale_mark=""
    if [ "$a" != "?" ] && [ "$a" -ge "$stale_threshold" ] 2>/dev/null; then stale_mark=" (stale ${a}s)"; fi
    printf '%s\t  %-14s %-12s stage=%-10s age=%ss%s\n' "$rank" "$t" "$s" "${st:-—}" "$a" "$stale_mark"
done | sort -n | cut -f2-

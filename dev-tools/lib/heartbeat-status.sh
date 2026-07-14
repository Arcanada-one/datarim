#!/usr/bin/env bash
# heartbeat-status.sh — the dispatch heartbeat status-file contract (TUNE-0490
# Phase 2). A delegated agent writes a small JSON status file at
# <ROOT>/datarim/runtime/<TASK-ID>.status; the laptop-side monitor reads it to
# disambiguate a bare tmux prompt (DONE vs DEAD-ORPHAN vs slow-starter) and to
# surface hard-gate escalations. This library is the SINGLE writer/reader of
# that file so the schema never drifts between producer and consumer.
#
# Why a status file at all: a bare shell prompt on a captured pane is ambiguous
# by construction — it looks identical whether the agent finished cleanly, died
# on first fork, or simply has not printed yet. The status file is the only
# signal that resolves the ambiguity, so `state` is authoritative and the pane
# capture is corroborating (see classify-pane.sh).
#
# Schema (JSON object, one file per task):
#   task_id        string   — the PREFIX-NNNN this status describes
#   state          enum     — init | in_progress | awaiting_operator | done
#   stage          string   — current pipeline stage (init|prd|plan|do|qa|
#                             compliance|archive) or a free short label
#   updated_at     integer  — epoch seconds, WALL-CLOCK at write time. This is a
#                             liveness timer independent of task progress: a
#                             stuck agent stops refreshing it even though its
#                             `state` is unchanged, which is exactly how the
#                             monitor detects a frozen heartbeat.
#   pid            integer  — the agent/orchestrator pid on the exec host (0 if
#                             unknown); the monitor cross-checks a live child.
#   question_id    string?  — present only when state=awaiting_operator
#   question_text  string?  — the hard-gate question (operator-facing)
#   options        [string]?— the enumerated answer options; the answer channel
#                             carries an INDEX into this list, never free text.
#
# All identifiers here are schema field names, not personal data — this file is
# part of the public shipped surface (English-only, identifier-free).
#
# Verbs (invoke as a CLI, or source and call the hb_* functions directly):
#   hb_write   --root <DIR> --task-id <ID> --state <S> [--stage <ST>]
#              [--pid <N>] [--question-id <Q>] [--question-text <T>]
#              [--option <O> ...]   (repeatable; order = option index)
#   hb_read    --root <DIR> --task-id <ID>            (prints the JSON, exit 1 if absent)
#   hb_field   --root <DIR> --task-id <ID> --field <F> (prints one field's value)
#   hb_age     --root <DIR> --task-id <ID>            (prints seconds since updated_at)
#
# Exit codes: 0 ok; 1 status file absent (read/field/age); 2 usage error.
# shellcheck shell=bash
set -euo pipefail

HB_RUNTIME_RELDIR="datarim/runtime"

_hb_usage() { echo "heartbeat-status: $*" >&2; return 2; }

# Resolve <ROOT>/datarim/runtime/<TASK-ID>.status. Refuses a task-id that is not
# the canonical PREFIX-NNNN shape so a crafted id cannot escape the runtime dir.
_hb_status_path() {
    local root="$1" task="$2"
    # Strict PREFIX-NNNN: 2-10 uppercase letters, a hyphen, exactly 4 digits,
    # and NOTHING else. A bash glob `case` is too loose here (it matched
    # `lowercase-0001`); an anchored ERE is the reliable contract check and
    # closes the runtime-dir-escape vector (`../`, slashes, extra segments).
    if [[ ! "$task" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]]; then
        _hb_usage "invalid task-id '$task' (want PREFIX-NNNN)"; return 2
    fi
    printf '%s/%s/%s.status' "$root" "$HB_RUNTIME_RELDIR" "$task"
}

# Portable epoch-now. `date +%s` is universal; no Date.now()-style dependency.
_hb_now() { date +%s; }

# Emit a JSON string literal (escapes \ and " and control chars) without jq,
# so the library has no hard jq dependency for the write path.
_hb_json_str() {
    local s="$1" out="" i c
    local bs=$'\134'   # backslash via octal ANSI-C quoting (avoids SC1003)
    for (( i=0; i<${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            "$bs") out="$out\\\\" ;;
            '"') out="$out\\\"" ;;
            $'\n') out="$out\\n" ;;
            $'\t') out="$out\\t" ;;
            $'\r') out="$out\\r" ;;
            *) out="$out$c" ;;
        esac
    done
    printf '"%s"' "$out"
}

hb_write() {
    local root="" task="" state="" stage="" pid="0" qid="" qtext="" now_override=""
    local -a options=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --task-id) task="$2"; shift 2 ;;
            --state) state="$2"; shift 2 ;;
            --stage) stage="$2"; shift 2 ;;
            --pid) pid="$2"; shift 2 ;;
            --question-id) qid="$2"; shift 2 ;;
            --question-text) qtext="$2"; shift 2 ;;
            --option) options+=("$2"); shift 2 ;;
            --now) now_override="$2"; shift 2 ;;   # test hook: fixed epoch
            *) _hb_usage "unknown arg $1"; return 2 ;;
        esac
    done
    [ -n "$root" ] && [ -n "$task" ] && [ -n "$state" ] || { _hb_usage "--root, --task-id, --state required"; return 2; }
    case "$state" in
        init|in_progress|awaiting_operator|done) : ;;
        *) _hb_usage "invalid state '$state'"; return 2 ;;
    esac
    case "$pid" in ''|*[!0-9]*) pid=0 ;; esac

    local path dir
    path="$(_hb_status_path "$root" "$task")" || return 2
    dir="$(dirname "$path")"
    mkdir -p "$dir" 2>/dev/null || { _hb_usage "cannot create $dir"; return 2; }

    local now opts_json="" i
    now="${now_override:-$(_hb_now)}"
    if [ "${#options[@]}" -gt 0 ]; then
        opts_json=""
        for i in "${!options[@]}"; do
            [ "$i" -gt 0 ] && opts_json="$opts_json,"
            opts_json="$opts_json$(_hb_json_str "${options[$i]}")"
        done
        opts_json="[$opts_json]"
    fi

    # Atomic write: build in a temp file, then mv over the target so a reader
    # never sees a half-written status.
    local tmp="${path}.tmp.$$"
    {
        printf '{'
        printf '"task_id":%s,' "$(_hb_json_str "$task")"
        printf '"state":%s,' "$(_hb_json_str "$state")"
        printf '"stage":%s,' "$(_hb_json_str "$stage")"
        printf '"updated_at":%s,' "$now"
        printf '"pid":%s' "$pid"
        if [ "$state" = "awaiting_operator" ] || [ -n "$qid$qtext" ] || [ -n "$opts_json" ]; then
            printf ',"question_id":%s' "$(_hb_json_str "$qid")"
            printf ',"question_text":%s' "$(_hb_json_str "$qtext")"
            printf ',"options":%s' "${opts_json:-[]}"
        fi
        printf '}\n'
    } > "$tmp"
    mv -f "$tmp" "$path"
    printf '%s\n' "$path"
}

hb_read() {
    local root="" task=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --task-id) task="$2"; shift 2 ;;
            *) _hb_usage "unknown arg $1"; return 2 ;;
        esac
    done
    [ -n "$root" ] && [ -n "$task" ] || { _hb_usage "--root, --task-id required"; return 2; }
    local path
    path="$(_hb_status_path "$root" "$task")" || return 2
    [ -f "$path" ] || return 1
    cat "$path"
}

# Read one field. Uses jq when available (robust), else a minimal grep/sed
# fallback for the flat scalar fields (state/stage/updated_at/pid/task_id) so
# the read path degrades gracefully on a host without jq.
hb_field() {
    local root="" task="" field=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --task-id) task="$2"; shift 2 ;;
            --field) field="$2"; shift 2 ;;
            *) _hb_usage "unknown arg $1"; return 2 ;;
        esac
    done
    [ -n "$root" ] && [ -n "$task" ] && [ -n "$field" ] || { _hb_usage "--root, --task-id, --field required"; return 2; }
    local json
    json="$(hb_read --root "$root" --task-id "$task")" || return $?
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty'
        return 0
    fi
    # jq-less fallback: only flat scalar string/number fields.
    case "$field" in
        updated_at|pid)
            printf '%s' "$json" | sed -n "s/.*\"$field\":\([0-9][0-9]*\).*/\1/p" | head -1 ;;
        *)
            printf '%s' "$json" | sed -n "s/.*\"$field\":\"\([^\"]*\)\".*/\1/p" | head -1 ;;
    esac
}

hb_age() {
    local root="" task=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --task-id) task="$2"; shift 2 ;;
            *) _hb_usage "unknown arg $1"; return 2 ;;
        esac
    done
    [ -n "$root" ] && [ -n "$task" ] || { _hb_usage "--root, --task-id required"; return 2; }
    local updated now
    updated="$(hb_field --root "$root" --task-id "$task" --field updated_at)" || return $?
    [ -n "$updated" ] || return 1
    now="$(_hb_now)"
    printf '%s\n' "$(( now - updated ))"
}

# CLI dispatch when executed directly (sourcing skips this).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    verb="${1:-}"; shift || true
    case "$verb" in
        hb_write|write) hb_write "$@" ;;
        hb_read|read) hb_read "$@" ;;
        hb_field|field) hb_field "$@" ;;
        hb_age|age) hb_age "$@" ;;
        *) _hb_usage "unknown verb '${verb:-}' (write|read|field|age)"; exit 2 ;;
    esac
fi

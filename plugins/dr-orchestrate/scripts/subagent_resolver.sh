#!/usr/bin/env bash
# subagent_resolver.sh — multi-backend LLM dispatch for unknown-prompt resolution.
# TUNE-0165 M2. Fail-closed by design: parse fail / backend error / timeout / no
# JSON ⇒ fall through; chain exhaustion ⇒ confidence 0 + reason chain_exhausted.
# Threshold gating is the caller's responsibility (cmd_run.sh).
#
# Output shape (stdout, single JSON object):
#   {"action": "<slash-cmd>", "confidence": <0..1>, "reason": "<short>",
#    "backend_used": "<backend-name>", "subagent_model": "<model-or-empty>"}
#
# Public env knobs:
#   DR_ORCH_SUBAGENT_CHAIN     — space-separated backend names. Default:
#                                "coworker-deepseek claude codex".
#   DR_ORCH_RESOLVER_TIMEOUT_S — per-backend wall-clock budget (default 15).
#   STATE_DIR                  — dedup dir for "backend missing" warnings.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_SUBAGENT_CHAIN:=coworker-deepseek claude codex}"
: "${DR_ORCH_RESOLVER_TIMEOUT_S:=15}"
: "${STATE_DIR:=$HOME/.local/share/dr-orchestrate/state}"
mkdir -p "$STATE_DIR"

# shellcheck source=rules_loader.sh
source "$DR_ORCH_DIR/scripts/rules_loader.sh"

# _with_timeout <secs> <cmd...> — run cmd with FD-3 closed, stdin redirected
# from /dev/null (CLI backends like `claude --print` probe stdin for 3s
# otherwise and emit a "no stdin data received" warning), and a kill-on-
# overrun watchdog. Echoes stdout, returns the command's rc, or 124 on timeout.
_with_timeout() {
  local secs="$1"; shift
  local outfile; outfile="$(mktemp)"
  ( exec 3>&-; "$@" </dev/null >"$outfile" 2>/dev/null ) &
  local pid=$! elapsed=0 rc
  while (( elapsed < secs )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null; rc=$?
      cat "$outfile"; rm -f "$outfile"
      return "$rc"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  kill -TERM "$pid" 2>/dev/null
  sleep 1
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  cat "$outfile"; rm -f "$outfile"
  return 124
}

# _backend_cmd <name> — print the command vector for the named backend, one
# arg per line. Returns 0 if recognised, 2 otherwise. The prompt is read from
# stdin and passed as the last argument by _invoke_backend.
_resolve_backend() {
  case "$1" in
    coworker-deepseek) echo coworker; echo ask; echo --provider; echo deepseek; echo --profile; echo code; echo --question ;;
    coworker-groq)     echo coworker; echo ask; echo --provider; echo groq;     echo --profile; echo code; echo --question ;;
    claude)            echo claude; echo --print; echo --output-format=json ;;
    codex)             echo codex; echo exec; echo --output-last-message; echo - ;;
    mock-*)            echo "dr-orch-mock-${1#mock-}" ;;
    *)                 return 2 ;;
  esac
}

_backend_present() {
  local first; first="$(_resolve_backend "$1" | head -1)" || return 1
  command -v "$first" >/dev/null 2>&1
}

_warn_missing_once() {
  local backend="$1"
  local sentinel="$STATE_DIR/.warned.${backend}"
  [[ -f "$sentinel" ]] && return 0
  echo "WARN backend-missing backend=${backend}" >&2
  : > "$sentinel"
}

# Strip the [coworker: ...] preamble line and any trailing "Shell cwd was reset"
# noise; leave the JSON-bearing body for the lenient extractor.
_normalize() {
  local backend="$1"; local raw="$2"
  case "$backend" in
    claude)
      local r
      r="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null)"
      if [[ -n "$r" ]]; then printf '%s' "$r"; else printf '%s' "$raw"; fi
      ;;
    *) printf '%s' "$raw" ;;
  esac
}

_extract_json() {
  local raw="$1"
  if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$raw"
    return 0
  fi
  local fenced
  fenced="$(printf '%s' "$raw" | awk '/^```json/{f=1;next} /^```/{f=0} f' )"
  if [[ -n "$fenced" ]] && printf '%s' "$fenced" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$fenced"
    return 0
  fi
  local block
  block="$(printf '%s' "$raw" | perl -0777 -ne 'if (/(\{(?:[^{}]|(?1))*\})/s) { print $1 }')"
  if [[ -n "$block" ]] && printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$block"
    return 0
  fi
  return 1
}

_build_prompt() {
  local pane_text="$1"
  local rules; rules="$(load)"
  local actions
  actions="$(printf '%s' "$rules" | jq -r '[.[].action] | unique | join(" ")')"
  cat <<PROMPT
You are a strict classifier for a Datarim CLI pipeline pane.
Pick the single most likely intended slash-command from this closed set:
  ${actions}

Respond with ONLY a JSON object — no prose, no markdown fences:
  {"action":"/dr-...","confidence":<float 0..1>,"reason":"<short>"}

If no command applies, set "confidence" to 0 and "action" to "".

Pane text to classify:
---
${pane_text}
---
PROMPT
}

_invoke() {
  local backend="$1"; local prompt="$2"
  local -a cmd
  while IFS= read -r line; do cmd+=("$line"); done < <(_resolve_backend "$backend")
  if (( ${#cmd[@]} == 0 )); then return 2; fi
  # Last position carries the prompt for argv-style backends (coworker --question, claude, codex).
  case "$backend" in
    mock-*) _with_timeout "$DR_ORCH_RESOLVER_TIMEOUT_S" "${cmd[@]}" ;;
    *)      _with_timeout "$DR_ORCH_RESOLVER_TIMEOUT_S" "${cmd[@]}" "$prompt" ;;
  esac
}

resolve() {
  local pane_text="${1:-}"
  local prompt; prompt="$(_build_prompt "$pane_text")"
  local backend raw json model
  for backend in $DR_ORCH_SUBAGENT_CHAIN; do
    if ! _backend_present "$backend"; then
      _warn_missing_once "$backend"
      continue
    fi
    raw="$(_invoke "$backend" "$prompt" || true)"
    [[ -n "$raw" ]] || continue
    raw="$(_normalize "$backend" "$raw")"
    json="$(_extract_json "$raw" 2>/dev/null || true)"
    [[ -n "$json" ]] || continue
    printf '%s' "$json" | jq -e '.action and (.confidence | type == "number")' >/dev/null 2>&1 || continue
    model=""
    case "$backend" in
      coworker-deepseek) model="deepseek-chat" ;;
      coworker-groq)     model="groq-llama" ;;
      claude)            model="claude-opus-4-7" ;;
      codex)             model="codex" ;;
      mock-*)            model="$backend" ;;
    esac
    printf '%s' "$json" | jq -c \
      --arg b "$backend" --arg m "$model" \
      '. + {backend_used: $b, subagent_model: $m, reason: (.reason // "")}'
    return 0
  done
  jq -n -c '{action:"", confidence:0, reason:"chain_exhausted", backend_used:"none", subagent_model:""}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: subagent_resolver.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi

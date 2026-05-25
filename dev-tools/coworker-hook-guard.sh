#!/usr/bin/env bash
# Hook guard that nudges coding agents (Claude, Codex CLI, …) to delegate
# bulk I/O to the coworker tool.
#
#   - PreToolUse on Claude tools  : Read | Write | Bash
#   - PreToolUse on Codex tools   : view | apply_patch | shell | exec_command
#   - SessionStart                : Moonshot balance probe (canary)
#
# Codex CLI 0.133 native tool names (verified via ~/.codex/logs_2.sqlite —
# 83 apply_patch events, exec_command frequent, no `shell`/`view`):
#   apply_patch    — patch-format file create/update/delete
#   exec_command   — shell-style command invocation
#   update_plan    — planning UI tool (not bulk-I/O, passed through)
#   write_stdin    — interactive stdin (not bulk-I/O, passed through)
# `shell` and `view` are retained as defensive aliases in case a future
# codex version normalises tool names to those Claude-equivalent labels.
#
# emit_deny → permissionDecision="deny" + reason. Silent (exit 0 with no
# stdout) means "no opinion, continue normal flow".
#
# Lineage:
#   - Migrated from kimi-hook-guard 2026-05-07 (TUNE-0127), vendor-neutral.
#   - Codex coverage added 2026-05-25 (TUNE-0303). Canonical source moves
#     into Datarim repo `dev-tools/coworker-hook-guard.sh`;
#     ~/.local/bin/coworker-hook-guard is a symlink fanned out by
#     install.sh fanout_runtime.
#
# Backwards-compat: KIMI_GUARD_* env vars still honoured as fallback.
set -euo pipefail

THRESHOLD_READ_LINES="${COWORKER_GUARD_READ_THRESHOLD:-${KIMI_GUARD_READ_THRESHOLD:-400}}"
THRESHOLD_BALANCE_USD="${COWORKER_GUARD_BALANCE_THRESHOLD:-${KIMI_GUARD_BALANCE_THRESHOLD:-3}}"

emit_deny() {
  jq -nc --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}

emit_session_message() {
  jq -nc --arg m "$1" '{ systemMessage: $m }'
}

# Returns 0 (success) if the given destination path should trigger a deny
# because it represents the FIRST DRAFT of a protected docs artefact.
# Returns 1 otherwise (existing file, unknown destination, exempt path).
#
# Protected: wiki/*, Social Media/*, prd-*.md, plan-*.md, creative-*.md,
# *-task-description.md. Exempt by omission: archive-*.md, reflection-*.md
# (operator decision 2026-05-24 — see CLAUDE.md § Exempt).
check_write_protected() {
  local f="$1"
  [ -n "$f" ] || return 1
  [ -e "$f" ] && return 1
  local base
  base=$(basename "$f")
  case "$f" in
    */wiki/*|*/Social\ Media/*) return 0 ;;
  esac
  case "$base" in
    prd-*.md|plan-*.md|creative-*.md|*-task-description.md) return 0 ;;
  esac
  return 1
}

emit_write_deny() {
  local f="$1"
  local base
  base=$(basename "$f")
  emit_deny "Создаёшь $base — это документационный артефакт. Per CLAUDE.md MANDATORY: первый draft через coworker write --profile datarim --spec \"...\" --context <refs> --target \"$f\", потом surgical edits. Approve только если уже сгенерирован coworker'ом."
}

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')

if [ "$event" = "SessionStart" ] || [ -z "$(printf '%s' "$input" | jq -r '.tool_name // empty')" ]; then
  if [ "$event" = "SessionStart" ]; then
    if [ -n "${MOONSHOT_API_KEY:-}" ] && command -v curl >/dev/null && command -v jq >/dev/null; then
      bal=$(curl -sf --max-time 4 -H "Authorization: Bearer $MOONSHOT_API_KEY" \
        https://api.moonshot.ai/v1/users/me/balance 2>/dev/null \
        | jq -r '.data.available_balance // empty' 2>/dev/null || true)
      if [ -n "$bal" ]; then
        low=$(awk -v b="$bal" -v t="$THRESHOLD_BALANCE_USD" 'BEGIN { print (b+0 < t+0) ? 1 : 0 }')
        if [ "$low" = "1" ]; then
          emit_session_message "⚠️  Moonshot balance low: \$${bal} (<\$${THRESHOLD_BALANCE_USD}). Top up or switch to '--provider deepseek' before scripts start failing with 429."
        fi
      fi
    fi
    exit 0
  fi
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

case "$tool" in
  Read|view)
    # Claude Read uses tool_input.file_path; codex view uses tool_input.path.
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
    [ -n "$f" ] && [ -f "$f" ] || exit 0
    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ' || echo 0)
    if [ "${lines:-0}" -gt "$THRESHOLD_READ_LINES" ]; then
      emit_deny "Файл $f — $lines строк (>$THRESHOLD_READ_LINES). Per CLAUDE.md MANDATORY: используй coworker ask --paths \"$f\" --question \"...\" вместо прямого Read. Approve только если действительно нужны точные line numbers для Edit."
    fi
    exit 0
    ;;
  Write)
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    if check_write_protected "$f"; then
      emit_write_deny "$f"
    fi
    exit 0
    ;;
  apply_patch)
    # Codex apply_patch payload — extract `*** Add File: <path>` headers and
    # apply Write-equivalent rules. Update File / Delete File entries pass
    # through (not first-draft of a new artefact). The raw patch body is
    # never logged — sed treats the path as an opaque string per S1.
    body=$(printf '%s' "$input" | jq -r '.tool_input.input // empty')
    [ -n "$body" ] || exit 0
    while IFS= read -r addpath; do
      [ -n "$addpath" ] || continue
      if check_write_protected "$addpath"; then
        emit_write_deny "$addpath"
        exit 0
      fi
    done < <(printf '%s' "$body" | sed -n 's/^\*\*\* Add File: //p')
    exit 0
    ;;
  Bash|shell|exec_command)
    # Claude Bash, codex shell (alias), codex exec_command all expose
    # tool_input.command. exec_command is the actual codex 0.133 emission;
    # shell is reserved for forward-compat / alias.
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    [ -n "$cmd" ] || exit 0
    # TUNE-0156: HEAD-blind branch creation gate.
    # Deny `git checkout -b NAME` / `git switch -c NAME` without 4th positional
    # start-point (`main` / SHA / explicit `HEAD`). Compound commands fall
    # through. See documentation/mandates/workspace-discipline.md Rule 11.
    read -r -a __words <<< "$cmd"
    if [ "${#__words[@]}" = "4" ] && [ "${__words[0]}" = "git" ]; then
      if { [ "${__words[1]}" = "checkout" ] && [ "${__words[2]}" = "-b" ]; } \
         || { [ "${__words[1]}" = "switch" ] && [ "${__words[2]}" = "-c" ]; }; then
        emit_deny 'git checkout -b NAME без explicit start-point в shared workspace. Per documentation/mandates/workspace-discipline.md Rule 11: укажи `main` / SHA / HEAD после имени ветки. Reason: INFRA-0116 incident class — sibling-session HEAD inheritance.'
        exit 0
      fi
    fi
    # Skip if already delegated to coworker (or legacy shims).
    case "$cmd" in *coworker\ ask*|*coworker\ write*|*ask-kimi*|*kimi-write*) exit 0 ;; esac
    trigger=0
    case "$cmd" in
      *"git diff"*) trigger=1 ;;
      *"git log -p"*|*"git log --patch"*) trigger=1 ;;
      *"git show"*) trigger=1 ;;
    esac
    case "$cmd" in
      *"| head"*|*"| tail"*|*"| wc"*|*"| grep"*|*"--stat"*|*"--name-only"*|*"--name-status"*|*"--shortstat"*) trigger=0 ;;
    esac
    if [ "$trigger" = "1" ]; then
      emit_deny "Команда '${cmd}' может вернуть >200 строк diff/log. Per CLAUDE.md MANDATORY: пайпь в coworker ask — например '${cmd} | coworker ask --question \"summarize changes\"'. Approve если уверен, что output короткий."
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

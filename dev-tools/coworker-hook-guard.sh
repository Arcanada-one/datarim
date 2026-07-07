#!/usr/bin/env bash
# Hook guard that nudges coding agents (Claude, Codex CLI, …) to delegate
# bulk I/O to the coworker tool.
#
#   - PreToolUse on Claude tools  : Read | Write | Bash
#   - PreToolUse on Codex tools   : view | apply_patch | shell | exec_command
#   - SessionStart                : balance canary — fires ONLY when the
#                                   resolved coworker provider is Moonshot
#                                   (profile.recommended_provider ->
#                                   COWORKER_DEFAULT_PROVIDER -> literal
#                                   moonshot; mirrors providers.py resolver)
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
# shellcheck shell=bash
set -euo pipefail

# --- KB pre-overwrite backup side-effect -------------------------------------
# The guard is the only universal enforcement point in front of BOTH the Write
# tool and Bash overwrites (awk/tee/redirect), on every machine. When a write
# targets a critical KB file under a resolved datarim/, take a fail-soft
# pre-overwrite backup so a stray truncation or inter-agent race is recoverable.
# Source the resolver + backup primitive from the canonical repo (this script
# is symlinked into ~/.local/bin; follow the link to find the lib dir). Any
# sourcing failure leaves the backup hooks as no-ops — the guard's primary
# delegation behaviour is unaffected.
# Resolve this script's real path, following a one-level symlink (the install
# topology: ~/.local/bin/coworker-hook-guard → canonical dev-tools/…). Avoids
# `readlink -f` which is not portable to stock macOS.
_GUARD_SRC="${BASH_SOURCE[0]}"
if [ -L "$_GUARD_SRC" ]; then
  _GUARD_TGT="$(readlink "$_GUARD_SRC" 2>/dev/null || true)"
  case "$_GUARD_TGT" in
    /*) _GUARD_SRC="$_GUARD_TGT" ;;
    ?*) _GUARD_SRC="$(dirname "$_GUARD_SRC")/$_GUARD_TGT" ;;
  esac
fi
_GUARD_LIB="$(cd "$(dirname "$_GUARD_SRC")/../scripts/lib" 2>/dev/null && pwd || true)"
_KB_BACKUP_READY=0
if [ -n "$_GUARD_LIB" ] && [ -f "$_GUARD_LIB/kb-backup.sh" ] && [ -f "$_GUARD_LIB/resolve-datarim-root.sh" ]; then
  # shellcheck source=../scripts/lib/resolve-datarim-root.sh
  if . "$_GUARD_LIB/resolve-datarim-root.sh" 2>/dev/null; then
    # shellcheck source=../scripts/lib/kb-backup.sh
    if . "$_GUARD_LIB/kb-backup.sh" 2>/dev/null; then
      _KB_BACKUP_READY=1
    fi
  fi
fi

# Back up <target> if it is an existing critical KB file under a datarim/.
# Always returns 0 (fail-soft) - must never block the write it precedes.
#
# <target> may be RELATIVE: a Bash redirect (awk ... > backlog.md) or a Write
# file_path carries whatever the agent typed, which is relative when the
# session cwd is already inside the KB - the exact original incident shape.
# The second arg <base_cwd> is the PreToolUse payload's cwd (the directory the
# command runs in); a relative target is canonicalised against it before the
# repo-root resolve + datarim/ membership match. Without this, the bare-name
# incident vector silently skipped the backup.
kb_backup_if_critical() {
  [ "$_KB_BACKUP_READY" = 1 ] || return 0
  local target="$1" base_cwd="${2:-$PWD}" abs base repo_root rel
  [ -n "$target" ] || return 0
  # Canonicalise a relative target against the session cwd.
  case "$target" in
    /*) abs="$target" ;;
    *)  abs="$base_cwd/$target" ;;
  esac
  [ -f "$abs" ] || return 0
  base="$(basename "$abs")"
  kb_is_critical_basename "$base" || return 0
  # Resolve the repo-root from the file's own directory.
  repo_root="$(resolve_datarim_root "$(dirname "$abs")" 2>/dev/null || true)"
  [ -n "$repo_root" ] || return 0
  # relpath under datarim/ - the target must live inside <repo_root>/datarim/.
  case "$abs" in
    "$repo_root"/datarim/*) rel="${abs#"$repo_root"/datarim/}" ;;
    *) return 0 ;;
  esac
  backup_critical_kb_file "$repo_root" "$rel" 2>/dev/null || true
  return 0
}

# Read gate is token-estimation based: est_tokens = wc -c / divisor (divisor
# by extension), with a delegation point and a hard ceiling that routes to
# grep-only. Legacy line-count vars (COWORKER_GUARD_READ_THRESHOLD /
# KIMI_GUARD_READ_THRESHOLD) are ignored — see the SessionStart deprecation
# note below; the value is never reinterpreted as bytes/tokens.
DELEGATE_TOKENS="${COWORKER_GUARD_DELEGATE_TOKENS:-10000}"
CEILING_TOKENS="${COWORKER_GUARD_CEILING_TOKENS:-100000}"
USE_TOKENIZER="${COWORKER_GUARD_USE_TOKENIZER:-0}"
TOKENIZER_BIN="${COWORKER_GUARD_TOKENIZER_BIN:-tiktoken}"
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
# Resolve the exempt-patterns allowlist path. Default: sibling of this script's
# real path (works under symlink/copy/project-install — _GUARD_SRC is already
# readlink-resolved above). Per-project override via COWORKER_GUARD_EXEMPT_FILE.
exempt_file_path() {
  if [ -n "${COWORKER_GUARD_EXEMPT_FILE:-}" ]; then
    printf '%s' "$COWORKER_GUARD_EXEMPT_FILE"
  else
    printf '%s' "$(dirname "$_GUARD_SRC")/coworker-delegation-exempt.patterns"
  fi
}

# Returns 0 if <basename> matches an exempt glob in the allowlist (the doc is an
# architectural decision the global rule says to write directly, NOT delegate).
# Returns 1 otherwise — including when the allowlist is absent/unreadable
# (fail-soft toward the gate: no file ⇒ no exemptions ⇒ prior deny behaviour).
#
# S1: pattern lines are used ONLY as `case` glob operands. Never eval'd, never
# sourced, never command-substituted. Matching is case-insensitive via tr
# (portable to macOS bash 3.2 — no `shopt nocasematch`, no `${var,,}`).
is_delegation_exempt() {
  local base="$1" ef lc_base lc_pat line
  ef=$(exempt_file_path)
  [ -f "$ef" ] && [ -r "$ef" ] || return 1
  lc_base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r line || [ -n "$line" ]; do
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'#'*) continue ;; esac
    lc_pat=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    # SC2254 intentionally NOT silenced by quoting: $lc_pat MUST expand as a
    # glob pattern (e.g. creative-*architecture*.md), not match literally. The
    # value is an allowlist glob, never user file content, and is used only as a
    # case operand — never eval'd/sourced (S1). Quoting it would break the gate.
    # shellcheck disable=SC2254
    case "$lc_base" in
      $lc_pat) return 0 ;;
    esac
  done < "$ef"
  return 1
}

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
    prd-*.md|plan-*.md|*-task-description.md) return 0 ;;
    creative-*.md)
      # Architectural creative-docs are exempt from delegation (write directly).
      is_delegation_exempt "$base" && return 1
      return 0
      ;;
  esac
  return 1
}

emit_write_deny() {
  local f="$1"
  local base
  base=$(basename "$f")
  emit_deny "Создаёшь $base — это документационный артефакт. Per CLAUDE.md MANDATORY: первый draft через coworker write --profile datarim-write --spec \"...\" --context <refs> --target \"$f\", потом surgical edits. Approve только если уже сгенерирован coworker'ом. Если это АРХИТЕКТУРНОЕ решение (ADR / threat-model / design) — global rule «Do NOT delegate → Architectural decisions» разрешает писать напрямую: добавь glob имени в coworker-delegation-exempt.patterns (рядом с хуком) ИЛИ пиши через Bash heredoc (хук не гейтит Bash). Делегируй coworker'у только настоящие черновики, НЕ имитируй compliance пустышкой."
}

# Read-branch deny wording, bound to the crossed token threshold. The wording
# is a named contract surface: the ceiling message MUST steer to byte-window
# tools (sed/grep/head — never an LLM); the delegate message MUST lead with the
# Bash-native edit hatch + coworker ask. The precondition guards implement the
# § Defensive Invariants contract — they catch a future refactor that emits one
# tier's wording on the other tier's branch.
emit_read_deny() {
  local tier="$1" f="$2" est="$3"
  local est_k=$(( est / 1000 ))
  case "$tier" in
    ceiling)
      if [ "$est" -le "$CEILING_TOKENS" ]; then
        echo "ERROR: internal invariant violated: ceiling deny but est=$est <= CEILING=$CEILING_TOKENS" >&2
        exit 2
      fi
      emit_deny "Файл $f — ~${est_k}k est-токенов (>${CEILING_TOKENS} ceiling) — больше безопасного context-window любого провайдера. НЕ отправляй ни в какую LLM. Читай нужное окно: sed -n 'A,Bp' \"$f\" / grep -n PATTERN -A/-B \"$f\" / head / tail."
      ;;
    delegate)
      if [ "$est" -le "$DELEGATE_TOKENS" ] || [ "$est" -gt "$CEILING_TOKENS" ]; then
        echo "ERROR: internal invariant violated: delegate deny but est=$est outside (${DELEGATE_TOKENS}, ${CEILING_TOKENS}]" >&2
        exit 2
      fi
      emit_deny "Файл $f — ~${est_k}k est-токенов (>${DELEGATE_TOKENS}). Для точечного edit применяй его через Bash python3/sed (guard НЕ гейтит Bash) — Read-precondition Edit'а тогда не нужен. Для bulk-понимания: coworker ask --paths \"$f\" --question \"...\". Поднять порог можно ТОЛЬКО релончем (COWORKER_GUARD_DELEGATE_TOKENS=N claude) — in-session '! export' до хука не доходит."
      ;;
    *)
      echo "ERROR: internal invariant violated: unknown deny tier '$tier'" >&2
      exit 2
      ;;
  esac
}

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
# Session cwd from the PreToolUse payload (Claude Code includes it). It anchors
# the canonicalisation of RELATIVE Write/Bash-redirect targets to the right KB
# - the bare-name incident vector (awk ... > backlog.md run inside datarim/).
# Fall back to the hook process $PWD when the field is absent.
session_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$session_cwd" ] || session_cwd="$PWD"

if [ "$event" = "SessionStart" ] || [ -z "$(printf '%s' "$input" | jq -r '.tool_name // empty')" ]; then
  if [ "$event" = "SessionStart" ]; then
    session_msg=""
    # Legacy line-count thresholds are ignored under the token model. Warn
    # ONCE per session-start; never reinterpret the value as bytes/tokens
    # (a stale `=700` must not silently become 700 bytes).
    if [ -n "${COWORKER_GUARD_READ_THRESHOLD:-}" ] || [ -n "${KIMI_GUARD_READ_THRESHOLD:-}" ]; then
      session_msg="⚠️  COWORKER_GUARD_READ_THRESHOLD / KIMI_GUARD_READ_THRESHOLD устарели (line-based) и игнорируются. Token-based пороги: COWORKER_GUARD_DELEGATE_TOKENS (default 10000), COWORKER_GUARD_CEILING_TOKENS (default 100000)."
    fi
    # Balance canary is provider-specific. Resolve the active coworker provider
    # the way coworker itself does (providers.py resolve_provider_and_model):
    #   profile.recommended_provider -> COWORKER_DEFAULT_PROVIDER -> "moonshot".
    # SessionStart carries no --provider flag; the mandated default profile is
    # `datarim`, so read that profile first. Reading the env var FIRST would
    # reproduce the stale-Moonshot bug (env=moonshot masks the real deepseek
    # default). Fail-soft: any lookup miss leaves coworker's own "moonshot"
    # fallback in place — never block SessionStart.
    active_provider=""
    if command -v yq >/dev/null 2>&1 \
       && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/coworker/profiles.yaml" ]; then
      active_provider=$(yq -r '.datarim.recommended_provider // ""' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/coworker/profiles.yaml" 2>/dev/null || true)
    fi
    [ -n "$active_provider" ] || active_provider="${COWORKER_DEFAULT_PROVIDER:-}"
    [ -n "$active_provider" ] || active_provider="moonshot"
    active_provider=$(printf '%s' "$active_provider" | tr '[:upper:]' '[:lower:]')
    # The hardcoded probe below only understands Moonshot's endpoint + JSON
    # shape. Skip it unless Moonshot is the resolved provider — otherwise the
    # mere presence of MOONSHOT_API_KEY (both keys are often exported) warns
    # about a provider coworker is not actually using. (DeepSeek balance probe
    # is intentionally out of scope here — see follow-up; providers.yaml zero
    # pricing makes the DeepSeek balance endpoint the only live budget signal,
    # a larger change with per-vendor JSON quirks incl. is_available:false.)
    if [ "$active_provider" = "moonshot" ] && [ -n "${MOONSHOT_API_KEY:-}" ] \
       && command -v curl >/dev/null && command -v jq >/dev/null; then
      bal=$(curl -sf --max-time 4 -H "Authorization: Bearer $MOONSHOT_API_KEY" \
        https://api.moonshot.ai/v1/users/me/balance 2>/dev/null \
        | jq -r '.data.available_balance // empty' 2>/dev/null || true)
      if [ -n "$bal" ]; then
        low=$(awk -v b="$bal" -v t="$THRESHOLD_BALANCE_USD" 'BEGIN { print (b+0 < t+0) ? 1 : 0 }')
        if [ "$low" = "1" ]; then
          bal_msg="⚠️  Moonshot balance low: \$${bal} (<\$${THRESHOLD_BALANCE_USD}) and Moonshot is the resolved coworker provider. Top up, or set a cheaper default (e.g. COWORKER_DEFAULT_PROVIDER=deepseek / --provider deepseek) before scripts start failing with 429."
          if [ -n "$session_msg" ]; then
            session_msg="${session_msg}"$'\n'"${bal_msg}"
          else
            session_msg="$bal_msg"
          fi
        fi
      fi
    fi
    [ -n "$session_msg" ] && emit_session_message "$session_msg"
    exit 0
  fi
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

case "$tool" in
  Read|view)
    # Claude Read uses tool_input.file_path; codex view uses tool_input.path.
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
    [ -n "$f" ] && [ -f "$f" ] || exit 0
    # Read-gate applies ONLY to documentation (.md / .markdown / .txt). Coworker
    # saves tokens on prose + RTK; program code the agent reads natively (Read
    # offset/limit, sed windows, grep), and `coworker ask` rejects non-doc
    # extensions with exit 6 anyway — gating code here is a dead-end deny. Any
    # other extension AND extension-less files pass through silently before any
    # byte/token estimation. Allowlist by operator decision; case-sensitive by
    # design (an uppercase .MD passing through is safer than a wrong deny).
    case "$f" in
      *.md|*.markdown|*.txt) ;;   # doc → fall through to token estimation
      *) exit 0 ;;                 # code / blob / no-extension → agent handles it
    esac
    bytes=$(wc -c < "$f" 2>/dev/null | tr -d ' ' || echo 0)
    bytes="${bytes:-0}"
    est=""
    # Opt-in fast tokenizer (fail-soft): use ONLY when explicitly enabled AND
    # the binary is present; any non-numeric output falls back to the byte
    # heuristic. Local binary on a quoted path, no network, no eval.
    if [ "$USE_TOKENIZER" = "1" ] && command -v "$TOKENIZER_BIN" >/dev/null 2>&1; then
      est=$("$TOKENIZER_BIN" "$f" 2>/dev/null || echo "")
      case "$est" in ''|*[!0-9]*) est="" ;; esac
    fi
    if [ -z "$est" ]; then
      # Byte heuristic: est_tokens = wc -c / divisor. Divisor by extension,
      # conservative-DOWNWARD (dense classes get a smaller divisor; never /4 —
      # under-estimating is the dangerous false-negative).
      case "$f" in
        *.b64|*.base64)     divisor=1 ;;
        *.min.js|*.min.css) divisor=2 ;;
        *)                  divisor=3 ;;
      esac
      est=$(( bytes / divisor ))
    fi
    if [ "$est" -gt "$CEILING_TOKENS" ]; then
      emit_read_deny ceiling "$f" "$est"
    elif [ "$est" -gt "$DELEGATE_TOKENS" ]; then
      emit_read_deny delegate "$f" "$est"
    fi
    exit 0
    ;;
  Write)
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    # Pre-overwrite backup side-effect (fail-soft, never blocks the write).
    kb_backup_if_critical "$f" "$session_cwd"
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
    # Pre-overwrite backup side-effect for the awk/tee/redirect class (the
    # actual incident: `awk … > backlog.md`). Best-effort: extract `> TARGET`,
    # `>> TARGET`, and `tee TARGET` operands and back up any that are critical
    # KB files. Obfuscated/computed redirects are out of scope (documented in
    # the recovery how-to). $cmd is never eval'd — operands are matched, not run.
    if [ "$_KB_BACKUP_READY" = 1 ]; then
      # `>`/`>>` redirect targets (may be relative - resolved against cwd)
      printf '%s\n' "$cmd" \
        | grep -oE '>>?[[:space:]]*[^[:space:]|;&<>]+' 2>/dev/null \
        | sed -E 's/^>>?[[:space:]]*//' \
        | while IFS= read -r _rt; do [ -n "$_rt" ] && kb_backup_if_critical "$_rt" "$session_cwd"; done || true
      # `tee [-a] TARGET...` operands (may be relative - resolved against cwd)
      printf '%s\n' "$cmd" \
        | grep -oE 'tee([[:space:]]+-a)?[[:space:]]+[^[:space:]|;&<>]+' 2>/dev/null \
        | sed -E 's/^tee([[:space:]]+-a)?[[:space:]]+//' \
        | while IFS= read -r _rt; do [ -n "$_rt" ] && kb_backup_if_critical "$_rt" "$session_cwd"; done || true
    fi
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
    # `git show <ref>:<path>` is a blob read (cat of a file at a revision) —
    # small + structured, signal not bulk. Disambiguate from `git show <commit>`
    # (diff/log dump). If the command is a git-show and any non-flag arg carries
    # a colon (the <ref>:<path> shape) → passthrough. `read -a` word-splits but
    # does NOT glob, so no path expansion (S1-safe — $cmd is never eval'd).
    case "$cmd" in
      *"git show"*)
        read -r -a __sw <<< "$cmd"
        for __a in "${__sw[@]}"; do
          case "$__a" in
            -*) ;;
            *:*) trigger=0 ;;
          esac
        done
        ;;
    esac
    # Reset when an output limiter or redirect makes the result short or empty:
    # head/tail/wc/grep/sed/awk pipes, git output-shape flags, --no-pager, and a
    # stdout redirect (`X > file` yields no stdout to pipe into coworker ask).
    case "$cmd" in
      *"| head"*|*"| tail"*|*"| wc"*|*"| grep"*|*"| sed"*|*"| awk"*|*"--stat"*|*"--name-only"*|*"--name-status"*|*"--shortstat"*|*"--no-pager"*|*" > "*) trigger=0 ;;
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

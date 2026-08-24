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
#   DR_FLEET_VERSION_HINTS     - set to 1 for best-effort CLI version advice.
#   DR_FLEET_VERSION_TIMEOUT_S - version-probe budget in seconds (default 2).
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_SUBAGENT_CHAIN:=coworker-deepseek claude codex}"
: "${DR_ORCH_RESOLVER_TIMEOUT_S:=15}"
: "${DR_FLEET_VERSION_TIMEOUT_S:=2}"
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
    coworker-deepseek) echo coworker; echo ask; echo --provider; echo deepseek; echo --profile; echo classifier; echo --question ;;
    coworker-groq)     echo coworker; echo ask; echo --provider; echo groq;     echo --profile; echo classifier; echo --question ;;
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

# --- Fleet interactive backend selection (design 3b) ---------------------------
# Distinct from resolve()'s headless inference path: fleet spawns a LIVE
# interactive CLI agent in tmux (operator correction A2 — NO `claude --print`).
# _resolve_fleet_backend prints the interactive launch command vector (one arg
# per line). ARAS is a deferred slot (never resolves until implemented).

# Fleet backend chain (priority): Claude → Codex → Cursor → Gemini → Coworker.
: "${DR_FLEET_BACKEND_CHAIN:=claude codex cursor gemini coworker}"

_resolve_fleet_backend() {
  case "$1" in
    claude)   echo claude ;;
    codex)    echo codex ;;
    cursor)   echo cursor ;;
    gemini)   echo gemini ;;
    coworker) echo coworker ;;   # bulk-I/O L1/L2 delegated call (not a live REPL)
    aras)     return 2 ;;        # deferred slot — treated as unavailable
    *)        return 2 ;;
  esac
}

_fleet_backend_present() {
  local first; first="$(_resolve_fleet_backend "$1")" || return 1
  command -v "$first" >/dev/null 2>&1
}

_fleet_cli_version_hint() {
  local backend="$1" executable="$2" raw version
  [ "${DR_FLEET_VERSION_HINTS:-0}" = "1" ] || return 0
  raw="$(_with_timeout "$DR_FLEET_VERSION_TIMEOUT_S" "$executable" --version)" \
    || return 0
  version="${raw%%$'\n'*}"
  version="${version:0:160}"
  [ -n "$version" ] || return 0
  printf 'ADVISORY: CLI %s %s detected; prefer the newest stable version when upgrades are permitted.\n' \
    "$backend" "$version" >&2
  return 0
}

# select_fleet_backend — walk DR_FLEET_BACKEND_CHAIN, return the first backend
# whose binary is present (health-check). Echoes the backend NAME on success.
# CONN wiring is OFF by default (DR_FLEET_CONN_ENABLED unset → contract-first
# stub: pure `command -v` health-check). When the real CONN-0088 fallback ships,
# the enabled branch routes through its contract without changing this interface.
select_fleet_backend() {
  local backend first
  for backend in $DR_FLEET_BACKEND_CHAIN; do
    # Health-check. Default (stub) path = local `command -v`. When CONN-0088
    # ships, DR_FLEET_CONN_ENABLED routes the check through the Model-Connector
    # fallback contract; the loop interface stays identical.
    if [ -n "${DR_FLEET_CONN_ENABLED:-}" ]; then
      _fleet_backend_present_conn "$backend" || continue
    else
      _fleet_backend_present "$backend" || continue
    fi
    first="$(_resolve_fleet_backend "$backend")" || first=""
    _fleet_cli_version_hint "$backend" "$first" || true
    printf '%s\n' "$backend"
    return 0
  done
  echo "ERROR: no fleet backend available in chain: $DR_FLEET_BACKEND_CHAIN" >&2
  return 1
}

# CONN-0088 contract-first stub. Until the Model Connector fallback-chain ships,
# this defers to the local health-check. Replace the body with the real CONN
# probe (HTTP /health against the connector) when DR_FLEET_CONN_ENABLED is the
# documented production path.
_fleet_backend_present_conn() {
  # Contract: returns 0 if the backend is reachable via CONN, non-zero otherwise.
  _fleet_backend_present "$1"
}

# fleet_role_session_init <role> — emit the per-role session-start injection a
# live fleet agent receives at spawn (design 3b): its complete executable role
# projection, read from the role registry. The orchestrator pipes these into the
# spawned session so role identity, skills, path scope, and forbidden actions
# cannot disappear between registry validation and runtime activation.
# Output (one key per line, machine-readable):
#   STARTER_SKILL=<skills/fleet/...>
#   ALLOWED_TOOLS=<comma-separated tool names>
#   AGENT=<agents/...md>                         (when configured)
#   DOMAIN_SKILLS=<space-separated skills/...>  (when configured)
#   ALLOWED_PATHS=<space-separated safe roots>
#   PRODUCT_CODE_ACCESS=<none|read-only|read-write>
#   FORBIDDEN_ACTIONS=<space-separated action ids>
# Unknown role or unsafe id ⇒ fail closed (non-zero, nothing emitted).
# DR_ORCH_DIR is the plugin root (plugins/dr-orchestrate); the role registry
# lives at the framework repo root (two levels up), matching fleet_concurrency.sh.
: "${DR_FLEET_REPO:=$(cd "$DR_ORCH_DIR/../.." && pwd)}"
: "${DR_FLEET_ROLES:=$DR_FLEET_REPO/config/roles.yaml}"

fleet_role_session_init() {
  local role="${1:-}"
  [[ "$role" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "ERROR: invalid role id" >&2; return 2; }
  [ -f "$DR_FLEET_ROLES" ] || { echo "ERROR: roles file not found: $DR_FLEET_ROLES" >&2; return 1; }
  python3 - "$DR_FLEET_ROLES" "$role" <<'PY' || { echo "ERROR: unknown role: $role" >&2; return 1; }
import re
import sys
import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        if not isinstance(key_node, yaml.nodes.ScalarNode):
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "mapping keys must be scalar",
                key_node.start_mark,
            )
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate YAML key: {key}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


def safe_list(entry, key, required=False):
    if required and key not in entry:
        raise ValueError(f"missing {key}")
    value = entry.get(key, [])
    if value is None and not required:
        value = []
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError(f"malformed {key}")
    return value


def safe_tokens(values, pattern, label):
    if any(re.fullmatch(pattern, value) is None for value in values):
        raise ValueError(f"unsafe {label}")
    return values


try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        doc = yaml.load(handle, Loader=UniqueKeyLoader) or {}
except (OSError, TypeError, yaml.YAMLError) as exc:
    problem = getattr(exc, "problem", None) or str(exc)
    print(f"ERROR: invalid role registry YAML: {problem}", file=sys.stderr)
    sys.exit(3)
role = sys.argv[2]
if not isinstance(doc, dict):
    print("ERROR: invalid role registry shape: root must be a mapping", file=sys.stderr)
    sys.exit(3)
roles = doc.get("roles")
if not isinstance(roles, list):
    print("ERROR: invalid role registry shape: roles must be a list", file=sys.stderr)
    sys.exit(3)
for index, r in enumerate(roles):
    if not isinstance(r, dict):
        print(
            f"ERROR: invalid role registry shape: roles[{index}] must be a mapping",
            file=sys.stderr,
        )
        sys.exit(3)
    if r.get("id") == role:
        skill = r.get("starter_skill")
        try:
            tools = safe_tokens(safe_list(r, "allowed_tools", required=True), r"[A-Za-z][A-Za-z0-9_-]*", "allowed_tools")
            paths = safe_tokens(safe_list(r, "allowed_paths", required=True), r"[A-Za-z0-9_./*-]+", "allowed_paths")
            forbidden = safe_tokens(safe_list(r, "forbidden_actions", required=True), r"[a-z][a-z0-9-]*", "forbidden_actions")
            domain_skills = safe_tokens(safe_list(r, "domain_skills"), r"skills/[a-z][a-z0-9-]*", "domain_skills")
        except ValueError as exc:
            print(f"ERROR: invalid role registry shape: {exc}", file=sys.stderr)
            sys.exit(3)
        agent = r.get("agent")
        if not isinstance(skill, str) or re.fullmatch(r"skills/[a-z0-9-]+/[a-z0-9-]+", skill) is None:
            sys.exit(3)   # malformed role entry → fail closed
        if agent is not None and (
            not isinstance(agent, str)
            or re.fullmatch(r"agents/[a-z][a-z0-9-]*\.md", agent) is None
        ):
            sys.exit(3)
        product_paths = [path for path in paths if path.startswith("Projects/") and "/code/" in path]
        knowledge_paths = [path.removesuffix("/**") for path in paths if path not in product_paths]
        if any("*" in path for path in knowledge_paths):
            sys.exit(3)
        if product_paths:
            product_access = "read-only" if "product-code-write" in forbidden else "read-write"
        else:
            product_access = "none"
        print(f"STARTER_SKILL={skill}")
        print("ALLOWED_TOOLS=" + ",".join(str(t) for t in tools))
        if agent:
            print(f"AGENT={agent}")
        if domain_skills:
            print("DOMAIN_SKILLS=" + " ".join(domain_skills))
        print("ALLOWED_PATHS=" + " ".join(knowledge_paths))
        print(f"PRODUCT_CODE_ACCESS={product_access}")
        print("FORBIDDEN_ACTIONS=" + " ".join(forbidden))
        sys.exit(0)
sys.exit(4)   # role not found
PY
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
  local pane_text="$1" hint="${2:-}"
  local rules; rules="$(load)"
  local actions action_kinds
  actions="$(printf '%s' "$rules" | jq -r '[.[].action] | unique | join(" ")')"
  action_kinds="$(load_action_autonomy_map 2>/dev/null \
    | jq -r 'keys | join(" ")' 2>/dev/null || true)"
  cat <<PROMPT
You are a strict classifier for a Datarim CLI pipeline pane.
Pick the single most likely intended slash-command from this closed set:
  ${actions}

Respond with ONLY a JSON object — no prose, no markdown fences:
  {"action":"/dr-...","confidence":<float 0..1>,"reason":"<short>",
   "action_kind":"<optional operational kind>","action_payload":{}}

When the pane requests a normally gated operational action, set action_kind
from this closed set and include required booleans in action_payload:
  ${action_kinds}
Otherwise omit action_kind or set it to an empty string.

If no command applies, set "confidence" to 0 and "action" to "".

Pane text to classify:
---
${pane_text}
---
Advisory snapshot recommendation (never authoritative): ${hint:-none}
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
  local hint="" pane_text=""
  if [[ "${1:-}" == "--hint" ]]; then
    hint="${2:-}"; [[ "$hint" =~ ^/dr-[a-z-]+$ ]] || hint=""; shift 2
    [[ "${1:-}" == "--" ]] && shift
  fi
  pane_text="${1:-}"
  if [[ -n "${DR_ORCH_RESOLVER_HINT_LOG:-}" ]]; then
    printf '%s\n' "${hint:-none}" >"$DR_ORCH_RESOLVER_HINT_LOG"
  fi
  local prompt; prompt="$(_build_prompt "$pane_text" "$hint")"
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

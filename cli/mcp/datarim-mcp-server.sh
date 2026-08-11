#!/usr/bin/env bash
# datarim-mcp-server.sh — Model Context Protocol (MCP) server exposing Datarim
# commands / skills / agents to Codex CLI over stdio JSON-RPC 2.0 (TUNE-0301).
#
# Codex's MCP client (probed, 0.142.5) consumes TOOLS only (initialize →
# notifications/initialized → tools/list); it never requests prompts/resources.
# So commands/skills/agents are exposed as MCP tools via a bounded dispatcher.
# prompts/* and resources/* handlers exist for other clients but are NOT
# advertised in `initialize` (avoids conformance obligations — architect panel).
#
# TRANSPORT INVARIANT: stdout carries ONLY newline-delimited JSON-RPC messages.
# Every diagnostic goes to stderr. This server NEVER execs artefact content and
# makes NO network calls — it reads framework files and returns their text.
#
# Design record: datarim/creative/creative-TUNE-0301-design.md
# Deps: bash 4+, jq, awk, realpath.

# NB: intentionally NO `set -e` — a JSON-RPC read loop must survive any single
# non-zero return (a whitelist miss, a grep no-match) by emitting an error and
# continuing (V-AC-7). `-u`/pipefail stay; `-f` disables globbing on names.
set -uo pipefail
set -f
IFS=$' \t\n'
export LC_ALL=C

# Resource backstops (DoS): file size + CPU. Best-effort; ignore if unsupported.
ulimit -f 65536 2>/dev/null || true   # 32 MB max file the process may create
ulimit -t 300   2>/dev/null || true

MCP_MAX_LINE="${MCP_MAX_LINE:-65536}"   # reject JSON-RPC lines larger than this
JQ_TIMEOUT="${MCP_JQ_TIMEOUT:-10}"      # seconds ceiling for any jq parse

_MCP_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cli/mcp/lib/mcp-catalog.sh
source "$_MCP_SELF/lib/mcp-catalog.sh"

# --- root + version --------------------------------------------------------
# Default DATARIM_ROOT = framework repo root (script lives at <root>/cli/mcp/).
DATARIM_ROOT="${DATARIM_ROOT:-$(cd "$_MCP_SELF/../.." && pwd)}"
MCP_ROOT="$(mcp_guard_root "$DATARIM_ROOT")" || {
    echo "mcp: fatal — DATARIM_ROOT guard failed; refusing to start" >&2
    exit 1
}
SERVER_NAME="datarim"
SERVER_VERSION="$(cat "$MCP_ROOT/VERSION" 2>/dev/null || echo "unknown")"
PROTOCOL_FALLBACK="2025-06-18"

# --- JSON-RPC emit helpers (stdout) ---------------------------------------
emit_result() {   # <id-json> <result-json>
    jq -cn --argjson id "$1" --argjson result "$2" \
        '{jsonrpc:"2.0", id:$id, result:$result}'
}
emit_error() {    # <id-json> <code> <message>
    jq -cn --argjson id "$1" --argjson code "$2" --arg msg "$3" \
        '{jsonrpc:"2.0", id:$id, error:{code:$code, message:$msg}}'
}
_text_result() {  # <text> [isError]  -> result json for tools/call
    jq -cn --arg t "$1" --argjson err "${2:-false}" \
        '{content:[{type:"text", text:$t}], isError:$err}'
}

# --- tool catalogue (fixed) -----------------------------------------------
tools_list_json() {
    jq -cn '{tools: [
      {name:"datarim_list_commands",
       description:"List all Datarim slash-commands (/dr-*) with descriptions.",
       inputSchema:{type:"object", properties:{}, additionalProperties:false}},
      {name:"datarim_run_command",
       description:"Return the full instruction body of a Datarim command by name (e.g. dr-status). The caller executes the returned instructions.",
       inputSchema:{type:"object", properties:{name:{type:"string", description:"command name, e.g. dr-plan"}, args:{type:"string", description:"optional arguments"}}, required:["name"], additionalProperties:false}},
      {name:"datarim_list_skills",
       description:"List all Datarim skills with descriptions.",
       inputSchema:{type:"object", properties:{}, additionalProperties:false}},
      {name:"datarim_get_skill",
       description:"Return the full body of a Datarim skill by name (e.g. brainstorming).",
       inputSchema:{type:"object", properties:{name:{type:"string"}}, required:["name"], additionalProperties:false}},
      {name:"datarim_list_agents",
       description:"List all Datarim agents with descriptions.",
       inputSchema:{type:"object", properties:{}, additionalProperties:false}},
      {name:"datarim_get_agent",
       description:"Return the full definition of a Datarim agent by name (e.g. architect).",
       inputSchema:{type:"object", properties:{name:{type:"string"}}, required:["name"], additionalProperties:false}}
    ]}'
}

# --- tools/call dispatch ---------------------------------------------------
# Emits a tools/call *result* json on stdout for the caller to wrap, OR nothing
# and returns 2 to signal a JSON-RPC -32602 (bad tool / missing arg).
handle_tool_call() {   # <tool> <arguments-json>
    local tool="$1" args="$2" name body kind
    case "$tool" in
        datarim_list_commands) _text_result "$(mcp_list "$MCP_ROOT" commands)"; return 0 ;;
        datarim_list_skills)   _text_result "$(mcp_list "$MCP_ROOT" skills)";   return 0 ;;
        datarim_list_agents)   _text_result "$(mcp_list "$MCP_ROOT" agents)";   return 0 ;;
        datarim_run_command) kind=commands ;;
        datarim_get_skill)   kind=skills ;;
        datarim_get_agent)   kind=agents ;;
        *) return 2 ;;   # unknown tool -> -32602
    esac
    name="$(printf '%s' "$args" | jq -r '.name // empty' 2>/dev/null)"
    [[ -n "$name" ]] || return 2   # missing required arg -> -32602
    if body="$(mcp_body "$MCP_ROOT" "$kind" "$name")"; then
        _text_result "$body"
    else
        # Valid tool, unknown target: isError result (logical name only, no path).
        _text_result "No such $kind artefact: $name" true
    fi
    return 0
}

# --- prompts / resources (bonus, unadvertised) ----------------------------
prompts_list_json() { jq -cn --argjson c "$(mcp_list "$MCP_ROOT" commands)" \
    '{prompts: ($c | map({name:.name, description:.description}))}'; }
resources_list_json() {
    local s a
    s="$(mcp_list "$MCP_ROOT" skills)"; a="$(mcp_list "$MCP_ROOT" agents)"
    jq -cn --argjson s "$s" --argjson a "$a" \
      '{resources: (($s|map({uri:("datarim://skill/"+.name), name:.name, description:.description, mimeType:"text/markdown"})) + ($a|map({uri:("datarim://agent/"+.name), name:.name, description:.description, mimeType:"text/markdown"})))}'
}

# --- request router --------------------------------------------------------
route() {   # <line>
    local line="$1" method id has_id
    method="$(printf '%s' "$line" | jq -r '.method // empty' 2>/dev/null)"
    id="$(printf '%s' "$line" | jq -c '.id' 2>/dev/null)"; [[ -n "$id" ]] || id="null"
    has_id="$(printf '%s' "$line" | jq -e 'has("id")' >/dev/null 2>&1 && echo yes || echo no)"

    case "$method" in
        initialize)
            local pv
            pv="$(printf '%s' "$line" | jq -r '.params.protocolVersion // empty' 2>/dev/null)"
            [[ -n "$pv" ]] || pv="$PROTOCOL_FALLBACK"
            emit_result "$id" "$(jq -cn --arg pv "$pv" --arg nm "$SERVER_NAME" --arg ver "$SERVER_VERSION" \
                '{protocolVersion:$pv, capabilities:{tools:{}}, serverInfo:{name:$nm, version:$ver}}')"
            ;;
        notifications/*) : ;;   # notifications never get a response
        ping) [[ "$has_id" == yes ]] && emit_result "$id" '{}' ;;
        tools/list) emit_result "$id" "$(tools_list_json)" ;;
        tools/call)
            local tool args res rc
            tool="$(printf '%s' "$line" | jq -r '.params.name // empty' 2>/dev/null)"
            args="$(printf '%s' "$line" | jq -c '.params.arguments // {}' 2>/dev/null)"
            res="$(handle_tool_call "$tool" "$args")"; rc=$?
            if [[ $rc -eq 2 ]]; then
                emit_error "$id" -32602 "Unknown tool or missing required argument: ${tool:-?}"
            else
                emit_result "$id" "$res"
            fi
            ;;
        prompts/list) emit_result "$id" "$(prompts_list_json)" ;;
        prompts/get)
            local pname pbody
            pname="$(printf '%s' "$line" | jq -r '.params.name // empty' 2>/dev/null)"
            if pbody="$(mcp_body "$MCP_ROOT" commands "$pname")"; then
                emit_result "$id" "$(jq -cn --arg t "$pbody" '{messages:[{role:"user", content:{type:"text", text:$t}}]}')"
            else
                emit_error "$id" -32602 "Unknown prompt"
            fi
            ;;
        resources/list) emit_result "$id" "$(resources_list_json)" ;;
        resources/read)
            local uri rkind rname rbody
            uri="$(printf '%s' "$line" | jq -r '.params.uri // empty' 2>/dev/null)"
            case "$uri" in
                datarim://skill/*) rkind=skills; rname="${uri#datarim://skill/}" ;;
                datarim://agent/*) rkind=agents; rname="${uri#datarim://agent/}" ;;
                *) rkind=""; rname="" ;;
            esac
            if [[ -n "$rkind" ]] && rbody="$(mcp_body "$MCP_ROOT" "$rkind" "$rname")"; then
                emit_result "$id" "$(jq -cn --arg u "$uri" --arg t "$rbody" '{contents:[{uri:$u, mimeType:"text/markdown", text:$t}]}')"
            else
                emit_error "$id" -32602 "Unknown resource"
            fi
            ;;
        "")
            # No method: only answer if it's a request (has id); else ignore.
            [[ "$has_id" == yes ]] && emit_error "$id" -32600 "Invalid Request"
            ;;
        *)
            [[ "$has_id" == yes ]] && emit_error "$id" -32601 "Method not found: $method"
            ;;
    esac
}

# --- main read loop --------------------------------------------------------
main() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        if [[ ${#line} -gt $MCP_MAX_LINE ]]; then
            emit_error "null" -32600 "Request too large"; continue
        fi
        case "$line" in
            \[*) emit_error "null" -32600 "Batch requests are not supported"; continue ;;
        esac
        if ! printf '%s' "$line" | timeout "$JQ_TIMEOUT" jq -e . >/dev/null 2>&1; then
            emit_error "null" -32700 "Parse error"; continue
        fi
        route "$line"
    done
}

main "$@"

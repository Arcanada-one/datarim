#!/usr/bin/env bash
# output.sh — foundation output envelope для Datarim CLI subcommands.
# Source: creative-TUNE-0268-architecture-subcommand-output-shape.md § IP-1
#         Option B (plain text default + --json envelope opt-in).
#
# Public API:
#   output_emit_json <data-json>             — composes envelope с data field, writes к stdout
#   output_emit_plain <text>                 — writes <text> к stdout (no envelope)
#   output_emit_error <exit> <name> <msg>    — JSON-mode → envelope; plain → stderr text; exits
#   output_emit_warn <text>                  — always stderr regardless of mode
#   output_strip_ansi <text>                 — removes ANSI escape sequences
#
# Env vars consumed:
#   DATARIM_CLI_CMD   — command label embedded in envelope (set by dispatcher)
#   OUTPUT_MODE       — "json" | "plain" (default "plain"); set by --json arg parse
#
# Dependencies: jq (composition), date -u (ISO-8601 timestamp).

[[ -n "${_OUTPUT_LOADED:-}" ]] && return 0
_OUTPUT_LOADED=1

_OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=exit-codes.sh
source "$_OUTPUT_DIR/exit-codes.sh"

: "${DATARIM_CLI_CMD:=unknown}"
: "${OUTPUT_MODE:=plain}"

# Strip ANSI CSI escape sequences (color codes etc).
output_strip_ansi() {
    local text="${1-}"
    printf '%s' "$text" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
}

# Internal: emit canonical envelope JSON with given data and error fields.
# Args: <data-json-or-null> <error-json-or-null>
_output_envelope() {
    local data="${1:-null}"
    local err="${2:-null}"
    local ts
    ts="$(date -u +%FT%TZ)"
    jq -n \
        --arg version "1" \
        --arg cmd "$DATARIM_CLI_CMD" \
        --arg ts "$ts" \
        --argjson data "$data" \
        --argjson err "$err" \
        '{version: $version, command: $cmd, ts: $ts, data: $data, error: $err}'
}

output_emit_json() {
    local data="${1:?output_emit_json: data JSON required}"
    _output_envelope "$data" null
}

output_emit_plain() {
    local text="${1-}"
    printf '%s\n' "$text"
}

output_emit_error() {
    local exit_code="${1:?output_emit_error: exit code required}"
    local err_name="${2:?output_emit_error: error name required}"
    local message="${3:?output_emit_error: message required}"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local err_json
        err_json="$(jq -n \
            --arg code "$err_name" \
            --argjson exit "$exit_code" \
            --arg msg "$message" \
            '{code: $code, exit: $exit, message: $msg}')"
        _output_envelope null "$err_json"
    else
        printf '%s: %s\n' "$err_name" "$message" >&2
    fi
    exit "$exit_code"
}

# Hybrid emit — error envelope с partial data (e.g. collisions list для
# ID_COLLISION_DETECTED). Foundation line 146 разрешает data ≠ null когда
# вызывающий передаёт partial-data context.
output_emit_error_with_data() {
    local exit_code="${1:?output_emit_error_with_data: exit code required}"
    local err_name="${2:?output_emit_error_with_data: error name required}"
    local message="${3:?output_emit_error_with_data: message required}"
    local data_json="${4:?output_emit_error_with_data: data JSON required}"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local err_json
        err_json="$(jq -n \
            --arg code "$err_name" \
            --argjson exit "$exit_code" \
            --arg msg "$message" \
            '{code: $code, exit: $exit, message: $msg}')"
        _output_envelope "$data_json" "$err_json"
    else
        printf '%s: %s\n' "$err_name" "$message" >&2
    fi
    exit "$exit_code"
}

output_emit_warn() {
    local text="${1-}"
    printf '%s\n' "$text" >&2
}

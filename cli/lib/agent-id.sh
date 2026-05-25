#!/usr/bin/env bash
# cli/lib/agent-id.sh — DATARIM_CLI_AGENT_ID env validation (UUID v7).
# Source: TUNE-0271 plan § Detailed Design 4.6.
#
# Contract:
#   - $DATARIM_CLI_AGENT_ID MUST be set, non-empty, UUID v7 format.
#   - Exit 22 on missing, malformed, or out-of-range timestamp.
#
# Caller pattern:
#   . "$(dirname "$0")/lib/agent-id.sh"
#   validate_agent_id || exit $?

set -u

CLI_AGENT_ID_EXIT_INVALID=22

# UUID v7 regex (8-4-4-4-12, version nibble = 7, variant nibble ∈ {8,9,a,b}).
CLI_AGENT_ID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

# Extract first 48 bits (12 hex chars) of UUID and decode as Unix-ms timestamp.
# Echoes the ms value on stdout; empty on parse failure.
_cli_uuid7_extract_ms() {
    local uuid="$1" hex ms
    # Strip dashes, take first 12 chars (48 bits).
    hex="${uuid//-/}"
    hex="${hex:0:12}"
    # Bash 3 can't handle 64-bit integers reliably across all platforms;
    # delegate to python3 for portability (python3 is also the UUID v7
    # generation fallback per D-D).
    ms=$(python3 -c "import sys; print(int(sys.argv[1], 16))" "$hex" 2>/dev/null || true)
    printf '%s' "$ms"
}

validate_agent_id() {
    local id="${DATARIM_CLI_AGENT_ID:-}"
    if [ -z "$id" ]; then
        printf '[agent-id] DATARIM_CLI_AGENT_ID is unset or empty; set a UUID v7 (see docs/cli.md § Agent identity)\n' >&2
        return $CLI_AGENT_ID_EXIT_INVALID
    fi
    if ! printf '%s' "$id" | grep -Eq "$CLI_AGENT_ID_RE"; then
        printf '[agent-id] DATARIM_CLI_AGENT_ID="%s" is not a valid UUID v7\n' "$id" >&2
        return $CLI_AGENT_ID_EXIT_INVALID
    fi
    local ms now_ms min_ms max_ms
    ms=$(_cli_uuid7_extract_ms "$id")
    if [ -z "$ms" ]; then
        printf '[agent-id] DATARIM_CLI_AGENT_ID="%s" timestamp parse failed\n' "$id" >&2
        return $CLI_AGENT_ID_EXIT_INVALID
    fi
    now_ms=$(python3 -c "import time; print(int(time.time()*1000))")
    # 10 years window backwards, 1 hour forwards.
    min_ms=$(( now_ms - 10 * 365 * 24 * 60 * 60 * 1000 ))
    max_ms=$(( now_ms + 60 * 60 * 1000 ))
    if [ "$ms" -lt "$min_ms" ] || [ "$ms" -gt "$max_ms" ]; then
        printf '[agent-id] DATARIM_CLI_AGENT_ID="%s" timestamp out of acceptable window (now=%s, ms=%s)\n' "$id" "$now_ms" "$ms" >&2
        return $CLI_AGENT_ID_EXIT_INVALID
    fi
    return 0
}

#!/usr/bin/env bash
# fleet-validate-message.sh — Schema validator for fleet bus messages.
#
# Usage:
#   fleet-validate-message.sh --id <uuid> --ts <ISO-8601> --type <enum> \
#                              --from <agent> --to <agent>
#
# Exits 0 if all required fields pass validation.
# Exits 1 with a descriptive error message on stderr/stdout if validation fails.
#
# Required fields:
#   --id    Non-empty string (UUID recommended)
#   --ts    ISO-8601 datetime (e.g. 2026-06-09T12:00:00Z)
#   --type  One of: lifecycle | alert | command | audit | heartbeat |
#                   level-reassigned | agent-spawned | agent-killed
#
# Optional fields (no validation, passed through):
#   --from  Sender agent identifier
#   --to    Destination agent/topic identifier
#
# Env:
#   DR_FLEET_VALIDATOR_STRICT=1 — also require --from and --to

set -uo pipefail

# ── valid type enum ───────────────────────────────────────────────────────────

readonly VALID_TYPES="lifecycle alert command audit heartbeat level-reassigned agent-spawned agent-killed"

# ── arg parser ────────────────────────────────────────────────────────────────

msg_id=""
msg_ts=""
msg_type=""
msg_from=""
msg_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)    msg_id="$2";   shift 2 ;;
    --ts)    msg_ts="$2";   shift 2 ;;
    --type)  msg_type="$2"; shift 2 ;;
    --from)  msg_from="$2"; shift 2 ;;
    --to)    msg_to="$2";   shift 2 ;;
    --help)
      printf 'usage: fleet-validate-message.sh --id <id> --ts <ISO-8601> --type <enum> [--from <x>] [--to <y>]\n'
      printf 'valid types: %s\n' "$VALID_TYPES"
      exit 0
      ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

# ── validation ────────────────────────────────────────────────────────────────

errors=()

# Validate id: must be non-empty
if [[ -z "$msg_id" ]]; then
  errors+=("INVALID: id is required and must be non-empty")
fi

# Validate ts: must match ISO-8601 basic pattern YYYY-MM-DDTHH:MM:SSZ (or +offset)
# Pattern: YYYY-MM-DDTHH:MM:SS followed by Z or ±HH:MM
if [[ -z "$msg_ts" ]]; then
  errors+=("INVALID: ts is required")
elif ! [[ "$msg_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([Z]|[+-][0-9]{2}:[0-9]{2})$ ]]; then
  errors+=("INVALID: ts must be ISO-8601 datetime (e.g. 2026-06-09T12:00:00Z), got: $msg_ts")
fi

# Validate type: must be in enum
if [[ -z "$msg_type" ]]; then
  errors+=("INVALID: type is required")
else
  valid=0
  for t in $VALID_TYPES; do
    [[ "$msg_type" == "$t" ]] && { valid=1; break; }
  done
  if (( ! valid )); then
    errors+=("INVALID: type must be one of [$VALID_TYPES], got: $msg_type")
  fi
fi

# Strict mode: also require from/to
if [[ "${DR_FLEET_VALIDATOR_STRICT:-0}" == "1" ]]; then
  [[ -z "$msg_from" ]] && errors+=("INVALID: --from is required in strict mode")
  [[ -z "$msg_to" ]]   && errors+=("INVALID: --to is required in strict mode")
fi

# ── output ────────────────────────────────────────────────────────────────────

if (( ${#errors[@]} > 0 )); then
  for err in "${errors[@]}"; do
    printf '%s\n' "$err"
  done
  exit 1
fi

exit 0

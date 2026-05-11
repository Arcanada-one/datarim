#!/usr/bin/env bash
# run-schemathesis.sh — Schemathesis contract test runner for orchestrator-interface.
# Wraps schemathesis against a running reference impl instance.
#
# Usage:
#   run-schemathesis.sh [--base-url <url>] [--schema <path>] [--max-examples <n>]
#
# Environment:
#   DR_ORCH_SCHEMATHESIS_URL      — override base URL (default http://127.0.0.1:8090)
#   DR_ORCH_INBOUND_TOKEN         — bearer token for auth header
#
# Exit codes:
#   0 — all checks pass
#   1 — schemathesis violations found
#   2 — schemathesis not installed (known-deferred to CI)
#   3 — reference impl not reachable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_URL="${DR_ORCH_SCHEMATHESIS_URL:-http://127.0.0.1:8090}"
SCHEMA="${PLUGIN_ROOT}/openapi/orchestrator-interface.yaml"
MAX_EXAMPLES=20

while (( $# > 0 )); do
  case "$1" in
    --base-url)      BASE_URL="$2";      shift 2 ;;
    --schema)        SCHEMA="$2";        shift 2 ;;
    --max-examples)  MAX_EXAMPLES="$2";  shift 2 ;;
    -h|--help)
      printf 'usage: run-schemathesis.sh [--base-url <url>] [--schema <path>] [--max-examples <n>]\n' >&2
      exit 0
      ;;
    *) printf 'ERR: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! command -v schemathesis >/dev/null 2>&1 && ! python3 -m schemathesis --version >/dev/null 2>&1; then
  printf 'SKIP: schemathesis not installed (known-deferred to CI)\n' >&2
  printf 'Install: pip install schemathesis\n' >&2
  exit 2
fi

# Check base URL reachability.
if ! curl -fsS --max-time 5 "$BASE_URL" >/dev/null 2>&1; then
  printf 'ERR: reference impl not reachable at %s\n' "$BASE_URL" >&2
  printf 'Start with: webhook -hooks %s/config/hooks.yaml -port 8090 -verbose\n' "$PLUGIN_ROOT" >&2
  exit 3
fi

AUTH_HEADER=""
if [[ -n "${DR_ORCH_INBOUND_TOKEN:-}" ]]; then
  AUTH_HEADER="--header Authorization:Bearer ${DR_ORCH_INBOUND_TOKEN}"
fi

# shellcheck disable=SC2086
schemathesis run \
  --base-url "$BASE_URL" \
  --checks all \
  --hypothesis-max-examples "$MAX_EXAMPLES" \
  ${AUTH_HEADER} \
  "$SCHEMA"

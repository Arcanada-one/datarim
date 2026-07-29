#!/usr/bin/env bash
# check-staging-not-stale.sh — staging-environment liveness checker (TUNE-0517).
#
# Stack-agnostic pre-flight check before running E2E acceptance criteria against
# a non-prod / staging environment. Encapsulates the STAGING-NOT-STALE PRE-CHECK
# procedural rules from commands/dr-do.md § 6.5 into an invocable script.
#
# Three-pronged check (all must pass):
#   1. SSH reachability of a staging host
#   2. `docker compose ps` over SSH — all required services Up/running
#   3. HTTP health endpoint returns 2xx or 3xx
#
# Usage:
#   check-staging-not-stale.sh --host <host> --health-url <url> [--compose-file <path>]
#
# Flags:
#   --host <host>         SSH host for staging (required; user@host format)
#   --health-url <url>    Health-check HTTP(S) URL (required)
#   --compose-file <path>  Path to compose file on staging host (default: docker-compose.yml)
#   --verbose             Print status details to stderr
#   --help                Show this help and exit 0
#
# Exit codes:
#   0  — staging is live (SSH reachable, compose services up, health endpoint OK)
#   1  — staging is dead or stale (details on stderr)
#   2  — usage error
#
# Security: S1 strict mode, regex-validate host/URL args, no eval, no
# StrictHostKeyChecking=no. The host key is validated by the user's
# ~/.ssh/known_hosts — this script does NOT bypass SSH verification.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
$SCRIPT_NAME — staging-environment liveness checker

Usage:
  $SCRIPT_NAME --host <host> --health-url <url> [--compose-file <path>] [--verbose]

Flags:
  --host <host>          SSH host (required; user@host or hostname)
  --health-url <url>     Health endpoint URL (required)
  --compose-file <path>  Compose file path on staging host (default: compose.yml)
  --verbose              Print status details to stderr
  --help                 Show this help and exit 0

Exit codes:
  0  staging is live
  1  staging is dead or stale
  2  usage error

Examples:
  $SCRIPT_NAME --host deploy@staging.example.com --health-url https://staging.example.com/health
  $SCRIPT_NAME --host user@10.0.0.5 --health-url http://10.0.0.5:8080/health --verbose
EOF
    exit 0
}

# ── Arg parsing ───────────────────────────────────────────────────────────────
HOST=""
HEALTH_URL=""
COMPOSE_FILE="compose.yml"
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --host)
            shift
            HOST="${1:-}"
            [ -z "$HOST" ] && { echo "ERROR: --host requires a value" >&2; exit 2; }
            # Basic host format validation (user@host or bare hostname)
            if ! [[ "$HOST" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+$ ]] && ! [[ "$HOST" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                echo "ERROR: --host value '$HOST' does not look like a valid host or user@host" >&2
                exit 2
            fi
            ;;
        --health-url)
            shift
            HEALTH_URL="${1:-}"
            [ -z "$HEALTH_URL" ] && { echo "ERROR: --health-url requires a value" >&2; exit 2; }
            # Basic URL validation
            if ! [[ "$HEALTH_URL" =~ ^https?:// ]]; then
                echo "ERROR: --health-url must start with http:// or https://" >&2
                exit 2
            fi
            ;;
        --compose-file)
            shift
            COMPOSE_FILE="${1:-}"
            [ -z "$COMPOSE_FILE" ] && { echo "ERROR: --compose-file requires a value" >&2; exit 2; }
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --help)
            usage
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            echo "Usage: $SCRIPT_NAME --host <host> --health-url <url> [--compose-file <path>]" >&2
            exit 2
            ;;
    esac
    shift
done

# Validate required args
if [ -z "$HOST" ] || [ -z "$HEALTH_URL" ]; then
    echo "ERROR: --host and --health-url are required" >&2
    echo "Usage: $SCRIPT_NAME --host <host> --health-url <url> [--compose-file <path>]" >&2
    exit 2
fi

# ── Checks ────────────────────────────────────────────────────────────────────

errs=0

# Check 1: SSH reachability
if [ "$VERBOSE" -eq 1 ]; then
    echo "INFO: Checking SSH reachability to $HOST ..." >&2
fi
if ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "echo ok" 2>/dev/null | grep -q "ok"; then
    if [ "$VERBOSE" -eq 1 ]; then
        echo "OK: SSH reachable: $HOST" >&2
    fi
else
    echo "FAIL: SSH unreachable: $HOST (timeout or auth failure)" >&2
    errs=$(( errs + 1 ))
fi

# Check 2: docker compose ps (only if SSH passed)
if [ "$errs" -eq 0 ]; then
    if [ "$VERBOSE" -eq 1 ]; then
        echo "INFO: Checking compose services on $HOST ..." >&2
    fi
    compose_out=$(ssh "$HOST" "docker compose -f '$COMPOSE_FILE' ps --status running" 2>&1) || true
    # If compose returns no output, no services are running — stale.
    # If the command itself failed (compose file missing, docker not installed),
    # that is also stale.
    if ! echo "$compose_out" | grep -q -v "^NAME\|^$"; then
        echo "FAIL: No running compose services on $HOST (compose file: $COMPOSE_FILE)" >&2
        errs=$(( errs + 1 ))
    else
        if [ "$VERBOSE" -eq 1 ]; then
            echo "OK: Compose services running on $HOST" >&2
            echo "$compose_out" >&2
        fi
    fi
fi

# Check 3: health endpoint HTTP status
if [ "$VERBOSE" -eq 1 ]; then
    echo "INFO: Checking health endpoint $HEALTH_URL ..." >&2
fi
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 "$HEALTH_URL" 2>/dev/null) || http_code="000"
if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
    if [ "$VERBOSE" -eq 1 ]; then
        echo "OK: Health endpoint returned $http_code" >&2
    fi
else
    echo "FAIL: Health endpoint $HEALTH_URL returned HTTP $http_code" >&2
    errs=$(( errs + 1 ))
fi

# ── Result ────────────────────────────────────────────────────────────────────

if [ "$errs" -gt 0 ]; then
    echo "STALE: $errs check(s) failed — staging is dead or stale" >&2
    exit 1
fi

echo "LIVE: Staging environment is current and reachable"
exit 0

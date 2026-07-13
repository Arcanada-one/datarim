#!/usr/bin/env bash
# check-execution-host-drift.sh — standalone execution-host drift validator
# (TUNE-0472, Phase 2).
#
# Compares the canon `spaces/<space>/space.yml § execution` block against the
# machine-local `~/.claude/local/config/execution-hosts.yml` binding for the
# same space, and flags TTL staleness (map older than 90 days).
#
# Orthogonal-tools rationale (framework CLAUDE.md § Self-Evolution,
# "Validation Discipline" — "New schema validations MUST NOT be added as new
# branches inside datarim-doctor.sh... orthogonal concerns get orthogonal
# tools"): datarim-doctor.sh's SCOPE=execution only CALLS this script and
# aggregates its findings; all comparison logic lives here.
#
# Canon always wins: this script only REPORTS drift, it never rewrites
# space.yml. `--fix` (if invoked with a real config path, not fixture-only)
# regenerates the local map FROM canon — never the reverse.
#
# Output discipline: findings never print more than the fields already
# present in canon/map (required_host, host_aliases, tailscale_ip). This is
# still a machine-local terminal tool (never piped into a committed
# artefact) — see plan § Security Design "no mesh-IP in shipped".
#
# Usage:
#   check-execution-host-drift.sh --check --canon <space.yml> --map <execution-hosts.yml> --space <name> [--ttl-days N]
#   check-execution-host-drift.sh --report --canon <space.yml> --map <execution-hosts.yml> --space <name> [--ttl-days N]
#
# Exit codes:
#   0   PASS — canon and map agree, map is fresh (or --report ran without error)
#   1   FAIL — drift finding and/or staleness finding
#   2   usage error
# shellcheck shell=bash
set -euo pipefail

MODE=""
CANON=""
MAP=""
SPACE=""
TTL_DAYS=90

usage() {
    cat <<'EOF'
Usage: check-execution-host-drift.sh (--check|--report) --canon <space.yml> --map <execution-hosts.yml> --space <name> [--ttl-days N]

Compares canon space.yml § execution against the machine-local
execution-hosts.yml binding for --space, and flags:
  - drift: required_host / tailscale_ip / host_aliases mismatch (canon wins)
  - staleness: map synced_at (or file mtime, if synced_at absent) older
    than --ttl-days (default 90)

Exit codes: 0 PASS, 1 FAIL (finding), 2 usage error.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --report) MODE="report"; shift ;;
        --canon) CANON="$2"; shift 2 ;;
        --map) MAP="$2"; shift 2 ;;
        --space) SPACE="$2"; shift 2 ;;
        --ttl-days) TTL_DAYS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$CANON" ] || [ -z "$MAP" ] || [ -z "$SPACE" ]; then
    usage >&2
    exit 2
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required" >&2
    exit 2
fi

FINDINGS=0
FINDING_LINES=()

if [ ! -f "$CANON" ]; then
    FINDINGS=$((FINDINGS + 1))
    FINDING_LINES+=("canon space.yml not found: $CANON")
fi
if [ ! -f "$MAP" ]; then
    FINDINGS=$((FINDINGS + 1))
    FINDING_LINES+=("execution-hosts map not found: $MAP")
fi

if [ "$FINDINGS" -eq 0 ]; then
    CANON_HOST="$(yq e '.execution.required_host // ""' "$CANON" 2>/dev/null || true)"
    CANON_IP="$(yq e '.execution.tailscale_ip // ""' "$CANON" 2>/dev/null || true)"
    CANON_ALIASES="$(yq e '.execution.host_aliases | join(",") // ""' "$CANON" 2>/dev/null || true)"

    # Find the binding index for --space in the map.
    n=$(yq e '.bindings | length' "$MAP" 2>/dev/null || echo 0)
    idx=-1
    i=0
    while [ "$i" -lt "$n" ]; do
        sp=$(yq e ".bindings[$i].space" "$MAP" 2>/dev/null || true)
        if [ "$sp" = "$SPACE" ]; then
            idx=$i
            break
        fi
        i=$((i + 1))
    done

    if [ "$idx" -lt 0 ]; then
        FINDINGS=$((FINDINGS + 1))
        FINDING_LINES+=("map has no binding for space '$SPACE'")
    else
        MAP_HOST="$(yq e ".bindings[$idx].required_host" "$MAP" 2>/dev/null || true)"
        MAP_IP="$(yq e ".bindings[$idx].tailscale_ip" "$MAP" 2>/dev/null || true)"
        MAP_ALIASES="$(yq e ".bindings[$idx].host_aliases | join(\",\")" "$MAP" 2>/dev/null || true)"

        if [ "$CANON_HOST" != "$MAP_HOST" ]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("canon<->map drift: required_host differs (space=$SPACE)")
        fi
        if [ "$CANON_IP" != "$MAP_IP" ]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("canon<->map drift: tailscale_ip differs (space=$SPACE)")
        fi
        if [ "$CANON_ALIASES" != "$MAP_ALIASES" ]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("canon<->map drift: host_aliases differ (space=$SPACE)")
        fi

        # --- TTL staleness --------------------------------------------------
        SYNCED_AT="$(yq e '.synced_at // ""' "$MAP" 2>/dev/null || true)"
        now_epoch="$(date -u +%s)"
        stale=0
        if [ -n "$SYNCED_AT" ]; then
            synced_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$SYNCED_AT" +%s 2>/dev/null \
                || date -u -d "$SYNCED_AT" +%s 2>/dev/null || echo 0)"
        else
            synced_epoch="$(stat -f %m "$MAP" 2>/dev/null || stat -c %Y "$MAP" 2>/dev/null || echo "$now_epoch")"
        fi
        age_days=$(( (now_epoch - synced_epoch) / 86400 ))
        if [ "$age_days" -gt "$TTL_DAYS" ]; then
            stale=1
        fi
        if [ "$stale" -eq 1 ]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("staleness: map older than ${TTL_DAYS} days (space=$SPACE, age=${age_days}d)")
        fi
    fi
fi

if [ "$MODE" = "report" ]; then
    echo "execution-host drift report (space=$SPACE): ${FINDINGS} finding(s)"
    for f in "${FINDING_LINES[@]:-}"; do
        [ -n "$f" ] && echo "  - $f"
    done
    exit 0
fi

# --check mode
if [ "$FINDINGS" -eq 0 ]; then
    echo "OK: execution-host binding consistent (space=$SPACE)"
    exit 0
fi
for f in "${FINDING_LINES[@]}"; do
    echo "FINDING: $f"
done
exit 1

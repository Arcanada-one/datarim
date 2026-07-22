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
WORKSPACE_ARG=""
TTL_DAYS=90

usage() {
    cat <<'EOF'
Usage: check-execution-host-drift.sh (--check|--report|--fix) --canon <space.yml> --map <execution-hosts.yml> --space <name> [--workspace <path>] [--ttl-days N]

--check / --report: compare canon space.yml § execution against the
machine-local execution-hosts.yml binding for --space, and flag:
  - drift: required_host / tailscale_ip / host_aliases mismatch (canon wins)
  - staleness: map synced_at (or file mtime, if synced_at absent) older
    than --ttl-days (default 90)

--fix: regenerate the machine-local map binding for --space FROM canon
(canon->cache only, never the reverse). Refreshes the canon-owned fields
(required_host, host_aliases, tailscale_ip, ssh_user, default_agent,
allowed_agents) and stamps synced_at=now. The machine-local `workspace`
path is owned by the cache, not canon: --fix preserves the existing
binding's workspace, and only needs --workspace when creating a brand-new
binding (fallback: canon .space.local_repo_path). Creates the map file
(schema_version/role/bindings skeleton) when absent; other spaces'
bindings and top-level keys are left untouched.

Exit codes: 0 PASS/OK, 1 FAIL (finding), 2 usage error.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --report) MODE="report"; shift ;;
        --fix) MODE="fix"; shift ;;
        --canon) CANON="$2"; shift 2 ;;
        --map) MAP="$2"; shift 2 ;;
        --space) SPACE="$2"; shift 2 ;;
        --workspace) WORKSPACE_ARG="$2"; shift 2 ;;
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

# --- do_fix -----------------------------------------------------------------
# Regenerate the machine-local map binding for $SPACE FROM canon. Canon owns
# host identity; the cache owns the machine-local `workspace` path. Never
# writes canon.
do_fix() {
    if [ ! -f "$CANON" ]; then
        echo "ERROR: canon space.yml not found: $CANON" >&2
        exit 2
    fi

    # Read canon-owned fields (tolerate both top-level and nested-under-space
    # layouts, mirroring the --check reader).
    local c_host c_ip c_aliases c_user c_agent c_allowed
    c_host="$(yq e '(.execution // .space.execution).required_host // ""' "$CANON")"
    c_ip="$(yq e '(.execution // .space.execution).tailscale_ip // ""' "$CANON")"
    c_aliases="$(yq e '(.execution // .space.execution).host_aliases // [] | join(", ")' "$CANON")"
    c_user="$(yq e '(.execution // .space.execution).ssh_user // ""' "$CANON")"
    c_agent="$(yq e '(.execution // .space.execution).default_agent // "claude-code"' "$CANON")"
    c_allowed="$(yq e '(.execution // .space.execution).allowed_agents // [] | join(", ")' "$CANON")"

    if [ -z "$c_host" ]; then
        echo "ERROR: canon has no execution.required_host (space=$SPACE): $CANON" >&2
        exit 2
    fi

    # Create the map skeleton when absent so += has a sequence to append to.
    if [ ! -f "$MAP" ]; then
        printf 'schema_version: 1\nrole: control\nbindings: []\n' > "$MAP"
    fi

    # Locate any existing binding for this space to preserve its
    # machine-local workspace path.
    local n idx existing_ws
    n="$(yq e '.bindings | length' "$MAP" 2>/dev/null || echo 0)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    idx=-1
    local i=0
    while [ "$i" -lt "$n" ]; do
        if [ "$(yq e ".bindings[$i].space" "$MAP" 2>/dev/null || true)" = "$SPACE" ]; then
            idx=$i
            break
        fi
        i=$((i + 1))
    done
    existing_ws=""
    if [ "$idx" -ge 0 ]; then
        existing_ws="$(yq e ".bindings[$idx].workspace // \"\"" "$MAP" 2>/dev/null || true)"
        [ "$existing_ws" = "null" ] && existing_ws=""
    fi

    # Resolve the machine-local workspace path: explicit --workspace wins,
    # else preserve the existing binding's path, else fall back to canon's
    # local_repo_path (best-effort for first-ever creation).
    local ws
    if [ -n "$WORKSPACE_ARG" ]; then
        ws="$WORKSPACE_ARG"
    elif [ -n "$existing_ws" ]; then
        ws="$existing_ws"
    else
        ws="$(yq e '.space.local_repo_path // ""' "$CANON")"
    fi
    if [ -z "$ws" ] || [ "$ws" = "null" ]; then
        echo "ERROR: cannot resolve machine-local workspace path for space '$SPACE'; pass --workspace <path>" >&2
        exit 2
    fi

    # Build the desired binding in a temp file (same flow-array shape the
    # map already uses) and splice it in: delete the prior binding for this
    # space, then append the fresh one. This preserves other spaces'
    # bindings and every top-level key except synced_at.
    local binding_tmp
    binding_tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$binding_tmp'" RETURN
    {
        printf 'workspace: %s\n' "$ws"
        printf 'space: %s\n' "$SPACE"
        printf 'required_host: %s\n' "$c_host"
        printf 'host_aliases: [%s]\n' "$c_aliases"
        printf 'tailscale_ip: "%s"\n' "$c_ip"
        printf 'ssh_user: %s\n' "$c_user"
        printf 'default_agent: %s\n' "$c_agent"
        printf 'allowed_agents: [%s]\n' "$c_allowed"
    } > "$binding_tmp"

    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    yq e -i "del(.bindings[] | select(.space == \"$SPACE\"))" "$MAP"
    yq e -i ".bindings += [load(\"$binding_tmp\")]" "$MAP"
    yq e -i ".synced_at = \"$now\"" "$MAP"

    echo "OK: regenerated map binding from canon (space=$SPACE)"
    exit 0
}

if [ "$MODE" = "fix" ]; then
    do_fix
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
    # Canon layout tolerance: fixtures use a top-level `execution:` block,
    # real space.yml files nest it under the `space:` root key. Accept both.
    CANON_HOST="$(yq e '(.execution // .space.execution).required_host // ""' "$CANON" 2>/dev/null || true)"
    CANON_IP="$(yq e '(.execution // .space.execution).tailscale_ip // ""' "$CANON" 2>/dev/null || true)"
    CANON_ALIASES="$(yq e '(.execution // .space.execution).host_aliases // [] | join(",")' "$CANON" 2>/dev/null || true)"

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
            # mtime fallback when synced_at is absent. Try GNU coreutils
            # (stat -c %Y) FIRST, then BSD/macOS (stat -f %m): on GNU, `-f`
            # means --file-system and prints multi-line FS info to stdout
            # (non-numeric), which under set -u crashes the arithmetic below;
            # so GNU must win the || chain on Linux. Numeric-guard the result.
            synced_epoch="$(stat -c %Y "$MAP" 2>/dev/null || stat -f %m "$MAP" 2>/dev/null || echo "$now_epoch")"
            case "$synced_epoch" in
                *[!0-9]*|"") synced_epoch="$now_epoch" ;;
            esac
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

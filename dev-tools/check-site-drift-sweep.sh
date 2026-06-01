#!/usr/bin/env bash
# check-site-drift-sweep.sh — level-3 ecosystem-wide site-drift sweep.
#
# Runs the repo↔site drift detector once per registered product and, for every
# drifted product, emits ONE idempotent site-update backlog task (deduped by
# the drift-site-update-<product> anchor via the shared backlog-sink library).
# A fail-soft Ops Bot heartbeat summarises the run. Host-agnostic: ships with a
# systemd timer/service template under dev-tools/deploy/ for a future server
# move; on the Mac primary it is operator-installed via crontab.
#
# Usage:
#   check-site-drift-sweep.sh [--root <dir>] [--cadence-h N] [--force]
#                             [--dry-run] [--help]
#
# Exit codes:
#   0  sweep completed (clean OR drift emitted OR no file sink — all normal)
#   2  usage error
#   3  registry missing / unparseable (detector exit 3 propagated)
#
# Dependency floor: bash + awk + grep + curl (emit only) + jq (emit DTO only).
# The detector itself avoids jq; jq is required solely for the Ops Bot payload.
#
# Security (Mandate S1/S5/S9): registry product ids are untrusted — each is
# allowlisted ^[a-z][a-z0-9-]*$ before reaching the detector or the backlog.
# OPSBOT_KEY is never exposed to `set -x`; the egress host is an HTTPS-pinned
# constant. Tier 0: outbound-only, no listener, no DB.
#
# Idempotency / anti-flap: open-task dedup (the backlog anchor) is the complete
# contract. There is no post-close cooldown — the drift signal is sticky (only
# an operator fix clears it), so it cannot flap. A product whose task was closed
# while still drifting re-spawns exactly one task on the next daily run; that is
# a true positive (premature close or regression), not noise.

set -uo pipefail

SCRIPT_NAME="check-site-drift-sweep.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""
CADENCE_H=24
FORCE=0
DRY_RUN=0

# Detector + library locations (overridable for tests).
DETECTOR="${DRIFT_SWEEP_DETECTOR:-$SCRIPT_DIR/check-repo-site-sync.sh}"
SINK_LIB="${DRIFT_SWEEP_SINK_LIB:-$SCRIPT_DIR/lib/backlog-sink.sh}"

# Ops Bot egress — HTTPS-pinned constant host (never interpolated from input).
OPS_BOT_URL="${DRIFT_SWEEP_OPS_BOT_URL:-https://ops.arcanada.one/events}"

REGISTRY_REL="documentation/ecosystem-sync/registry.yml"

print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--root <dir>] [--cadence-h N] [--force] [--dry-run] [--help]

  --root <dir>     KB root (default: walk up from cwd to find $REGISTRY_REL)
  --cadence-h N    minimum hours between real runs (default 24, stamp-guarded)
  --force          ignore the cadence stamp and run now
  --dry-run        detect + report, but never write the backlog or emit
  --help           this message

Exit: 0 swept | 2 usage error | 3 registry missing/unparseable
EOF
}

# ---- arg parse ----
while [ $# -gt 0 ]; do
    case "$1" in
        --root)      ROOT="$2"; shift 2 ;;
        --cadence-h) CADENCE_H="$2"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --dry-run)   DRY_RUN=1; shift ;;
        --help)      print_usage; exit 0 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; print_usage >&2; exit 2 ;;
    esac
done

# ---- stamp guard (write unconditionally at entry per sre digest) ----
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/datarim"
STAMP="$STATE_DIR/drift-sweep.last-run"
mkdir -p "$STATE_DIR" 2>/dev/null || true

now_epoch="$(date +%s 2>/dev/null || echo 0)"

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
    last="$(cat "$STAMP" 2>/dev/null)"
    case "$last" in (''|*[!0-9]*) last=0 ;; esac
    age=$(( now_epoch - last ))
    window=$(( CADENCE_H * 3600 ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$window" ]; then
        echo "INFO: within cadence window (${age}s < ${window}s); skipping. Use --force to override." >&2
        exit 0
    fi
fi
# Write the run stamp unconditionally now (dead-man / anti-flap heartbeat).
printf '%s\n' "$now_epoch" > "$STAMP" 2>/dev/null || true

# ---- resolve KB root + registry ----
if [ -z "$ROOT" ]; then
    d="$PWD"
    while [ "$d" != "/" ]; do
        [ -f "$d/$REGISTRY_REL" ] && { ROOT="$d"; break; }
        d="$(dirname "$d")"
    done
fi
REGISTRY="$ROOT/$REGISTRY_REL"
if [ -z "$ROOT" ] || [ ! -f "$REGISTRY" ]; then
    echo "ERROR: registry not found ($REGISTRY_REL)" >&2
    exit 3
fi

# ---- source the shared backlog-sink library ----
# shellcheck source=dev-tools/lib/backlog-sink.sh
if [ -f "$SINK_LIB" ]; then
    . "$SINK_LIB"
else
    echo "ERROR: backlog-sink library not found ($SINK_LIB)" >&2
    exit 2
fi

# ---- enumerate registry product ids (allowlisted) ----
# Reuse the detector's two-space-indent product contract; reject any id that
# fails ^[a-z][a-z0-9-]*$ (security: no traversal / regex-meta into backlog).
enumerate_products() {
    awk '
        BEGIN { in_products=0 }
        /^[[:space:]]*#/ { next }
        /^products:[[:space:]]*$/ { in_products=1; next }
        in_products==0 { next }
        /^  [A-Za-z0-9_.\/-]+:[[:space:]]*$/ {
            line=$0; sub(/:[[:space:]]*$/,"",line); sub(/^  /,"",line); print line
        }
    ' "$REGISTRY" | grep -E '^[a-z][a-z0-9-]*$' || true
}

# ---- Ops Bot fail-soft emit (adapted from preflight-check.sh emit_ops_bot) ----
emit_ops_bot() {  # $1=category(info|warning|fatal) $2=title $3=body
    local category="$1" title="$2" body="$3"
    local key="${OPSBOT_KEY:-}"
    if [ -z "$key" ]; then
        echo "WARN: OPSBOT_KEY unset; skipping Ops Bot emit (fail-soft)" >&2
        return 0
    fi
    command -v jq >/dev/null 2>&1 || { echo "WARN: jq absent; skipping Ops Bot emit" >&2; return 0; }
    local payload
    payload="$(jq -cn \
        --arg agent "dr-drift-sweep" \
        --arg title "$title" \
        --arg body  "$body" \
        --arg cat   "$category" \
        '{agent:$agent, title:$title, body:$body, category:$cat}')"
    # NB: never `set -x` around this curl — OPSBOT_KEY would leak.
    local resp_file http_code
    resp_file="$(mktemp -t drift-opsbot.XXXXXX 2>/dev/null || echo "/tmp/drift-opsbot.$$")"
    http_code="$(curl -sS -X POST "$OPS_BOT_URL" \
        -H "Authorization: Bearer ${key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        -d "$payload" \
        --output "$resp_file" \
        --write-out '%{http_code}' 2>/dev/null || echo "000")"
    if ! printf '%s' "$http_code" | grep -Eq '^2[0-9]{2}$'; then
        echo "WARN: Ops Bot emit failed (HTTP ${http_code}); not blocking sweep" >&2
    fi
    rm -f "$resp_file"
}

# ---- resolve sink (caller no-ops if no file sink) ----
BACKLOG=""
if BACKLOG="$(resolve_backlog_sink --root "$ROOT")"; then
    :
else
    echo "INFO: no file backlog sink resolved (future non-file backend or consumer machine); skipping append. Zero writes." >&2
    BACKLOG=""
fi

# ---- per-product sweep ----
n_checked=0; n_drift=0; n_emitted=0; n_suppressed=0; n_skipped=0
fatal=0

for prod in $(enumerate_products); do
    n_checked=$((n_checked+1))
    rc=0
    "$DETECTOR" --check --product "$prod" --root "$ROOT" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) : ;;                                   # clean
        1)                                        # drift
            n_drift=$((n_drift+1))
            if [ "$DRY_RUN" -eq 1 ] || [ -z "$BACKLOG" ]; then
                n_suppressed=$((n_suppressed+1))
                continue
            fi
            # Detail kept terse + single-line (injection gate enforced in lib).
            sev="MEDIUM"
            already=0
            [ -f "$BACKLOG" ] && grep -qF "drift-site-update-$prod" -- "$BACKLOG" && already=1
            if append_site_update_task "$BACKLOG" "$prod" "$sev" "repo↔site drift detected by sweep"; then
                if [ "$already" -eq 0 ]; then
                    n_emitted=$((n_emitted+1))
                    # state-change only alert
                    emit_ops_bot warning "Site drift: $prod" "New site-update task spawned for $prod (repo↔site drift)."
                else
                    n_suppressed=$((n_suppressed+1))
                fi
            else
                n_suppressed=$((n_suppressed+1))
            fi
            ;;
        3)                                        # registry missing/unparseable
            fatal=1
            echo "ERROR: detector reported registry failure (exit 3) for '$prod'" >&2
            emit_ops_bot fatal "Drift sweep fatal" "Detector exit 3 (registry missing/unparseable) at product $prod."
            break
            ;;
        *)                                        # SKIP / source-unavailable / other
            n_skipped=$((n_skipped+1))
            ;;
    esac
done

# ---- heartbeat (one info message per run) ----
hb="checked=$n_checked drifted=$n_drift emitted=$n_emitted suppressed=$n_suppressed skipped=$n_skipped"
echo "INFO: drift-sweep $hb" >&2
emit_ops_bot info "Drift sweep heartbeat" "$hb"

[ "$fatal" -eq 1 ] && exit 3
exit 0

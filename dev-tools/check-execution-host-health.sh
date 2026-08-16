#!/usr/bin/env bash
# check-execution-host-health.sh — answer "is this machine actually gated?"
#
# Why this exists. `eh_decision` returns 0 for BOTH «this host is the declared
# one» and «this workspace has no mandate», so an absent guard and a healthy
# guard are indistinguishable by exit code: both are silence. A machine with no
# protection at all reads as healthy. That is not hypothetical — it is how a
# real outage stayed invisible while a second machine, mis-wired the other way,
# denied every task on its own declared execution host.
#
# So this script never infers health from silence. It runs the resolver twice:
#
#   POSITIVE control — as the real current host: must resolve on-host.
#   NEGATIVE control — under a hostname that cannot possibly match: must
#                      resolve off-host.
#
# A control that has never been observed denying has not been observed at all.
# Both must hold, or the machine is not gated. Reading EH_STATE (rather than
# the exit code) is what makes "unconfigured" visible instead of silent.
#
# This reports on the RESOLVER, which is what the framework ships. Whether a
# PreToolUse hook is installed is site policy (CLAUDE.md § S10-bis); a site that
# wires one should assert its deny path separately, in its own test suite.
#
# Usage:
#   check-execution-host-health.sh [--check|--report] [--root <path>] [--map <path>]
#
# Exit codes:
#   0  gated and correct (both controls pass), or genuinely unconfigured
#      (no mandate anywhere — reported explicitly, never as silence)
#   1  MIS-GATED: a mandate exists but the controls disagree with it
#   2  usage or environment error (fail-closed: never read as healthy)
# shellcheck shell=bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SELF_DIR/lib/execution-host.sh"
DEFAULT_MAP="${HOME}/.claude/local/config/execution-hosts.yml"

MODE="check"
ROOT=""
MAP_PATH="${DATARIM_EXEC_HOSTS_MAP:-$DEFAULT_MAP}"

usage() {
    cat <<'EOF'
Usage: check-execution-host-health.sh [--check|--report] [--root <path>] [--map <path>]

Proves whether this machine is actually gated for a workspace, using a
positive control (current host must resolve on-host) AND a negative control
(a foreign hostname must resolve off-host). Silence is never read as health.

  --check   one-line verdict (default)
  --report  per-control detail
  --root    workspace root (default: walk up from $PWD)
  --map     machine-local routing map (default: ~/.claude/local/config/execution-hosts.yml)

Exit: 0 gated-and-correct or genuinely-unconfigured, 1 mis-gated, 2 usage/env error.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --report) MODE="report"; shift ;;
        --root) ROOT="${2:-}"; shift 2 ;;
        --map) MAP_PATH="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ ! -f "$LIB" ]; then
    echo "ERROR: resolver library not found: $LIB" >&2
    exit 2
fi
# shellcheck source=/dev/null
source "$LIB" || { echo "ERROR: cannot source resolver library: $LIB" >&2; exit 2; }

if [ -z "$ROOT" ]; then
    ROOT="$(eh_resolve_workspace_root "$PWD" 2>/dev/null || true)"
fi
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "ERROR: no datarim workspace root resolved (pass --root)" >&2
    exit 2
fi

# --- POSITIVE control: the real current host --------------------------------
EH_STATE="unset"
eh_decision "$ROOT" "$MAP_PATH" >/dev/null 2>&1 || true
positive_state="$EH_STATE"

# --- NEGATIVE control: a hostname that cannot match any real binding --------
# A control that never denies proves nothing, so we force the deny path.
EH_STATE="unset"
EH_TEST_HOSTNAME="eh-health-probe-not-a-real-host.invalid" \
    eh_decision "$ROOT" "$MAP_PATH" >/dev/null 2>&1 || true
negative_state="$EH_STATE"

emit_report() {
    printf 'execution-host health (root=%s)\n' "$ROOT"
    printf '  positive control (this host)    : EH_STATE=%s\n' "$positive_state"
    printf '  negative control (foreign host) : EH_STATE=%s\n' "$negative_state"
}

[ "$MODE" = "report" ] && emit_report

# --- verdict ----------------------------------------------------------------
# Genuinely unconfigured: BOTH controls agree there is no binding. Reported
# out loud, because "no mandate here" and "gate broken" must never look alike.
if [ "$positive_state" = "unconfigured" ] && [ "$negative_state" = "unconfigured" ]; then
    echo "UNCONFIGURED: no execution-host binding for this workspace — this machine is NOT gated (by design, no mandate found)."
    exit 0
fi

if [ "$positive_state" = "on-host" ] && [ "$negative_state" = "off-host" ]; then
    echo "OK: gated — this host resolves on-host, a foreign host is denied."
    exit 0
fi

if [ "$positive_state" = "off-host" ] && [ "$negative_state" = "off-host" ]; then
    echo "OK: gated — a binding exists and resolves elsewhere; this machine is correctly off-host."
    exit 0
fi

# Everything else is a real defect, including the case that hid the outage:
# a mandate that resolves as `unconfigured` on one side only.
echo "MIS-GATED: controls disagree (positive=$positive_state, negative=$negative_state) — a binding exists but does not resolve consistently. This machine cannot prove it is gated." >&2
[ "$MODE" = "report" ] || emit_report >&2
exit 1

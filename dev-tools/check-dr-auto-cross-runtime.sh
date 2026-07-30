#!/usr/bin/env bash
# check-dr-auto-cross-runtime.sh — /dr-auto cross-runtime activation smoke.
#
# Validates that the /dr-auto autonomous-mode activation contract is
# runtime-agnostic: it holds for Codex CLI and Cursor exactly as it does for
# Claude Code, because it rests on pure-bash primitives (a marker file + an
# explicit subagent auto-signal) rather than any Claude-Code-only hook.
#
# The three checks mirror the three properties an operator must confirm when
# dogfooding /dr-auto on a non-Claude runtime (backlog TUNE-0292):
#
#   1. Activation — `auto-mode-marker.sh reassert` writes a parseable marker
#      whose effective path is reported by `auto-mode-marker.sh resolve`. The
#      Question Suppression Ladder engages off this marker, not off the runtime
#      identity, so the write+resolve round-trip must work on a bare shell.
#   2. Env-var independence — `subagent-active` returns "active" for a matching
#      task + auto-signal true and "non-auto" for auto-signal false, WITH
#      DATARIM_AUTO_MODE unset. A spawned Codex/Cursor subagent does not inherit
#      the shell env var, so the marker + prompt-signal path must stand alone.
#   3. Hard-gate escalation data — dev-tools/rules/fb-rules.yaml declares a
#      non-empty hard_gated_actions list. Hard-gated actions never auto-execute
#      on any runtime; the data driving that escalation must be present.
#
# This preflight is itself pure bash: run it from a Codex CLI or Cursor shell
# (same script, same result) before the interactive full-cycle smoke described
# in documentation/how-to/multi-runtime.md § Cross-runtime /dr-auto smoke.
#
# Modes:
#   --check    exit 0 = all properties hold, 1 = one or more failed (default)
#   --report   human-readable per-check detail (implies --check)
#   --help     usage
#
# Exit codes: 0 = PASS · 1 = FAIL · 2 = usage/precondition/internal error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_TOOL="$SCRIPT_DIR/auto-mode-marker.sh"
FB_RULES="$SCRIPT_DIR/rules/fb-rules.yaml"
# Any well-formed task-id (^[A-Z]{2,10}-[0-9]{4}$) works; the smoke uses a
# reserved sentinel so it never collides with a real task's marker.
SMOKE_TASK_ID="TUNE-0000"

REPORT=0

usage() {
    cat <<'EOF'
Usage: check-dr-auto-cross-runtime.sh [--check|--report|--help]

Cross-runtime activation smoke for /dr-auto. Exits 0 when the autonomous-mode
activation contract holds on the current shell runtime (Claude Code / Codex CLI
/ Cursor), 1 when any property fails.
EOF
}

case "${1:---check}" in
    --check) ;;
    --report) REPORT=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: ${1}" >&2; usage >&2; exit 2 ;;
esac

log() { [ "$REPORT" -eq 1 ] && echo "$@"; return 0; }

fail=0
note_fail() { fail=1; echo "FAIL: $1" >&2; }

# Preconditions — the runtime-agnostic primitives must be present.
[ -f "$MARKER_TOOL" ] || { echo "ERROR: missing $MARKER_TOOL (auto-mode-marker.sh)" >&2; exit 2; }
[ -f "$FB_RULES" ]    || { echo "ERROR: missing $FB_RULES (fb-rules.yaml)" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/datarim"

# ── Check 1: activation marker ────────────────────────────────────────────────
# reassert writes the per-task marker; resolve reports its effective path (this
# indirection is what keeps the smoke robust to the marker's on-disk layout).
marker_ok=0
if bash "$MARKER_TOOL" reassert --root "$WORK" --task-id "$SMOKE_TASK_ID" >/dev/null 2>&1; then
    mpath="$(bash "$MARKER_TOOL" resolve --root "$WORK" --task-id "$SMOKE_TASK_ID" 2>/dev/null || true)"
    if [ -n "$mpath" ] && [ -f "$mpath" ] \
        && grep -q "^task_id:[[:space:]]*${SMOKE_TASK_ID}$" "$mpath" 2>/dev/null; then
        marker_ok=1
    fi
fi
if [ "$marker_ok" -eq 1 ]; then
    log "check 1 (activation marker) ...... PASS"
else
    note_fail "check 1: reassert/resolve did not yield a parseable marker for ${SMOKE_TASK_ID}"
fi

# ── Check 2: env-var-independent subagent activation ─────────────────────────
active_dec="$(env -u DATARIM_AUTO_MODE bash "$MARKER_TOOL" subagent-active \
    --root "$WORK" --task-id "$SMOKE_TASK_ID" --auto-signal true 2>/dev/null || true)"
nonauto_dec="$(env -u DATARIM_AUTO_MODE bash "$MARKER_TOOL" subagent-active \
    --root "$WORK" --task-id "$SMOKE_TASK_ID" --auto-signal false 2>/dev/null || true)"
if [ "$active_dec" = "active" ] && [ "$nonauto_dec" = "non-auto" ]; then
    log "check 2 (env-var independence) ... PASS (active/non-auto without DATARIM_AUTO_MODE)"
else
    note_fail "check 2: subagent-active gave '${active_dec}'/'${nonauto_dec}', expected 'active'/'non-auto'"
fi

# ── Check 3: hard-gate escalation data present ───────────────────────────────
# Count the `- <action>` entries under the hard_gated_actions: key without
# depending on yq (the smoke must run on any bare shell).
gate_count="$(awk '
    /^hard_gated_actions:[[:space:]]*$/ { in_block=1; next }
    in_block && /^[[:space:]]*-[[:space:]]+[a-z]/ { n++; next }
    in_block && /^[^[:space:]-]/ { in_block=0 }
    END { print n+0 }
' "$FB_RULES")"
if [ "$gate_count" -ge 1 ]; then
    log "check 3 (hard-gate data) ......... PASS (${gate_count} hard-gated actions)"
else
    note_fail "check 3: hard_gated_actions list is empty in $(basename "$FB_RULES")"
fi

if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAIL — /dr-auto activation contract is not runtime-portable on this shell" >&2
    exit 1
fi
log "RESULT: PASS — /dr-auto activation contract holds runtime-agnostically"
[ "$REPORT" -eq 0 ] && echo "PASS"
exit 0

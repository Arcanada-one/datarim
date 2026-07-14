#!/usr/bin/env bats

# Test contract: dev-tools/auto-mode-marker.sh per-task marker + dispatch-nonce
# binding (collision-safe autonomous-mode signal for delegated execution).
#
# Covers PRD-TUNE-0490 Phase-1 V-AC:
#   V-AC-1  autonomous path: valid nonce+session => subagent-active prints active
#   V-AC-2  fail-safe default: no marker => non-auto
#   V-AC-S2 forgery/replay rejected: wrong nonce / wrong session / stale / wrong id
#   collision-safety: two per-task markers coexist, each validates only its own id
#   resolve: prints per-task path when present, legacy path otherwise
#   back-compat: legacy single file honoured when per-task absent (no-nonce path)

HELPER="$BATS_TEST_DIRNAME/../dev-tools/auto-mode-marker.sh"

setup() {
    [ -x "$HELPER" ] || skip "auto-mode-marker.sh not executable: $HELPER"
    ROOT="$BATS_TEST_TMPDIR/ws"
    mkdir -p "$ROOT/datarim"
    ID="FAKE-9001"
    ID2="FAKE-9002"
    NONCE="abcdef0123456789"
    SESS="dr-arcanada-FAKE-9001"
    PT="$ROOT/datarim/.auto/${ID}.mode"
    LEGACY="$ROOT/datarim/.auto-mode-active"
}

# ── V-AC-1: autonomous path — valid nonce + session => active ──────────────────
@test "V-AC-1 valid nonce+session subagent-active => active" {
    run "$HELPER" reassert --root "$ROOT" --task-id "$ID" --space arcanada \
        --nonce "$NONCE" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ -f "$PT" ]
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "$NONCE" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ "$output" = "active" ]
}

# ── V-AC-2: fail-safe default — no marker => non-auto ──────────────────────────
@test "V-AC-2 no marker => non-auto (fail-safe)" {
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "$NONCE" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ── V-AC-S2a: wrong nonce => non-auto (replay/forgery reject) ──────────────────
@test "V-AC-S2a wrong nonce => non-auto" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID" --space arcanada \
        --nonce "$NONCE" --dispatch-session "$SESS"
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "ffffffffffffffff" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ── V-AC-S2b: wrong dispatch-session => non-auto ───────────────────────────────
@test "V-AC-S2b wrong dispatch-session => non-auto" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID" --space arcanada \
        --nonce "$NONCE" --dispatch-session "$SESS"
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "$NONCE" --dispatch-session "dr-arcanada-FAKE-9099"
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ── V-AC-S2c: stale marker (mtime > 24h) => non-auto ───────────────────────────
@test "V-AC-S2c stale marker (>24h) => non-auto" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID" --space arcanada \
        --nonce "$NONCE" --dispatch-session "$SESS"
    # Backdate the marker 25 hours (GNU touch -d, BSD touch -t fallback).
    old_epoch=$(( $(date +%s) - 90000 ))
    if ! touch -d "@${old_epoch}" "$PT" 2>/dev/null; then
        touch -t "$(date -r "$old_epoch" +%Y%m%d%H%M.%S 2>/dev/null)" "$PT" 2>/dev/null || skip "cannot backdate mtime portably"
    fi
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "$NONCE" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ── V-AC-S2d: marker for a different task-id => non-auto for this id ────────────
@test "V-AC-S2d marker for different task => non-auto" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID2" --space arcanada \
        --nonce "$NONCE" --dispatch-session "dr-arcanada-FAKE-9002"
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true \
        --nonce "$NONCE" --dispatch-session "$SESS"
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ── collision-safety: two per-task markers coexist independently ───────────────
@test "collision two per-task markers coexist, each validates only its own id" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID"  --space arcanada
    "$HELPER" reassert --root "$ROOT" --task-id "$ID2" --space arcanada
    [ -f "$ROOT/datarim/.auto/${ID}.mode" ]
    [ -f "$ROOT/datarim/.auto/${ID2}.mode" ]
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true
    [ "$output" = "active" ]
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID2" --auto-signal true
    [ "$output" = "active" ]
}

# ── resolve: per-task path when present ────────────────────────────────────────
@test "resolve prints per-task path when present" {
    "$HELPER" reassert --root "$ROOT" --task-id "$ID" --space arcanada
    run "$HELPER" resolve --root "$ROOT" --task-id "$ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$PT" ]
}

# ── resolve: legacy path when per-task absent ──────────────────────────────────
@test "resolve prints legacy path when per-task absent" {
    run "$HELPER" resolve --root "$ROOT" --task-id "$ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$LEGACY" ]
}

# ── back-compat: legacy single file honoured (no-nonce hand-run path) ──────────
@test "back-compat legacy single file => active when per-task absent" {
    cat > "$LEGACY" <<YAML
task_id: ${ID}
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
activated_by: /dr-auto
mode: resume
YAML
    run "$HELPER" subagent-active --root "$ROOT" --task-id "$ID" --auto-signal true
    [ "$status" -eq 0 ]
    [ "$output" = "active" ]
}

# ── input validation: malformed nonce rejected (exit 2) ────────────────────────
@test "malformed nonce => usage error exit 2" {
    run "$HELPER" reassert --root "$ROOT" --task-id "$ID" --nonce "NOT-HEX!!"
    [ "$status" -eq 2 ]
}

#!/usr/bin/env bats

# Test contract: dev-tools/classify-pane.sh + dev-tools/dispatch-digest.sh
# (PRD-TUNE-0490 Phase 2 monitoring layer).
#
# classify-pane covers V-AC-4 (no false-DONE) and the safety invariants:
#   - awaiting_operator ALWAYS wins (never reaped)
#   - live child ALWAYS blocks DEAD-ORPHAN (STALLED, not reaped)
#   - DEAD-ORPHAN only after >= 2 consecutive stale probes
# dispatch-digest covers aggregation + the SYNC STALE degrade (never false-DONE).

CP="$BATS_TEST_DIRNAME/../dev-tools/classify-pane.sh"
DG="$BATS_TEST_DIRNAME/../dev-tools/dispatch-digest.sh"
LIB="$BATS_TEST_DIRNAME/../dev-tools/lib/heartbeat-status.sh"

setup() {
    [ -f "$CP" ] || skip "classify-pane.sh not found"
    ROOT="$BATS_TEST_TMPDIR/ws"
    mkdir -p "$ROOT/datarim"
    NOW=1800000000
    BARE="$BATS_TEST_TMPDIR/bare.txt"
    printf 'dev@host:~/arcanada$ ' > "$BARE"
    ACTIVE="$BATS_TEST_TMPDIR/active.txt"
    printf '● Working (2m 14s • esc to interrupt)\n  reading files...\n' > "$ACTIVE"
}

w() { bash "$LIB" write --root "$ROOT" --now "$NOW" "$@" >/dev/null; }
c() { bash "$CP" --root "$ROOT" --now "$NOW" "$@"; }

# ── V-AC-4: no false-DONE ──────────────────────────────────────────────────────
@test "V-AC-4a state=done + bare prompt => DONE" {
    w --task-id ARCA-0001 --state done
    run c --task-id ARCA-0001 --pane-file "$BARE" --stale-count 3
    [ "$output" = "DONE" ]
}

@test "V-AC-4b in_progress + stale + no child + bare + >=2 probes => DEAD-ORPHAN" {
    w --task-id ARCA-0002 --state in_progress --now $((NOW-5000))
    run c --task-id ARCA-0002 --pane-file "$BARE" --has-child 0 --stale-count 3
    [ "$output" = "DEAD-ORPHAN" ]
}

@test "V-AC-4b guard: same but only 1 stale probe => HOLD (never single-probe reap)" {
    w --task-id ARCA-0002 --state in_progress --now $((NOW-5000))
    run c --task-id ARCA-0002 --pane-file "$BARE" --has-child 0 --stale-count 1
    [ "$output" = "HOLD" ]
}

# ── safety invariant: awaiting_operator always wins ────────────────────────────
@test "awaiting_operator + bare + many stale probes => AWAITING (never reaped)" {
    w --task-id ARCA-0003 --state awaiting_operator --question-id g --question-text q --option A --option B
    run c --task-id ARCA-0003 --pane-file "$BARE" --has-child 0 --stale-count 9
    [ "$output" = "AWAITING" ]
}

# ── safety invariant: live child blocks reap ───────────────────────────────────
@test "stale heartbeat + LIVE child => STALLED (escalate, never reap)" {
    w --task-id ARCA-0004 --state in_progress --now $((NOW-5000))
    run c --task-id ARCA-0004 --pane-file "$BARE" --has-child 1 --stale-count 9
    [ "$output" = "STALLED" ]
}

@test "fresh heartbeat + live child => RUNNING" {
    w --task-id ARCA-0005 --state in_progress
    run c --task-id ARCA-0005 --pane-file "$ACTIVE" --has-child 1
    [ "$output" = "RUNNING" ]
}

@test "fresh in_progress + active pane + no child yet => RUNNING (slow child detection)" {
    w --task-id ARCA-0006 --state in_progress
    run c --task-id ARCA-0006 --pane-file "$ACTIVE" --has-child 0
    [ "$output" = "RUNNING" ]
}

@test "no status at all + bare + >=2 probes => DEAD-ORPHAN" {
    run c --task-id ARCA-9999 --pane-file "$BARE" --has-child 0 --stale-count 2
    [ "$output" = "DEAD-ORPHAN" ]
}

@test "no status + bare + 1 probe => HOLD" {
    run c --task-id ARCA-9999 --pane-file "$BARE" --has-child 0 --stale-count 1
    [ "$output" = "HOLD" ]
}

# ── dispatch-digest ────────────────────────────────────────────────────────────
@test "digest: empty runtime reports no active tasks" {
    run bash "$DG" --root "$ROOT" --now "$NOW"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no active delegated tasks"* ]]
}

@test "digest: mixed set pins awaiting_operator first" {
    w --task-id ARCA-0001 --state done --stage archive
    w --task-id ARCA-0003 --state awaiting_operator --stage qa --question-id g --question-text q --option A
    run bash "$DG" --root "$ROOT" --now "$NOW"
    [ "$status" -eq 0 ]
    # first task line (after header) must be the awaiting_operator one
    first_task_line="$(printf '%s\n' "$output" | sed -n '2p')"
    [[ "$first_task_line" == *"ARCA-0003"* ]]
    [[ "$first_task_line" == *"awaiting_operator"* ]]
}

@test "digest: SYNC STALE flagged when freshest write older than sync-stale" {
    w --task-id ARCA-0001 --state in_progress
    run bash "$DG" --root "$ROOT" --now $((NOW+9000)) --sync-stale 1800
    [[ "$output" == *"SYNC STALE"* ]]
}

@test "digest: fresh writes do NOT get SYNC STALE" {
    w --task-id ARCA-0001 --state in_progress
    run bash "$DG" --root "$ROOT" --now "$NOW" --sync-stale 1800
    [[ "$output" != *"SYNC STALE"* ]]
}

@test "digest: JSON mode is valid JSON with per-task entries" {
    w --task-id ARCA-0001 --state done
    w --task-id ARCA-0002 --state in_progress
    if command -v jq >/dev/null 2>&1; then
        run bash -c "bash '$DG' --root '$ROOT' --now '$NOW' --json | jq -r '.count'"
        [ "$output" = "2" ]
    fi
}

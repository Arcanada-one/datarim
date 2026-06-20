#!/usr/bin/env bats

# Test contract: dev-tools/auto-mode-marker.sh implements marker re-assert and
# subagent activation logic per skills/autonomous-mode/SKILL.md § When this skill
# is active (Spawned subagents — relaxed activation).
#
# Verbs tested:
#   reassert   --root <DIR> --task-id <ID>
#   subagent-active --root <DIR> --task-id <ID> --auto-signal <true|false>
#
# Tests:
#   1. reassert restores a vanished marker
#   2. reassert is idempotent on a valid marker
#   3. subagent activates without env-var (env DATARIM_AUTO_MODE unset)
#   4. fail-safe preserved on true mismatch (no marker + no auto-signal)
#   5. subagent non-auto when marker holds a different task_id
#   6. subagent non-auto with a valid marker but auto-signal=false
#      (pins the auto-signal requirement against regression)

HELPER="$BATS_TEST_DIRNAME/../dev-tools/auto-mode-marker.sh"

setup() {
    [ -x "$HELPER" ] || skip "auto-mode-marker.sh not executable: $HELPER"
    # Create a temporary fake workspace with a datarim/ subdir
    FAKE_ROOT="$BATS_TEST_TMPDIR/fake-workspace"
    mkdir -p "$FAKE_ROOT/datarim"
    MARKER="$FAKE_ROOT/datarim/.auto-mode-active"
    TASK_ID="FAKE-9001"
}

# Helper: write a valid marker for the given task-id
_seed_marker() {
    local task_id="${1:-FAKE-9001}"
    cat > "$MARKER" <<YAML
task_id: ${task_id}
activated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
activated_by: /dr-auto
mode: resume
YAML
}

# ─────────────────────────────────────────────────────────────────
# Test 1: reassert restores a vanished marker
# ─────────────────────────────────────────────────────────────────
@test "reassert restores a vanished marker" {
    # Precondition: no marker exists
    [ ! -f "$MARKER" ]

    run "$HELPER" reassert --root "$FAKE_ROOT" --task-id "$TASK_ID"
    [ "$status" -eq 0 ]

    # Marker must now exist
    [ -f "$MARKER" ]

    # task_id must match
    run grep -q "task_id: ${TASK_ID}" "$MARKER"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────
# Test 2: reassert is idempotent on a valid marker
# ─────────────────────────────────────────────────────────────────
@test "reassert is idempotent on a valid marker" {
    _seed_marker "$TASK_ID"
    local before
    before=$(cat "$MARKER")

    # Run reassert on the already-valid marker
    run "$HELPER" reassert --root "$FAKE_ROOT" --task-id "$TASK_ID"
    [ "$status" -eq 0 ]

    # File must still exist and still hold the same task_id
    [ -f "$MARKER" ]
    run grep -q "task_id: ${TASK_ID}" "$MARKER"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────
# Test 3: subagent activates without env-var
# Env DATARIM_AUTO_MODE is explicitly unset; valid marker + auto-signal=true
# ─────────────────────────────────────────────────────────────────
@test "subagent activates without env-var" {
    _seed_marker "$TASK_ID"

    # Ensure DATARIM_AUTO_MODE is not inherited
    run env -u DATARIM_AUTO_MODE \
        "$HELPER" subagent-active --root "$FAKE_ROOT" --task-id "$TASK_ID" --auto-signal true
    [ "$status" -eq 0 ]
    [ "$output" = "active" ]
}

# ─────────────────────────────────────────────────────────────────
# Test 4: fail-safe preserved on true mismatch (no marker, no auto-signal)
# ─────────────────────────────────────────────────────────────────
@test "fail-safe preserved on true mismatch — no marker and no auto-signal" {
    # Precondition: no marker exists
    [ ! -f "$MARKER" ]

    run "$HELPER" subagent-active --root "$FAKE_ROOT" --task-id "$TASK_ID" --auto-signal false
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ─────────────────────────────────────────────────────────────────
# Test 5: subagent non-auto when marker holds a different task_id
# ─────────────────────────────────────────────────────────────────
@test "subagent non-auto when marker holds a different task_id" {
    # Seed a marker for a DIFFERENT task
    _seed_marker "FAKE-9099"

    run "$HELPER" subagent-active --root "$FAKE_ROOT" --task-id "$TASK_ID" --auto-signal true
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

# ─────────────────────────────────────────────────────────────────
# Test 6: subagent non-auto with a valid marker but auto-signal=false
# A valid marker alone MUST NOT activate a subagent — the explicit
# prompt auto-signal is a required condition. Pins the auto-signal
# requirement so a future regression that drops it is caught.
# ─────────────────────────────────────────────────────────────────
@test "subagent non-auto with valid marker but auto-signal false" {
    _seed_marker "$TASK_ID"

    run "$HELPER" subagent-active --root "$FAKE_ROOT" --task-id "$TASK_ID" --auto-signal false
    [ "$status" -eq 0 ]
    [ "$output" = "non-auto" ]
}

@test "reassert writes the resolved space binding" {
    run "$HELPER" reassert --root "$FAKE_ROOT" --task-id "$TASK_ID" --space arcanada
    [ "$status" -eq 0 ]
    [ "$(yq eval -r '.space' "$MARKER")" = arcanada ]
}

@test "reassert replaces a marker with the wrong space binding" {
    _seed_marker "$TASK_ID"
    printf 'space: aether\n' >> "$MARKER"
    run "$HELPER" reassert --root "$FAKE_ROOT" --task-id "$TASK_ID" --space arcanada
    [ "$status" -eq 0 ]
    [ "$(yq eval -r '.space' "$MARKER")" = arcanada ]
}

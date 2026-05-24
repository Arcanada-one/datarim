#!/usr/bin/env bats
# hunk-selective-staging.bats — workspace discipline integration (Phase 2b).
# Source: plan TUNE-0268 § Phase 2 step 2.7 + threat-model row 475-476.
# Verifies lib/workspace-discipline.sh:
#   - ws_check_id_ownership: file with only --task ID or no IDs → 0; file with foreign TASK-ID → 34
#   - ws_stage_selective_hunk: no-op when file not git-tracked; selective git update-index --add when tracked

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$DATARIM_CLI_DIR/lib/workspace-discipline.sh"
    [[ -f "$LIB" ]] || skip "lib/workspace-discipline.sh not yet implemented"
    FIX="$BATS_TMPDIR/ws-disc-$$"
    mkdir -p "$FIX"
}

teardown() { [[ -z "${FIX:-}" ]] || rm -rf "$FIX"; }

@test "1: ws_check_id_ownership — file referencing only target TASK-ID → exit 0" {
    cat > "$FIX/clean.md" <<'EOF'
# Notes for TUNE-0268
- TUNE-0268 · in_progress · P2 · L3 · Item
EOF
    run bash -c "source '$LIB' && ws_check_id_ownership '$FIX/clean.md' TUNE-0268"
    [ "$status" -eq 0 ]
}

@test "2: ws_check_id_ownership — file with no TASK-ID references → exit 0 (passive)" {
    cat > "$FIX/empty.md" <<'EOF'
# Just plain prose, no task IDs anywhere
- generic bullet
EOF
    run bash -c "source '$LIB' && ws_check_id_ownership '$FIX/empty.md' TUNE-0268"
    [ "$status" -eq 0 ]
}

@test "3: ws_check_id_ownership — file referencing foreign TASK-ID → exit 34 WORKSPACE_DISCIPLINE_VIOLATION" {
    cat > "$FIX/foreign.md" <<'EOF'
# Mixed content
- TUNE-0268 · own line
- VERD-0099 · foreign hunk from parallel session
EOF
    run bash -c "source '$LIB' && ws_check_id_ownership '$FIX/foreign.md' TUNE-0268"
    [ "$status" -eq 34 ]
    [[ "$output" == *"VERD-0099"* ]] || [[ "$output" == *"foreign"* ]]
}

@test "4: ws_stage_selective_hunk — file not in git repo → exit 0 (no-op)" {
    # FIX is not a git working tree.
    cat > "$FIX/untracked.md" <<'EOF'
content
EOF
    run bash -c "source '$LIB' && ws_stage_selective_hunk '$FIX/untracked.md' TUNE-0268"
    [ "$status" -eq 0 ]
}

@test "5: ws_stage_selective_hunk — git-tracked file with own ID only → exit 0, staged" {
    cd "$FIX"
    git init -q
    git config user.email "t@t" && git config user.name "t"
    cat > tracked.md <<'EOF'
- TUNE-0268 · pending · P1 · L1 · Initial
EOF
    git add tracked.md && git commit -qm init
    # Modify in-place, then call helper.
    cat > tracked.md <<'EOF'
- TUNE-0268 · in_progress · P1 · L1 · Initial (advanced)
EOF
    run bash -c "cd '$FIX' && source '$LIB' && ws_stage_selective_hunk '$FIX/tracked.md' TUNE-0268"
    [ "$status" -eq 0 ]
    cd "$FIX" && git diff --staged --name-only | grep -qx tracked.md
}

@test "6: ws_stage_selective_hunk — git-tracked file referencing foreign ID → exit 34 (refuse)" {
    cd "$FIX"
    git init -q
    git config user.email "t@t" && git config user.name "t"
    cat > tracked.md <<'EOF'
- TUNE-0268 · own
EOF
    git add tracked.md && git commit -qm init
    cat > tracked.md <<'EOF'
- TUNE-0268 · own
- VERD-0099 · foreign hunk leaked in from parallel session
EOF
    run bash -c "cd '$FIX' && source '$LIB' && ws_stage_selective_hunk '$FIX/tracked.md' TUNE-0268"
    [ "$status" -eq 34 ]
    # Nothing should be staged.
    cd "$FIX" && [[ -z "$(git diff --staged --name-only)" ]]
}

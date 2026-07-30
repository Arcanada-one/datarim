#!/usr/bin/env bats
# tests/dr-init-id-lock.bats — atomic /dr-init ID-claim marker (race window).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOCK="$REPO/dev-tools/dr-init-id-lock.sh"
    NEXTID="$REPO/dev-tools/next-free-id.sh"
    ROOT="$BATS_TEST_TMPDIR/ws"
    mkdir -p "$ROOT/datarim"
    printf -- '- TUNE-0100 · high-watermark\n' > "$ROOT/datarim/tasks.md"
    printf -- '' > "$ROOT/datarim/backlog.md"
}

@test "acquire on a free ID succeeds (exit 0) and creates the marker" {
    run bash "$LOCK" acquire TUNE-0101 "$ROOT"
    [ "$status" -eq 0 ]
    [ -d "$ROOT/datarim/.locks/TUNE-0101.init-lock" ]
}

@test "second session acquiring the SAME live ID collides (exit 1)" {
    bash "$LOCK" acquire TUNE-0101 "$ROOT"
    run bash "$LOCK" acquire TUNE-0101 "$ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"COLLISION"* ]]
}

@test "release frees the ID for re-acquisition" {
    bash "$LOCK" acquire TUNE-0101 "$ROOT"
    run bash "$LOCK" release TUNE-0101 "$ROOT"
    [ "$status" -eq 0 ]
    [ ! -d "$ROOT/datarim/.locks/TUNE-0101.init-lock" ]
    run bash "$LOCK" acquire TUNE-0101 "$ROOT"
    [ "$status" -eq 0 ]
}

@test "release is idempotent on an absent marker (exit 0)" {
    run bash "$LOCK" release TUNE-0999 "$ROOT"
    [ "$status" -eq 0 ]
}

@test "a stale marker (age >= TTL) is reclaimed on acquire" {
    bash "$LOCK" acquire TUNE-0101 "$ROOT"
    run env DR_INIT_LOCK_TTL=0 bash "$LOCK" acquire TUNE-0101 "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed stale"* || "$output" == *"acquired"* ]]
}

@test "list prints held IDs for the prefix" {
    bash "$LOCK" acquire TUNE-0101 "$ROOT"
    bash "$LOCK" acquire TUNE-0102 "$ROOT"
    run bash "$LOCK" list TUNE "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0101"* ]]
    [[ "$output" == *"TUNE-0102"* ]]
}

@test "next-free-id.sh treats a held marker as a claim surface (skips it)" {
    # Without any marker, the next free ID is TUNE-0101.
    run bash "$NEXTID" TUNE "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0101" ]
    # A concurrent session holds TUNE-0101 (claimed, not yet written to tasks.md).
    bash "$LOCK" acquire TUNE-0101 "$ROOT"
    run bash "$NEXTID" TUNE "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0102" ]
}

@test "two-session race: winner writes tasks.md, loser bumps via marker surface" {
    # Session A claims TUNE-0101 atomically.
    run bash "$LOCK" acquire TUNE-0101 "$ROOT"
    [ "$status" -eq 0 ]
    # Session B, computing max+1 independently, would also target TUNE-0101 —
    # but next-free-id now sees the marker and yields TUNE-0102 instead.
    run bash "$NEXTID" TUNE "$ROOT"
    [ "$output" = "TUNE-0102" ]
    # B claims its bumped ID; no collision.
    run bash "$LOCK" acquire TUNE-0102 "$ROOT"
    [ "$status" -eq 0 ]
}

@test "invalid task ID is rejected (exit 2)" {
    run bash "$LOCK" acquire not-an-id "$ROOT"
    [ "$status" -eq 2 ]
}

@test "acquire without a datarim/ dir is a usage error (exit 2)" {
    run bash "$LOCK" acquire TUNE-0101 "$BATS_TEST_TMPDIR/nope"
    [ "$status" -eq 2 ]
}

@test "wiring: commands/dr-init.md carries a MANDATORY acquire invocation (anti-decay)" {
    # A gate landed without enforcement wiring is documented-but-unwired. Assert the
    # command spec keeps an imperative cue adjacent to the executable call, so a
    # later edit that demotes it to advisory prose fails CI instead of silently
    # reopening the TOCTOU window.
    CMD="$REPO/commands/dr-init.md"
    [ -f "$CMD" ]
    run grep -n 'dr-init-id-lock.sh" acquire' "$CMD"
    [ "$status" -eq 0 ]
    # an imperative cue within 8 lines above the invocation
    inv_line=$(grep -n 'dr-init-id-lock.sh" acquire' "$CMD" | head -1 | cut -d: -f1)
    start=$(( inv_line > 8 ? inv_line - 8 : 1 ))
    run sed -n "${start},${inv_line}p" "$CMD"
    [[ "$output" == *MANDATORY* ]]
    # release is documented too, so the marker is not leaked for the full TTL
    run grep -c 'dr-init-id-lock.sh" release' "$CMD"
    [ "$status" -eq 0 ]
}

@test "wiring: next-free-id.sh reads held markers as claim surface 4" {
    run grep -n 'init-lock' "$REPO/dev-tools/next-free-id.sh"
    [ "$status" -eq 0 ]
}

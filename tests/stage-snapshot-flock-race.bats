#!/usr/bin/env bats
#
# TUNE-0254 — concurrent-write race + lock-timeout (mkdir-based lock).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim/snapshots"
    export OPTIONS="$BATS_TEST_TMPDIR/options.txt"
    printf '/dr-do TUNE-0254 | go\n' > "$OPTIONS"
}

@test "two concurrent writers — file body is coherent (A or B in entirety, never interleaved)" {
    local body_a="$BATS_TEST_TMPDIR/body-a.txt"
    local body_b="$BATS_TEST_TMPDIR/body-b.txt"
    printf 'AAAAAAAAAA writer-A unique marker AAAAAAAAAA\n' > "$body_a"
    printf 'BBBBBBBBBB writer-B unique marker BBBBBBBBBB\n' > "$body_b"

    # Spawn two writers in parallel via subshells.
    (
        # shellcheck source=/dev/null
        . "$WRITER_LIB"
        write_stage_snapshot \
            --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
            --captured-by agent --recommended-next /dr-do \
            --options-file "$OPTIONS" --body-file "$body_a"
    ) &
    local pid_a=$!
    (
        . "$WRITER_LIB"
        write_stage_snapshot \
            --root "$TMPROOT" --task TUNE-0254 --stage do --command /dr-do \
            --captured-by agent --recommended-next /dr-qa \
            --options-file "$OPTIONS" --body-file "$body_b"
    ) &
    local pid_b=$!
    wait "$pid_a"
    wait "$pid_b"

    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    [ -f "$snap" ]

    local has_a=0 has_b=0
    grep -q 'writer-A unique marker' "$snap" && has_a=1
    grep -q 'writer-B unique marker' "$snap" && has_b=1
    # Exactly one body wins. Never both (would imply interleave).
    [ $((has_a + has_b)) -eq 1 ]

    # Lock directory cleaned up.
    [ ! -d "$TMPROOT/datarim/snapshots/.lock.TUNE-0254" ]
}

@test "four concurrent writers under repeated bursts — every wait exits 0 and body stays coherent" {
    # CI-like amplification of the $$ / late-cleanup race that failed resulting-main
    # bats on Arcanada-one/datarim#536 merge (run 39985213658, shard 4/8).
    # Four writers × three bursts keeps contention high without multi-minute
    # wall time from acquire_plugin_lock's 1s retry sleep under deep queues.
    local i tag body snap markers marker_count pid
    local pids
    snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"

    for i in 1 2 3; do
        pids=""
        for tag in A B C D; do
            body="$BATS_TEST_TMPDIR/body-${i}-${tag}.txt"
            printf 'burst-%s writer-%s unique marker %s\n' "$i" "$tag" "$tag" > "$body"
            (
                # shellcheck source=/dev/null
                . "$WRITER_LIB"
                write_stage_snapshot \
                    --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
                    --captured-by agent --recommended-next /dr-do \
                    --options-file "$OPTIONS" --body-file "$body"
            ) &
            pids="$pids $!"
        done
        for pid in $pids; do
            wait "$pid"
        done
        [ -f "$snap" ]
        marker_count=0
        for tag in A B C D; do
            if grep -q "writer-${tag} unique marker ${tag}" "$snap"; then
                marker_count=$((marker_count + 1))
            fi
        done
        # Exactly one coherent body; never an interleave of multiple markers.
        [ "$marker_count" -eq 1 ]
        [ ! -d "$TMPROOT/datarim/snapshots/.lock.TUNE-0254" ]
        # No stranded temps from a colliding publish path.
        markers="$(find "$TMPROOT/datarim/snapshots" -maxdepth 1 -name 'TUNE-0254.snapshot.md.tmp*' 2>/dev/null | wc -l | tr -d ' ')"
        [ "$markers" -eq 0 ]
    done
}

@test "second writer hits lock-timeout — exits 3" {
    local body="$BATS_TEST_TMPDIR/body.txt"
    printf 'lock-timeout body\n' > "$body"

    # Pre-create lock dir to simulate held lock.
    mkdir -p "$TMPROOT/datarim/snapshots/.lock.TUNE-0254"

    # Set 1 sec timeout to keep test fast.
    DR_SNAPSHOT_LOCK_TIMEOUT=1 run bash -c "
        . '$WRITER_LIB'
        write_stage_snapshot \
            --root '$TMPROOT' --task TUNE-0254 --stage plan --command /dr-plan \
            --captured-by agent --recommended-next /dr-do \
            --options-file '$OPTIONS' --body-file '$body'
    "
    [ "$status" -eq 3 ]

    # Cleanup
    rmdir "$TMPROOT/datarim/snapshots/.lock.TUNE-0254" 2>/dev/null || true
}

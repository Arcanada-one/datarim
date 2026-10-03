#!/usr/bin/env bats
#
# Contract test for dev-tools/check-shared-tree-conflict.sh.
# A file that differs from the base ref in the working tree must report CONFLICT
# (exit 1); a file matching the base must report CLEAN (exit 0); a path outside
# any git work tree must report CANNOT-PROBE without setting exit 1 (fail-open).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-shared-tree-conflict.sh"
    WORK="$(mktemp -d)"
    git -C "$WORK" init -q
    git -C "$WORK" config user.email t@t.t
    git -C "$WORK" config user.name t
    printf 'original\n' > "$WORK/tracked.txt"
    printf 'clean\n' > "$WORK/clean.txt"
    git -C "$WORK" add -A
    git -C "$WORK" commit -q -m base
}

teardown() {
    rm -rf "$WORK"
}

@test "clean file matching base -> exit 0, CLEAN" {
    run bash "$SCRIPT" --base HEAD --repo "$WORK" "$WORK/clean.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN: clean.txt"* ]]
}

@test "file with uncommitted change vs base -> exit 1, CONFLICT" {
    printf 'foreign edit\n' >> "$WORK/tracked.txt"
    run bash "$SCRIPT" --base HEAD --repo "$WORK" "$WORK/tracked.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CONFLICT: tracked.txt"* ]]
    [[ "$output" == *"isolate via git worktree"* ]]
}

@test "mixed set: one clean one dirty -> exit 1 (any conflict fails)" {
    printf 'dirty\n' >> "$WORK/tracked.txt"
    run bash "$SCRIPT" --base HEAD --repo "$WORK" "$WORK/clean.txt" "$WORK/tracked.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLEAN: clean.txt"* ]]
    [[ "$output" == *"CONFLICT: tracked.txt"* ]]
}

@test "path outside a git work tree -> CANNOT-PROBE, does not set exit 1 alone" {
    OUT="$(mktemp -d)"
    printf 'x\n' > "$OUT/loose.txt"
    run bash "$SCRIPT" --repo "$OUT" "$OUT/loose.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CANNOT-PROBE"* ]]
    rm -rf "$OUT"
}

@test "no file argument -> usage error exit 2" {
    run bash "$SCRIPT" --repo "$WORK"
    [ "$status" -eq 2 ]
}

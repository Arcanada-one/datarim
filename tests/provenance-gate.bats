#!/usr/bin/env bats
# TUNE-0510 — provenance / tip-freshness Step-0 gate for /dr-qa and /dr-compliance.
# Red: a drifted tip or dirty working tree blocks. Green: a clean matching tip passes.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/provenance-gate.sh"
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email "t@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    # datarim/ is gitignored in Datarim-managed repos, so the evidence-record
    # file (written under datarim/provenance/) never dirties the tree.
    printf 'datarim/\n' >"$REPO/.gitignore"
    printf 'one\n' >"$REPO/a.txt"
    git -C "$REPO" add .gitignore a.txt
    git -C "$REPO" commit -q -m "c1"
}

# ── Green cases ──────────────────────────────────────────────────────────────

@test "green: verify passes on a clean matching tip (--expected-sha)" {
    head="$(git -C "$REPO" rev-parse HEAD)"
    run bash "$SCRIPT" --root "$REPO" --expected-sha "$head" --stage qa
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "green: record then verify via evidence file passes" {
    ef="$REPO/datarim/prov.sha"
    run bash "$SCRIPT" --root "$REPO" --record --evidence-file "$ef" --stage qa
    [ "$status" -eq 0 ]
    [ -f "$ef" ]
    run bash "$SCRIPT" --root "$REPO" --evidence-file "$ef" --stage compliance
    [ "$status" -eq 0 ]
}

@test "green: --task derives default evidence file under datarim/provenance" {
    run bash "$SCRIPT" --root "$REPO" --record --task TUNE-0510 --stage qa
    [ "$status" -eq 0 ]
    [ -f "$REPO/datarim/provenance/TUNE-0510.sha" ]
    run bash "$SCRIPT" --root "$REPO" --task TUNE-0510 --stage compliance
    [ "$status" -eq 0 ]
}

@test "green: --allow-dirty bypasses the clean-tree assertion" {
    head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'dirty\n' >>"$REPO/a.txt"
    run bash "$SCRIPT" --root "$REPO" --expected-sha "$head" --allow-dirty
    [ "$status" -eq 0 ]
}

# ── Red cases (gate violation, exit 1) ───────────────────────────────────────

@test "red: dirty tracked file blocks (exit 1)" {
    head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'dirty\n' >>"$REPO/a.txt"
    run bash "$SCRIPT" --root "$REPO" --expected-sha "$head"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not clean"* ]]
}

@test "red: untracked file blocks (exit 1)" {
    head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'x\n' >"$REPO/untracked.txt"
    run bash "$SCRIPT" --root "$REPO" --expected-sha "$head"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not clean"* ]]
}

@test "red: amended tip after record blocks (exit 1)" {
    ef="$REPO/datarim/prov.sha"
    run bash "$SCRIPT" --root "$REPO" --record --evidence-file "$ef"
    [ "$status" -eq 0 ]
    # A message change guarantees a distinct SHA (a no-edit amend within the same
    # second can reproduce a byte-identical commit object).
    git -C "$REPO" commit -q --amend -m "c1-amended"
    run bash "$SCRIPT" --root "$REPO" --evidence-file "$ef"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tip moved"* ]]
}

@test "red: new commit after record blocks (exit 1)" {
    ef="$REPO/datarim/prov.sha"
    bash "$SCRIPT" --root "$REPO" --record --evidence-file "$ef"
    printf 'two\n' >"$REPO/b.txt"
    git -C "$REPO" add b.txt
    git -C "$REPO" commit -q -m "c2"
    run bash "$SCRIPT" --root "$REPO" --evidence-file "$ef"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tip moved"* ]]
}

@test "red: unresolvable evidence SHA blocks (exit 1)" {
    run bash "$SCRIPT" --root "$REPO" \
        --expected-sha "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no longer resolves"* ]]
}

# ── Usage / environment errors (exit 2) ──────────────────────────────────────

@test "usage: verify without any expected source errors (exit 2)" {
    run bash "$SCRIPT" --root "$REPO"
    [ "$status" -eq 2 ]
}

@test "usage: verify with a missing evidence file errors (exit 2)" {
    run bash "$SCRIPT" --root "$REPO" --evidence-file "$REPO/datarim/absent.sha"
    [ "$status" -eq 2 ]
}

@test "usage: non-git root errors (exit 2)" {
    mkdir -p "$BATS_TEST_TMPDIR/plain"
    run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR/plain" --expected-sha abc123
    [ "$status" -eq 2 ]
}

@test "usage: unknown flag errors (exit 2)" {
    run bash "$SCRIPT" --root "$REPO" --bogus
    [ "$status" -eq 2 ]
}

@test "usage: --record without a file target errors (exit 2)" {
    run bash "$SCRIPT" --root "$REPO" --record
    [ "$status" -eq 2 ]
}

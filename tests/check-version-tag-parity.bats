#!/usr/bin/env bats
# Regression contract for dev-tools/check-version-tag-parity.sh — the gate that
# fails when VERSION on main has no matching v<VERSION> tag on origin (the
# silent half-release: bumped manifest, never-pushed tag, no release artefacts).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    GATE="$REPO_ROOT/dev-tools/check-version-tag-parity.sh"
    WORK="$(mktemp -d "${BATS_TMPDIR}/vtp.XXXXXX")"

    # Bare "origin" + a clone declaring VERSION, so ls-remote hits a real remote.
    git init -q --bare "$WORK/origin.git"
    git init -q "$WORK/clone"
    (
        cd "$WORK/clone"
        git config user.email t@example.invalid; git config user.name t
        echo "3.5.7" > VERSION
        git add VERSION && git commit -qm "bump to 3.5.7"
        git remote add origin "$WORK/origin.git"
        git push -q origin HEAD:main
    )
}

teardown() { rm -rf "$WORK"; }

@test "V1 PASS when the remote carries the matching tag" {
    (cd "$WORK/clone" && git tag -a v3.5.7 -m "release 3.5.7" && git push -q origin v3.5.7)
    run bash "$GATE" --check --repo "$WORK/clone"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"*"v3.5.7"* ]]
}

@test "V2 FAIL when no tag exists for VERSION (the half-release)" {
    run bash "$GATE" --check --repo "$WORK/clone"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"*"v3.5.7"*"never tagged"* ]]
}

@test "V3 a LOCAL-only tag must NOT pass — the release workflow fires on the remote push" {
    (cd "$WORK/clone" && git tag -a v3.5.7 -m "release 3.5.7")   # not pushed
    run bash "$GATE" --check --repo "$WORK/clone"
    [ "$status" -eq 1 ]
}

@test "V4 FAIL when only a DIFFERENT version is tagged" {
    (cd "$WORK/clone" && git tag -a v3.5.6 -m "release 3.5.6" && git push -q origin v3.5.6)
    run bash "$GATE" --check --repo "$WORK/clone"
    [ "$status" -eq 1 ]
}

@test "V5 --wait-seconds picks up a tag that arrives inside the window" {
    ( sleep 2; cd "$WORK/clone" && git tag -a v3.5.7 -m "release 3.5.7" && git push -q origin v3.5.7 ) &
    run bash "$GATE" --check --repo "$WORK/clone" --wait-seconds 40
    wait
    [ "$status" -eq 0 ]
}

@test "V6 usage errors are exit 2, not silent passes" {
    run bash "$GATE" --repo "$WORK/clone"          # missing --check
    [ "$status" -eq 2 ]
    run bash "$GATE" --check --repo "$WORK"        # not a work tree
    [ "$status" -eq 2 ]
    (cd "$WORK/clone" && echo "not-a-version" > VERSION)
    run bash "$GATE" --check --repo "$WORK/clone"  # malformed VERSION
    [ "$status" -eq 2 ]
}

@test "V7 wiring: framework-gates runs intent-aware parity on main-push without runner wait" {
    wf="$REPO_ROOT/.github/workflows/framework-gates.yml"
    reconcile="$REPO_ROOT/.github/workflows/release-tag-reconcile.yml"
    grep -q "check-version-tag-parity.sh --check" "$wf"
    # The job must be fenced off pull_request runs (release PRs bump VERSION pre-tag).
    awk '/version-tag-parity:/,/component-counts:/' "$wf" | grep -q "github.event_name == 'push'"
    # ARC-CI-05: no 900s runner sleep; durable intent + off-runner reconcile.
    awk '/version-tag-parity:/,/component-counts:/' "$wf" | grep -q -- "--allow-pending-intent"
    ! awk '/version-tag-parity:/,/component-counts:/' "$wf" | grep -q -- "--wait-seconds"
    [ -f "$reconcile" ]
    grep -q "verify-release-intent.sh --check" "$reconcile"
}

@test "V8 durable release intent covers the merge→tag window without waiting" {
    head_sha="$(cd "$WORK/clone" && git rev-parse HEAD)"
    run bash "$REPO_ROOT/dev-tools/record-release-intent.sh" \
        --repo "$WORK/clone" --version 3.5.7 --source-sha "$head_sha"
    [ "$status" -eq 0 ]
    run bash "$GATE" --check --repo "$WORK/clone" --allow-pending-intent
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING"*"3.5.7"* ]]
}

#!/usr/bin/env bats

setup() {
    TOOL="${BATS_TEST_DIRNAME}/../scripts/verify-personal-id-overlay-revision.py"
    OVERLAY="$BATS_TEST_TMPDIR/private.regex"
    printf 'synthetic-protected-pattern\n' > "$OVERLAY"
    export DATARIM_PERSONAL_ID_REVISION_ID='test-inventory-2026-r1'
    export DATARIM_PERSONAL_ID_OVERLAY_SHA256="$(sha256sum "$OVERLAY" | cut -d ' ' -f 1)"
}

@test "matching protected overlay reports only a revision fingerprint" {
    run python3 "$TOOL" --overlay "$OVERLAY"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^private\ overlay\ revision\ fingerprint:\ [0-9a-f]{12}\ verified$ ]]
    [[ "$output" != *'synthetic-protected-pattern'* ]]
}

@test "changed overlay is refused without displaying content or digest" {
    printf 'another-synthetic-pattern\n' >> "$OVERLAY"
    run python3 "$TOOL" --overlay "$OVERLAY"
    [ "$status" -eq 2 ]
    [[ "$output" == *'revision check failed'* ]]
    [[ "$output" != *'synthetic-protected-pattern'* ]]
    [[ "$output" != *"$DATARIM_PERSONAL_ID_OVERLAY_SHA256"* ]]
}

@test "missing revision commitment is refused" {
    unset DATARIM_PERSONAL_ID_OVERLAY_SHA256
    run python3 "$TOOL" --overlay "$OVERLAY"
    [ "$status" -eq 2 ]
    [[ "$output" == *'revision check failed'* ]]
}

@test "protected manifest verifies a host copy and rejects a symlink" {
    printf '{"revision_id":"test-inventory-2026-r1","overlay_sha256":"%s"}\n' \
        "$DATARIM_PERSONAL_ID_OVERLAY_SHA256" > "$BATS_TEST_TMPDIR/manifest.json"
    run python3 "$TOOL" --overlay "$OVERLAY" --manifest "$BATS_TEST_TMPDIR/manifest.json"
    [ "$status" -eq 0 ]
    ln -s "$OVERLAY" "$BATS_TEST_TMPDIR/link.regex"
    run python3 "$TOOL" --overlay "$BATS_TEST_TMPDIR/link.regex" --manifest "$BATS_TEST_TMPDIR/manifest.json"
    [ "$status" -eq 2 ]
}

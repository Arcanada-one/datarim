#!/usr/bin/env bats
#
# Tests for dev-tools/check-resume-block-mirror.sh (TUNE-0441 V-AC-7)
#
# Coverage:
#   - --check exits 0 on canonical (byte-identical) files
#   - --check exits 1 when one mirror's fence is altered
#   - --report mode prints diff on drift
#   - exits 2 on usage error (unknown flag)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
GATE="${REPO_ROOT}/dev-tools/check-resume-block-mirror.sh"

# ---------------------------------------------------------------------------
# Gate passes on canonical (shipped) files
# ---------------------------------------------------------------------------

@test "mirror-gate: canonical files are byte-identical (exit 0)" {
    run bash "$GATE" --check --root "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "mirror-gate: --report mode prints OK on canonical files" {
    run bash "$GATE" --report --root "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ---------------------------------------------------------------------------
# Gate fails when one mirror fence is mutated
# ---------------------------------------------------------------------------

@test "mirror-gate: exits 1 when dr-save.md fence has extra line" {
    # Create a temp dir with mutated copies.
    local tmpdir
    tmpdir="$(mktemp -d "${BATS_TEST_TMPDIR}/mirror-test.XXXX")"

    # Mirror structure.
    mkdir -p "${tmpdir}/commands"
    mkdir -p "${tmpdir}/skills/session-handoff-writer"

    # Copy canonical files.
    cp "${REPO_ROOT}/commands/dr-save.md" "${tmpdir}/commands/dr-save.md"
    cp "${REPO_ROOT}/skills/session-handoff-writer/SKILL.md" \
        "${tmpdir}/skills/session-handoff-writer/SKILL.md"

    # Mutate dr-save.md: insert an extra line inside the fence body.
    # We insert after the "To resume in a fresh window" line.
    sed -i.bak 's|To resume in a fresh window, copy this line exactly:|To resume in a fresh window, copy this line exactly:\n  # MUTATED LINE|' \
        "${tmpdir}/commands/dr-save.md"

    run bash "$GATE" --check --root "$tmpdir"
    [ "$status" -eq 1 ]

    rm -rf "$tmpdir"
}

@test "mirror-gate: exits 1 when SKILL.md fence has a character removed" {
    local tmpdir
    tmpdir="$(mktemp -d "${BATS_TEST_TMPDIR}/mirror-test2.XXXX")"
    mkdir -p "${tmpdir}/commands"
    mkdir -p "${tmpdir}/skills/session-handoff-writer"

    cp "${REPO_ROOT}/commands/dr-save.md" "${tmpdir}/commands/dr-save.md"
    cp "${REPO_ROOT}/skills/session-handoff-writer/SKILL.md" \
        "${tmpdir}/skills/session-handoff-writer/SKILL.md"

    # Mutate SKILL.md: change one character in the fence body.
    sed -i.bak 's|/dr-continue {SESSION-ID}|/dr-continue {SESSION-ID-MUTATED}|' \
        "${tmpdir}/skills/session-handoff-writer/SKILL.md"

    run bash "$GATE" --check --root "$tmpdir"
    [ "$status" -eq 1 ]

    rm -rf "$tmpdir"
}

@test "mirror-gate: --report prints unified diff on drift" {
    local tmpdir
    tmpdir="$(mktemp -d "${BATS_TEST_TMPDIR}/mirror-test3.XXXX")"
    mkdir -p "${tmpdir}/commands"
    mkdir -p "${tmpdir}/skills/session-handoff-writer"

    cp "${REPO_ROOT}/commands/dr-save.md" "${tmpdir}/commands/dr-save.md"
    cp "${REPO_ROOT}/skills/session-handoff-writer/SKILL.md" \
        "${tmpdir}/skills/session-handoff-writer/SKILL.md"

    # Introduce drift.
    sed -i.bak 's|Do NOT use|Do NOT EVER use|' \
        "${tmpdir}/commands/dr-save.md"

    run bash "$GATE" --report --root "$tmpdir"
    [ "$status" -eq 1 ]
    # Output (stderr merged) should contain diff-style markers.
    [[ "$output" =~ "DRIFT" ]] || [[ "${output}" =~ "differ" ]]

    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Usage error
# ---------------------------------------------------------------------------

@test "mirror-gate: exits 2 on unknown flag" {
    run bash "$GATE" --unknown-flag
    [ "$status" -eq 2 ]
}

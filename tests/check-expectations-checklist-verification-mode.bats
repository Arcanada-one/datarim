#!/usr/bin/env bats
# check-expectations-checklist-verification-mode.bats — TUNE-0454
#
# Covers verification_mode / evidence_artifact (schema v3) durability mechanism.
#
#   1.  optional-field-absent-ok          — v3, no verification_mode → exit 0
#   2.  reproducible-without-artifact     — reproducible, no evidence_artifact → exit 1, verification-not-wired
#   3.  reproducible-with-file-path       — evidence_artifact = real committed file → pass
#   4.  reproducible-with-grep-target     — evidence_artifact = string grep-findable in .bats/.sh → pass
#   5.  bad-enum-rejected                 — verification_mode: ad-hoc → exit 1
#   6.  v2-task-still-valid               — schema_version: 2, no verification_mode → pass (zero regression)
#   7.  schema-version-3-accepted         — schema_version: 3 → no version-reject error
#   8.  v1-deprecation-still-fires        — schema_version: 1 → DEPRECATION to stderr, exit 0
#   9.  heuristic-advisory-fires          — v3, empirical, no verification_mode, success-criterion has HTTP URL
#   10. stub-artifact-advisory            — reproducible + evidence_artifact file with only stubs → advisory stderr, exit 0

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# write_v3_expectations <ID> <wish_body>
# Writes a minimal valid schema_version: 3 file with one item whose body is
# provided by the caller. Uses evidence_type: empirical (required by v3).
write_v3_expectations() {
    local id="$1"
    local wish_body="$2"
    cat > "$TMPROOT/datarim/tasks/${id}-expectations.md" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 3
captured_at: 2026-06-23
captured_by: /dr-prd
agent: architect
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Feature works end-to-end.**
  - wish_id: feature-works
  - Что хочу проверить: The feature behaves correctly in all scenarios.
  - Как проверить (success criterion): Run the acceptance test suite; all pass.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: empirical
$wish_body
  - #### История статусов
    - 2026-06-23T10:00:00Z / 23.06.2026 13:00 (MSK) · /dr-prd · pending → pending · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
EOF
}

# write_v2_expectations <ID>
# Writes a minimal valid schema_version: 2 file (no verification_mode fields).
write_v2_expectations() {
    local id="$1"
    cat > "$TMPROOT/datarim/tasks/${id}-expectations.md" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 2
captured_at: 2026-06-23
captured_by: /dr-prd
agent: planner
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Validator output is correct.**
  - wish_id: validator-output-correct
  - Что хочу проверить: Validator exits 0 on well-formed v2 input.
  - Как проверить (success criterion): Run validator; exit code is 0.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: static
  - #### История статусов
    - 2026-06-23T10:00:00Z / 23.06.2026 13:00 (MSK) · /dr-prd · pending → pending · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
EOF
}

# write_v1_expectations <ID>
# Writes a minimal valid schema_version: 1 file.
write_v1_expectations() {
    local id="$1"
    cat > "$TMPROOT/datarim/tasks/${id}-expectations.md" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 1
captured_at: 2026-06-23
captured_by: /dr-prd
agent: planner
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Basic item.**
  - wish_id: basic-item
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-06-23T10:00:00Z / 23.06.2026 13:00 (MSK) · /dr-prd · pending → pending · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
EOF
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "VM1 optional-field-absent-ok: v3 wish without verification_mode exits 0" {
    write_v3_expectations "VM-0001" ""
    run "$CHECK" --task VM-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "VM2 reproducible-without-artifact-fails: reproducible + no evidence_artifact exits 1" {
    write_v3_expectations "VM-0002" "  - verification_mode: reproducible"
    run "$CHECK" --task VM-0002 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    # run merges stderr into $output by default in bats.
    [[ "$output" == *"verification-not-wired"* ]]
}

@test "VM3 reproducible-with-file-path-passes: evidence_artifact resolved via test -f" {
    # Create the artifact file that will be resolved.
    mkdir -p "$TMPROOT/tests"
    # NB: the fixture deliberately contains no bats test-declaration token — some
    # bats preprocessors enumerate tests by scanning for that string even
    # inside heredocs, which would inflate the parent suite's test count.
    cat > "$TMPROOT/tests/my-acceptance.bats" <<'BATS'
# acceptance fixture: a real assertion lives here
run true
[ "$status" -eq 0 ]
BATS
    # Initialise a git repo so git rev-parse --show-toplevel works.
    git -C "$TMPROOT" init -q
    git -C "$TMPROOT" add tests/my-acceptance.bats
    git -C "$TMPROOT" -c user.email=t@t.com -c user.name=T commit -qm "init"

    write_v3_expectations "VM-0003" \
        "  - verification_mode: reproducible
  - evidence_artifact: tests/my-acceptance.bats"

    run "$CHECK" --task VM-0003 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "VM4 reproducible-with-grep-target-passes: evidence_artifact resolved via grep" {
    # Create a bats file whose content mentions the test-id string.
    mkdir -p "$TMPROOT/tests"
    # No bats test-declaration token in the fixture (see VM3 note). The evidence_artifact
    # value below is the grep target — it just has to appear in this file's text.
    cat > "$TMPROOT/tests/suite.bats" <<'BATS'
# suite fixture containing the test-id string: feature-e2e-check
run true
[ "$status" -eq 0 ]
BATS
    git -C "$TMPROOT" init -q
    git -C "$TMPROOT" add tests/suite.bats
    git -C "$TMPROOT" -c user.email=t@t.com -c user.name=T commit -qm "init"

    # evidence_artifact is a test-id string (not a file path) — tier-2 grep.
    write_v3_expectations "VM-0004" \
        "  - verification_mode: reproducible
  - evidence_artifact: feature-e2e-check"

    run "$CHECK" --task VM-0004 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "VM5 bad-enum-rejected: verification_mode=ad-hoc exits 1" {
    write_v3_expectations "VM-0005" "  - verification_mode: ad-hoc"
    run "$CHECK" --task VM-0005 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"verification_mode not in enum"* ]]
}

@test "VM6 v2-task-still-valid: schema_version=2 without verification_mode exits 0 (zero regression)" {
    write_v2_expectations "VM-0006"
    run "$CHECK" --task VM-0006 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    # Must not mention verification_mode at all in merged output.
    [[ "$output" != *"verification_mode"* ]]
}

@test "VM7 schema-version-3-accepted: schema_version=3 passes version check" {
    write_v3_expectations "VM-0007" ""
    run "$CHECK" --task VM-0007 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    # Must NOT contain the old "must be '1' or '2'" rejection message.
    [[ "$output" != *"must be '1' or '2'"* ]]
}

@test "VM8 v1-deprecation-still-fires: schema_version=1 emits DEPRECATION to stderr, exit 0" {
    write_v1_expectations "VM-0008"
    run "$CHECK" --task VM-0008 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    # bats run merges stderr into $output by default.
    [[ "$output" == *"DEPRECATION"* ]] || [[ "$stderr" == *"DEPRECATION"* ]]
}

@test "VM9 heuristic-advisory-fires: v3 empirical no-vmode with HTTP URL → ADVISORY stderr, exit 0" {
    # The success criterion contains an HTTP URL — triggers world-state heuristic.
    cat > "$TMPROOT/datarim/tasks/VM-0009-expectations.md" <<'EOF'
---
task_id: VM-0009
artifact: expectations
schema_version: 3
captured_at: 2026-06-23
captured_by: /dr-prd
agent: architect
status: canonical
---

# VM-0009 — Ожидания оператора

## Ожидания

- **1. HTTP endpoint returns 200.**
  - wish_id: endpoint-200
  - Что хочу проверить: The API endpoint is reachable in production.
  - Как проверить (success criterion): curl https://example.com/api/status returns HTTP 200 OK.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: empirical
  - #### История статусов
    - 2026-06-23T10:00:00Z / 23.06.2026 13:00 (MSK) · /dr-prd · pending → pending · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
EOF
    run "$CHECK" --task VM-0009 --root "$TMPROOT"
    # Advisory: exit 0, ADVISORY in output (bats merges stderr into $output).
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVISORY"* ]] || [[ "$stderr" == *"ADVISORY"* ]]
    [[ "$output" == *"verification-mode-suggested-reproducible"* ]] || [[ "$stderr" == *"verification-mode-suggested-reproducible"* ]]
}

@test "VM10 stub-artifact-advisory: reproducible + stub-only file → ADVISORY stderr, exit 0" {
    # Create a test file that consists entirely of stub literals.
    # All non-blank lines must be stubs for the all-stubs advisory to fire.
    mkdir -p "$TMPROOT/tests"
    cat > "$TMPROOT/tests/stub-only.bats" <<'BATS'
expect(true).toBe(true)
BATS
    git -C "$TMPROOT" init -q
    git -C "$TMPROOT" add tests/stub-only.bats
    git -C "$TMPROOT" -c user.email=t@t.com -c user.name=T commit -qm "init"

    write_v3_expectations "VM-0010" \
        "  - verification_mode: reproducible
  - evidence_artifact: tests/stub-only.bats"

    run "$CHECK" --task VM-0010 --root "$TMPROOT"
    # Stub-only advisory: still exit 0 (advisory, not hard error).
    [ "$status" -eq 0 ]
    [[ "$output" == *"evidence-artifact-is-stub"* ]] || [[ "$stderr" == *"evidence-artifact-is-stub"* ]]
}

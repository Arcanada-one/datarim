#!/usr/bin/env bats
#
# compound-task-id-acceptance — the four task-ID validators must accept
# compound shapes {PREFIX-NNNN-suffix...} (follow-up tasks).
#
# Contract: skills/datarim-system/SKILL.md § Unified Task Numbering allows
# compound IDs (e.g. `DEV-1234-FU-slug`, `DEV-1234-FOLLOWUP-slug`). The four
# scripts below previously enforced the bare `^[A-Z]+-[0-9]{4}$` shape and
# rejected compound IDs end-to-end across the pipeline.
#
# Sibling reference: scripts/datarim-doctor.sh ONELINER_RE already supports
# `(-[A-Za-z0-9]+)*`.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

INIT_TASK="$REPO_ROOT/dev-tools/check-init-task-presence.sh"
APPEND_QA="$REPO_ROOT/dev-tools/append-init-task-qa.sh"
EXPECTATIONS="$REPO_ROOT/dev-tools/check-expectations-checklist.sh"
PRE_ARCHIVE="$REPO_ROOT/scripts/pre-archive-check.sh"

# Build a minimal datarim/ workspace under $BATS_TMPDIR for one compound ID.
setup() {
    WORK="$(mktemp -d "$BATS_TMPDIR/compound-XXXXXX")"
    export WORK
    mkdir -p "$WORK/datarim/tasks"
    cd "$WORK"
    git init -q . >/dev/null
    git -C "$WORK" config user.email t@t
    git -C "$WORK" config user.name t

    # init-task fixture (compound ID)
    cat > "$WORK/datarim/tasks/DEV-1234-FU-slug-init-task.md" <<'EOF'
---
task_id: DEV-1234-FU-slug
artifact: init-task
schema_version: 1
captured_at: 2026-05-27
captured_by: /dr-init
operator: t@t
status: canonical
source: backlog
---

## Operator brief (verbatim)

Body.

## Append-log (operator amendments)

_(empty)_
EOF

    # expectations fixture (compound ID, schema_version 2, bullet-list shape)
    cat > "$WORK/datarim/tasks/DEV-1234-FU-slug-expectations.md" <<'EOF'
---
task_id: DEV-1234-FU-slug
artifact: expectations
schema_version: 2
captured_at: 2026-05-27
captured_by: /dr-init
agent: planner
status: canonical
parent_init_task: DEV-1234-FU-slug-init-task.md
---

## Ожидания

- **1. Test wish.**
  - wish_id: test-wish
  - Что хочу проверить: пример
  - Как проверить (success criterion): grep
  - Связанный AC из PRD: «—»
  - evidence_type: static
  - #### История статусов
    - 2026-05-27T00:00:00Z / 2026-05-27 · /dr-init · pending → pending · reason: created
  - #### Текущий статус
    - met
EOF
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# -----------------------------------------------------------------------------
# T1: check-init-task-presence.sh accepts compound task_id frontmatter.
# -----------------------------------------------------------------------------
@test "T1: check-init-task-presence accepts DEV-1234-FU-slug" {
    run bash "$INIT_TASK" --task DEV-1234-FU-slug --root "$WORK"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# T2: append-init-task-qa.sh --task accepts compound ID at usage validation.
#     We only exercise the regex — the script needs --question/--answer files
#     so we provide minimal fixtures.
# -----------------------------------------------------------------------------
@test "T2: append-init-task-qa accepts --task DEV-1234-FU-slug" {
    qf="$WORK/q.txt"; af="$WORK/a.txt"
    printf 'Q?' > "$qf"; printf 'A.' > "$af"
    run bash "$APPEND_QA" --root "$WORK" --task DEV-1234-FU-slug \
        --stage do --round 1 \
        --question-file "$qf" --answer-file "$af" \
        --decided-by operator --summary "test"
    # Either exit 0 (write succeeded) or non-2 (regex passed, downstream issue).
    # Compound-ID regex failure produced exit 2 with the «must match» message.
    [ "$status" -ne 2 ] || ! echo "$output" | grep -q "must match"
}

# -----------------------------------------------------------------------------
# T3: check-expectations-checklist.sh --task accepts compound ID.
# -----------------------------------------------------------------------------
@test "T3: check-expectations-checklist --task accepts DEV-1234-FU-slug" {
    run bash "$EXPECTATIONS" --task DEV-1234-FU-slug --root "$WORK"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# T4: check-expectations-checklist.sh --verify accepts compound ID.
# -----------------------------------------------------------------------------
@test "T4: check-expectations-checklist --verify accepts DEV-1234-FU-slug" {
    run bash "$EXPECTATIONS" --verify DEV-1234-FU-slug --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *PASS* ]]
}

# -----------------------------------------------------------------------------
# T5: pre-archive-check.sh --task-id accepts compound ID at regex gate.
#     A clean workspace + no schema files → script runs past the regex check.
# -----------------------------------------------------------------------------
@test "T5: pre-archive-check --task-id accepts DEV-1234-FU-slug" {
    run bash "$PRE_ARCHIVE" --task-id DEV-1234-FU-slug --shared "$WORK" --no-schema-check
    # We only care that the regex did NOT reject the compound ID
    # (previous behaviour was exit 2 with «invalid --task-id» message).
    ! echo "$output" | grep -q "invalid --task-id"
}

# -----------------------------------------------------------------------------
# T6: same scripts STILL reject malformed IDs (regression guard for the relax).
# -----------------------------------------------------------------------------
@test "T6: append-init-task-qa rejects lowercase prefix" {
    qf="$WORK/q.txt"; af="$WORK/a.txt"
    printf 'Q?' > "$qf"; printf 'A.' > "$af"
    run bash "$APPEND_QA" --root "$WORK" --task "dev-1234" \
        --stage do --round 1 \
        --question-file "$qf" --answer-file "$af" \
        --decided-by operator --summary "test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must match"* ]]
}

@test "T7: pre-archive-check rejects DEV-12 (too few digits)" {
    run bash "$PRE_ARCHIVE" --task-id "DEV-12" --shared "$WORK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid --task-id"* ]]
}

@test "T8: check-expectations-checklist rejects bare 'foo' task_id in frontmatter" {
    cat > "$WORK/datarim/tasks/foo-expectations.md" <<'EOF'
---
task_id: foo
artifact: expectations
schema_version: 2
captured_at: 2026-05-27
captured_by: /dr-init
agent: planner
status: canonical
parent_init_task: foo-init-task.md
---

## Ожидания

- **1. x.**
  - wish_id: x
  - Что хочу проверить: x
  - Как проверить (success criterion): x
  - evidence_type: static
  - #### История статусов
    - 2026-05-27T00:00:00Z / 2026-05-27 · /dr-init · pending → pending · reason: x
  - #### Текущий статус
    - pending
EOF
    run bash "$EXPECTATIONS" --task foo --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"task_id 'foo'"* ]] || [[ "$output" == *"does not match"* ]]
}
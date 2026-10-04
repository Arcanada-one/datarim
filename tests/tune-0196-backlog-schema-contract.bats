#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DOCTOR="$ROOT/scripts/datarim-doctor.sh"
    TMP_CASE="$(mktemp -d)"
    # Dynamic repository root is resolved by Bats setup.
    # shellcheck disable=SC1091
    source "$ROOT/scripts/lib/schema-regex.sh"
    INLINE_LINE='- TUNE-9001 · blocked · P3 · L2 · Preserve this deliberately long pending-work description because backlog is the operator ledger and not the strict active-task index'
    POINTER_LINE="$INLINE_LINE → tasks/TUNE-9001-task-description.md"
}

teardown() {
    rm -rf -- "$TMP_CASE"
}

assert_regex_match() {
    local regex="$1"
    local line="$2"
    [[ "$line" =~ $regex ]]
}

assert_doc_contract() {
    local root="$1"

    grep -Fq '### Backlog ledger line format' "$root/skills/datarim-system/SKILL.md" || return 1
    grep -Fq 'Pointer: optional for backlog entries.' "$root/skills/datarim-system/SKILL.md" || return 1
    grep -Fq 'Active-index pointer: required.' "$root/skills/datarim-system/SKILL.md" || return 1
    grep -Fq -- "ONELINER_RE\` accepts \`in_progress|blocked|not_started|pending|blocked-pending|cancelled\`" "$root/skills/datarim-system/SKILL.md" || return 1
    grep -Fq 'Canonical active-index writers emit' "$root/skills/datarim-system/SKILL.md" || return 1
    grep -Fq 'line-oriented pending-work ledger' "$root/skills/datarim-system/backlog-and-routing.md" || return 1
    grep -Fq 'optional task-description pointer' "$root/skills/datarim-system/backlog-and-routing.md" || return 1

    grep -Fq '### Backlog ledger line format' "$root/skills/datarim-doctor/SKILL.md" || return 1
    grep -Fq 'Pointer: optional for backlog entries.' "$root/skills/datarim-doctor/SKILL.md" || return 1
    grep -Fq 'Active-index pointer: required.' "$root/skills/datarim-doctor/SKILL.md" || return 1
    grep -Fq -- "ONELINER_RE\` accepts \`in_progress|blocked|not_started|pending|blocked-pending|cancelled\`" "$root/skills/datarim-doctor/SKILL.md" || return 1
    grep -Fq 'Canonical active-index writers emit' "$root/skills/datarim-doctor/SKILL.md" || return 1
    ! grep -Fq '## Last Updated' "$root/skills/datarim-doctor/SKILL.md" || return 1

    grep -Fq 'Pointer: optional for backlog entries.' "$root/templates/backlog-template.md" || return 1
    grep -Fq -- '- <TASK-ID-A> · pending · P2 · L2 · <Inline pending-work description>' "$root/templates/backlog-template.md" || return 1
    grep -Fq -- '- <TASK-ID-B> · blocked · P3 · L2 · <Title> → tasks/<TASK-ID-B>-task-description.md' "$root/templates/backlog-template.md" || return 1
    grep -Fq 'TUNE-0196 backlog schema fork is superseded' "$root/CHANGELOG.md" || return 1
}

copy_doc_contract() {
    local target="$1"
    mkdir -p "$target/skills/datarim-system" "$target/skills/datarim-doctor" "$target/templates"
    cp "$ROOT/skills/datarim-system/SKILL.md" "$target/skills/datarim-system/SKILL.md"
    cp "$ROOT/skills/datarim-system/backlog-and-routing.md" "$target/skills/datarim-system/backlog-and-routing.md"
    cp "$ROOT/skills/datarim-doctor/SKILL.md" "$target/skills/datarim-doctor/SKILL.md"
    cp "$ROOT/templates/backlog-template.md" "$target/templates/backlog-template.md"
    cp "$ROOT/CHANGELOG.md" "$target/CHANGELOG.md"
}

rewrite_file() {
    local expression="$1"
    local file="$2"
    local replacement="${file}.next"

    sed "$expression" "$file" >"$replacement" || return 1
    mv "$replacement" "$file" || return 1
}

@test "relaxed backlog regexes accept a long pointerless inline description" {
    assert_regex_match "$BACKLOG_ITEM_RE" "$INLINE_LINE" || return 1
    assert_regex_match "$SCHEMA_BACKLOG_RE" "$INLINE_LINE" || return 1
}

@test "strict active-index regexes require the description pointer" {
    ! assert_regex_match "$ONELINER_RE" "$INLINE_LINE" || return 1
    ! assert_regex_match "$SCHEMA_TASKS_RE" "$INLINE_LINE" || return 1
    assert_regex_match "$ONELINER_RE" "$POINTER_LINE" || return 1
    assert_regex_match "$SCHEMA_TASKS_RE" "$POINTER_LINE" || return 1
}

@test "mandatory-pointer backlog mutants reject the accepted line" {
    local doctor_mutant="$TMP_CASE/schema-doctor-mutant.sh"
    local archive_mutant="$TMP_CASE/schema-archive-mutant.sh"

    cp "$ROOT/scripts/lib/schema-regex.sh" "$doctor_mutant"
    # Literal variable references are required in the sourced mutant.
    # shellcheck disable=SC2016
    rewrite_file 's/^BACKLOG_ITEM_RE=.*/BACKLOG_ITEM_RE="$ONELINER_RE"/' "$doctor_mutant"
    # shellcheck disable=SC2016
    grep -Fq 'BACKLOG_ITEM_RE="$ONELINER_RE"' "$doctor_mutant" || return 1

    # A new shell must source the rewritten file; no parent-process variables.
    # shellcheck disable=SC2016
    run bash -c 'source "$1"; line="$2"; [[ "$line" =~ $BACKLOG_ITEM_RE ]]' _ "$doctor_mutant" "$INLINE_LINE"
    [ "$status" -ne 0 ] || return 1

    cp "$ROOT/scripts/lib/schema-regex.sh" "$archive_mutant"
    # shellcheck disable=SC2016
    rewrite_file 's/^SCHEMA_BACKLOG_RE=.*/SCHEMA_BACKLOG_RE="$SCHEMA_TASKS_RE"/' "$archive_mutant"
    # shellcheck disable=SC2016
    grep -Fq 'SCHEMA_BACKLOG_RE="$SCHEMA_TASKS_RE"' "$archive_mutant" || return 1

    # shellcheck disable=SC2016
    run bash -c 'source "$1"; line="$2"; [[ "$line" =~ $SCHEMA_BACKLOG_RE ]]' _ "$archive_mutant" "$INLINE_LINE"
    [ "$status" -ne 0 ] || return 1
}

@test "Doctor accepts the pointerless line in backlog without a finding" {
    local datarim_root="$TMP_CASE/accepted/datarim"
    mkdir -p "$datarim_root/tasks"
    printf '# Tasks\n\n## Active\n' >"$datarim_root/tasks.md"
    printf '# Backlog\n\n## Pending\n\n%s\n' "$INLINE_LINE" >"$datarim_root/backlog.md"

    run "$DOCTOR" --root="$datarim_root"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" != *"non-compliant backlog item"* ]] || return 1
}

@test "Doctor rejects the same pointerless line in tasks" {
    local datarim_root="$TMP_CASE/rejected/datarim"
    mkdir -p "$datarim_root/tasks"
    printf '# Tasks\n\n## Active\n\n%s\n' "$INLINE_LINE" >"$datarim_root/tasks.md"
    printf '# Backlog\n\n## Pending\n' >"$datarim_root/backlog.md"

    run "$DOCTOR" --root="$datarim_root"
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *"non-compliant bullet"* ]] || return 1
}

@test "shipped docs distinguish backlog ledger from strict active indexes" {
    assert_doc_contract "$ROOT"
}

@test "mutation removing optional-pointer guidance makes the contract red" {
    copy_doc_contract "$TMP_CASE"
    assert_doc_contract "$TMP_CASE" || return 1
    rewrite_file 's/Pointer: optional for backlog entries\./Pointer behavior removed./g' "$TMP_CASE/skills/datarim-system/SKILL.md"

    run assert_doc_contract "$TMP_CASE"
    [ "$status" -ne 0 ] || return 1
}

@test "mutation removing optional-pointer guidance from every shipped surface makes the contract red" {
    for relative in \
        skills/datarim-doctor/SKILL.md \
        templates/backlog-template.md; do
        case_dir="$TMP_CASE/optional-${relative//\//-}"
        copy_doc_contract "$case_dir"
        rewrite_file 's/Pointer: optional for backlog entries\./Pointer behavior removed./g' "$case_dir/$relative"
        run assert_doc_contract "$case_dir"
        [ "$status" -ne 0 ] || return 1
    done
}

@test "mutation removing backlog-ledger fragment guidance makes the contract red" {
    copy_doc_contract "$TMP_CASE"
    assert_doc_contract "$TMP_CASE" || return 1
    rewrite_file 's/optional task-description pointer/removed task-description pointer/g' \
        "$TMP_CASE/skills/datarim-system/backlog-and-routing.md"

    run assert_doc_contract "$TMP_CASE"
    [ "$status" -ne 0 ] || return 1
}

@test "mutation removing required active pointer makes the contract red" {
    copy_doc_contract "$TMP_CASE"
    assert_doc_contract "$TMP_CASE" || return 1
    rewrite_file 's/Active-index pointer: required\./Active-index pointer rule removed./g' "$TMP_CASE/skills/datarim-doctor/SKILL.md"

    run assert_doc_contract "$TMP_CASE"
    [ "$status" -ne 0 ] || return 1
}

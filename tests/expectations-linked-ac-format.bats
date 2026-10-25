#!/usr/bin/env bats
# expectations-linked-ac-format.bats
#
# `--task` mode warns when a `linked_ac` value is neither a V-AC token nor the
# no-link dash. The spec-graph link collector keeps only V-AC tokens, so any
# other value (for example an acceptance-contract criterion id) reads later as
# "wish has no linked V-AC" in `graph-complete-l3`. By then the expectations
# file is usually frozen in a live-evidence contract scope, and correcting it
# invalidates every recorded attempt. The warning moves the finding to the
# point where the file is still cheap to edit. It is advisory: exit stays 0.

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# write_expectations <ID> <linked_ac line>
write_expectations() {
    local id="$1"
    local link_line="$2"
    cat > "$TMPROOT/datarim/tasks/${id}-expectations.md" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 3
captured_at: 2026-10-19
captured_by: /dr-prd
agent: architect
status: canonical
---

# $id — Expectations

## Ожидания

- **1. Feature works end-to-end.**
  - wish_id: feature-works
  - wish: The feature behaves correctly in all scenarios.
  - success_criterion: The acceptance suite passes.
$link_line
  - evidence_type: static
  - #### status_history
    - 2026-10-19T10:00:00Z / 19.10.2026 13:00 (MSK) · /dr-prd · pending → pending · reason: wish captured
  - #### current_status
    - pending
EOF
}

@test "linked_ac with a single V-AC token: no advisory" {
    write_expectations "LAC-0001" "  - linked_ac: V-AC-1"
    run bash "$CHECK" --task LAC-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"linked-ac-not-vac-token"* ]]
}

@test "linked_ac with several V-AC tokens, including an axis id: no advisory" {
    write_expectations "LAC-0002" "  - linked_ac: V-AC-1, V-AC-A2, V-AC-3.1"
    run bash "$CHECK" --task LAC-0002 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"linked-ac-not-vac-token"* ]]
}

@test "linked_ac no-link dash forms: no advisory" {
    for dash in '—' '«—»' '`—`' '-' '–'; do
        write_expectations "LAC-0003" "  - linked_ac: $dash"
        run bash "$CHECK" --task LAC-0003 --root "$TMPROOT"
        [ "$status" -eq 0 ]
        [[ "$output" != *"linked-ac-not-vac-token"* ]] || {
            echo "dash form flagged: $dash"
            return 1
        }
    done
}

@test "linked_ac with a contract criterion id: advisory naming the token, exit 0" {
    write_expectations "LAC-0004" "  - linked_ac: wish-1-per-route-roles"
    run bash "$CHECK" --task LAC-0004 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVISORY:"*"linked-ac-not-vac-token: feature-works"* ]]
    [[ "$output" == *"wish-1-per-route-roles"* ]]
}

@test "linked_ac mixing a V-AC token and a foreign token: advisory names only the foreign token" {
    write_expectations "LAC-0005" "  - linked_ac: V-AC-1, crit-two"
    run bash "$CHECK" --task LAC-0005 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"linked-ac-not-vac-token"*"crit-two"* ]]
    [[ "$output" != *"V-AC-1)"* ]]
}

@test "localized linked_ac label is normalized before the format check" {
    write_expectations "LAC-0006" "  - Связанный AC из PRD: crit-three"
    run bash "$CHECK" --task LAC-0006 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"linked-ac-not-vac-token"*"crit-three"* ]]
}

@test "verify mode is unaffected by the advisory" {
    write_expectations "LAC-0007" "  - linked_ac: wish-1-per-route-roles"
    run bash "$CHECK" --verify LAC-0007 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

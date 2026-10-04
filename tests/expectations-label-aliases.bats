#!/usr/bin/env bats

setup() {
    REPO="${EXPECTATIONS_TEST_SOURCE:-${BATS_TEST_DIRNAME}/..}"
    CHECK="$REPO/dev-tools/check-expectations-checklist.sh"
    LINT="$REPO/dev-tools/dr-spec-lint.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/tasks" "$WORK/datarim/prd" "$WORK/datarim/plans"
    EXP="$WORK/datarim/tasks/TEST-0001-expectations.md"
    cat > "$EXP" <<'EOF'
---
task_id: TEST-0001
artifact: expectations
schema_version: 3
captured_at: 2026-10-04
captured_by: /dr-prd
agent: architect
status: amended
---
# Generic expectations

## Operator expectations

- **1. Check the generic requirement.**
  - wish_id: generic-requirement
  - How to verify (success criterion): Check independent evidence.
  - Related AC from PRD: V-AC-1
  - evidence_type: static
  - #### Status history
    - 2026-10-04 · /dr-qa · met · reason: Independent check recorded.
  - #### Current status
    - met

## Append-log (operator amendments)

## PRD append-merge

- **2. Check every linked criterion.**
  - wish_id: complete-coverage
  - How to verify (success criterion): Check all linked criteria.
  - Related AC from PRD: V-AC-2, V-AC-3
  - evidence_type: static
  - #### Status history
    - 2026-10-04 · /dr-qa · met · reason: Independent check recorded.
  - #### Current status
    - met
EOF
    cat > "$WORK/datarim/prd/PRD-TEST-0001.md" <<'EOF'
# Generic requirements
**Complexity:** Level 3
#### D-REQ-01: all wishes are represented
#### D-REQ-02: second requirement is represented
#### D-REQ-03: third requirement is represented
- V-AC-1: first requirement
  Covers: D-REQ-01
- V-AC-2: second requirement
  Covers: D-REQ-02
- V-AC-3: third requirement
  Covers: D-REQ-03
EOF
    cat > "$WORK/datarim/plans/TEST-0001-plan.md" <<'EOF'
# Generic plan
- Step 1: check requirements
  Verifies: V-AC-1, V-AC-2, V-AC-3
EOF
    cat > "$WORK/datarim/tasks/TEST-0001-task-description.md" <<'EOF'
# Generic evidence
- Evidence: V-AC-1 — independent check
- Evidence: V-AC-2 — independent check
- Evidence: V-AC-3 — independent check
EOF
}

teardown() { rm -rf -- "$WORK"; }

replace_text() {
    python3 - "$EXP" "$1" "$2" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))
PY
}

@test "English historical labels pass structural and routing validation" {
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ] && [[ "$output" == *PASS* ]]
}

@test "English historical labels retain every graph link including appended multi-AC wishes" {
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c 'source "$1/scripts/lib/spec-graph.sh"; collect_expectation_links "$2"' _ "$REPO" "$EXP"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'complete-coverage\tV-AC-2\tmet\tno'* ]]
    [[ "$output" == *$'complete-coverage\tV-AC-3\tmet\tno'* ]]
}

@test "canonical ASCII labels retain structural and graph behavior" {
    replace_text "Operator expectations" "Expectations"
    replace_text "How to verify (success criterion)" "success_criterion"
    replace_text "Related AC from PRD" "linked_ac"
    replace_text "Status history" "status_history"
    replace_text "Current status" "current_status"
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "localized Expectations marker retains structural and graph behavior" {
    replace_text "## Operator expectations" "## Attentes <!-- datarim:expectations -->"
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "Russian legacy labels retain structural and every graph link" {
    python3 - "$EXP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
for old, new in {
    "Operator expectations": "\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u044f",
    "How to verify (success criterion)": "\u041a\u0430\u043a \u043f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c (success criterion)",
    "Related AC from PRD": "\u0421\u0432\u044f\u0437\u0430\u043d\u043d\u044b\u0439 AC \u0438\u0437 PRD",
    "Status history": "\u0418\u0441\u0442\u043e\u0440\u0438\u044f \u0441\u0442\u0430\u0442\u0443\u0441\u043e\u0432",
    "Current status": "\u0422\u0435\u043a\u0443\u0449\u0438\u0439 \u0441\u0442\u0430\u0442\u0443\u0441",
}.items():
    text = text.replace(old, new)
p.write_text(text)
PY
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "unknown heading aliases are rejected" {
    replace_text "Operator expectations" "Operator hopes"
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ] && [[ "$output" == *"no items"* ]]
}

@test "English labels do not accept an invalid status" {
    replace_text "    - met" "    - complete"
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"status not in enum"* ]]
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ] && [[ "$output" == *BLOCKED* ]]
}

@test "English labels do not accept a missing status or empty history" {
    replace_text "    - met" ""
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *missing*value* ]]
    replace_text "    - 2026-10-04 · /dr-qa · met · reason: Independent check recorded." ""
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ] && [[ "$output" == *"empty"* ]]
}

@test "appended English wish with partial status still blocks routing" {
    replace_text "    - met" "    - partial"
    run "$CHECK" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ] && [[ "$output" == *BLOCKED* ]]
    [[ "$output" == *"complete-coverage"* ]]
}

@test "English graph rejects missing links" {
    replace_text "Related AC from PRD: V-AC-1" "Related AC from PRD: —"
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 1 ] && [[ "$output" == *"no linked V-AC"* ]]
}

@test "English graph rejects wrong later AC in a multi-link wish" {
    replace_text "V-AC-2, V-AC-3" "V-AC-2, V-AC-99"
    run "$LINT" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 1 ] && [[ "$output" == *"undeclared V-AC-99"* ]]
}

@test "English success criterion still triggers the existing unwired-check advisory" {
    replace_text "evidence_type: static" "evidence_type: empirical"
    replace_text "Check independent evidence." "Check HTTP 200 at https://example.invalid/status."
    run "$CHECK" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ] && [[ "$output" == *"verification_mode"* ]]
}

@test "fresh project installation ships the shared normalizer and working validators" {
    # This is an ephemeral test project, with the normal answers-token gate.
    run env XDG_STATE_HOME="$WORK/state" python3 "$REPO/scripts/project_install.py" \
        --project "$WORK" --without-jev --client codex --permissions ask
    [ "$status" -eq 2 ]
    token="$(printf '%s\n' "$output" | sed -nE 's/.*--answers ([0-9a-f]+) <flags>.*/\1/p')"
    [ -n "$token" ]
    run env XDG_STATE_HOME="$WORK/state" python3 "$REPO/scripts/project_install.py" \
        --project "$WORK" --without-jev --client codex --permissions ask --answers "$token"
    [ "$status" -eq 0 ]
    [ -f "$WORK/.datarim-runtime/scripts/lib/expectations_labels.py" ]
    run "$WORK/.datarim-runtime/dev-tools/check-expectations-checklist.sh" \
        --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    run "$WORK/.datarim-runtime/dev-tools/dr-spec-lint.sh" \
        --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "missing shared normalization helper fails closed in both validators" {
    mkdir -p "$WORK/incomplete/scripts/lib" "$WORK/incomplete/dev-tools"
    cp "$REPO/scripts/lib/spec-graph.sh" "$REPO/scripts/lib/schema-regex.sh" \
        "$WORK/incomplete/scripts/lib/"
    cp "$CHECK" "$LINT" "$REPO/dev-tools/dr-spec-rules.yaml" \
        "$WORK/incomplete/dev-tools/"
    run "$WORK/incomplete/dev-tools/check-expectations-checklist.sh" \
        --verify TEST-0001 --root "$WORK"
    [ "$status" -ne 0 ]
    run "$WORK/incomplete/dev-tools/dr-spec-lint.sh" \
        --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *"failed to collect expectation links"* ]]
}

#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_TMPDIR/repo"
  VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/check-ui-dx-evidence.py"
  FIXTURE="$BATS_TEST_DIRNAME/ui-dx-evidence-fixture.py"
  mkdir -p "$ROOT/datarim/qa/synthetic"
  git -C "$ROOT" init -q
  git -C "$ROOT" config user.name Fixture
  git -C "$ROOT" config user.email fixture@example.invalid
  printf 'synthetic source pin\n' > "$ROOT/source.txt"
  git -C "$ROOT" add source.txt
  git -C "$ROOT" commit -qm 'synthetic UI and DX validator fixture'
  python3 "$FIXTURE" clean "$ROOT"
}

run_check() {
  run python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
}

@test "complete synthetic UI and DX evidence passes at exact HEAD" {
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"UI_DX_REVIEW PASS"* ]]
  [[ "$output" == *"lowest_rubric_score=2"* ]]
}

@test "missing UI error state is rejected" {
  python3 "$FIXTURE" missing-ui-error "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_ui_state_error"* ]]
}

@test "missing developer recovery path is rejected" {
  python3 "$FIXTURE" missing-recovery "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_journey_stage_recover"* ]]
}

@test "explicit UI and DX not-applicable results are reported distinctly" {
  python3 "$FIXTURE" not-applicable "$ROOT"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"UI_DX_REVIEW NOT_APPLICABLE"* ]]
}

@test "adoption statistics are rejected" {
  python3 "$FIXTURE" adoption-statistic "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"prohibited_input"* ]]
}

@test "designer binary dependencies are rejected" {
  python3 "$FIXTURE" designer-binary "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"prohibited_input"* ]]
}

@test "retained phrasing without attribution is rejected" {
  python3 "$FIXTURE" unattributed "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unattributed_retained_material"* ]]
}

@test "stale source revision is rejected" {
  python3 "$FIXTURE" stale "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale_source_revision"* ]]
}

@test "changed referenced artifact bytes are rejected" {
  python3 "$FIXTURE" artifact-digest-mismatch "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_digest_mismatch"* ]]
}

@test "design and QA commands consume the fragments without replacing Layer 4h" {
  local design="$BATS_TEST_DIRNAME/../commands/dr-design.md"
  local qa="$BATS_TEST_DIRNAME/../commands/dr-qa.md"
  run grep -F 'skills/frontend-ui/SKILL.md' "$design"
  [ "$status" -eq 0 ]
  run grep -F 'skills/dx-review/SKILL.md' "$qa"
  [ "$status" -eq 0 ]
  run grep -F 'check-ui-dx-evidence.py' "$qa"
  [ "$status" -eq 0 ]
  run grep -F '### Layer 4h — Test-Environment Verification' "$qa"
  [ "$status" -eq 0 ]
  run grep -F 'This check is separate from Layer 4h.' "$qa"
  [ "$status" -eq 0 ]
}

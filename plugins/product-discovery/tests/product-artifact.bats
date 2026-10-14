#!/usr/bin/env bats

CHECKER="$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"
DECISION_V2="$FIXTURES/decision-record-v2"

@test "DecisionRecord v2 validates a continue choice with counterevidence and reversal conditions" {
  run "$CHECKER" --root "$DECISION_V2" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "DecisionRecord v2 refuses GO when the counterevidence section is absent" {
  local candidate
  candidate="$BATS_TEST_TMPDIR/decision-no-counterevidence-$BATS_TEST_NUMBER"
  cp -R "$DECISION_V2" "$candidate"
  python3 - "$candidate/decision.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text().splitlines()
start = lines.index('counterevidence_refs:')
end = start + 1
while end < len(lines) and lines[end].startswith('  - '):
    end += 1
del lines[start:end]
path.write_text('\n'.join(lines) + '\n')
PY
  run "$CHECKER" --root "$candidate" --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_COUNTEREVIDENCE_REQUIRED"* ]]
}

@test "DecisionRecord v2 refuses an empty counterevidence list for GO" {
  local candidate
  candidate="$BATS_TEST_TMPDIR/decision-empty-counterevidence-$BATS_TEST_NUMBER"
  cp -R "$DECISION_V2" "$candidate"
  python3 - "$candidate/decision.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'counterevidence_refs:\n  - {id: raw:SYN-DECISION-COUNTER-002, revision: 1, digest: sha256:da215666f394ffb789ff084685b89e215b1ffdc2807906ecde905f4cf82c2bcb}\n'
assert text.count(old) == 1
path.write_text(text.replace(old, 'counterevidence_refs: []\n'))
PY
  run "$CHECKER" --root "$candidate" --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_COUNTEREVIDENCE_REQUIRED"* ]]
}

@test "DecisionRecord v2 cannot mark authority granted without an authority reference" {
  local candidate
  candidate="$BATS_TEST_TMPDIR/decision-unbound-authority-$BATS_TEST_NUMBER"
  cp -R "$DECISION_V2" "$candidate"
  python3 - "$candidate/decision.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'authority_to_act:\n  status: none\n  authority_ref: null\n'
assert text.count(old) == 1
path.write_text(text.replace(old, 'authority_to_act:\n  status: granted\n  authority_ref: null\n'))
PY
  run "$CHECKER" --root "$candidate" --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_AUTHORITY_REF_REQUIRED"* ]]
}

@test "complete synthetic artifact examples pass together" {
  run "$CHECKER" --root "$FIXTURES/positive/complete" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SK04 groups duplicate source families and preserves an explicit conflict" {
  run "$CHECKER" --root "$FIXTURES/sk04/positive-grouped-conflict" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SK04 rejects contradictory references collapsed onto one source" {
  run "$CHECKER" --root "$FIXTURES/sk04/negative-collapsed-conflict" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = $'opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED\nopportunity.md: E_COUNTEREVIDENCE_DUPLICATE' ]
}

@test "SK04 rejects conflict-group members collapsed onto the supporting side" {
  run "$CHECKER" --root "$FIXTURES/sk04/negative-conflict-same-side" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED" ]
}

@test "SK04 rejects a conflict-group counter-source omitted from the claim" {
  run "$CHECKER" --root "$FIXTURES/sk04/negative-conflict-dropped-counterevidence" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED" ]
}

@test "SK04 rejects a publication date without a matching raw basis reference" {
  run "$CHECKER" --root "$FIXTURES/sk04/negative-guessed-published-at" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "ledger.md: E_PUBLISHED_AT_BASIS_INVALID" ]
}

@test "SK04 keeps an unavailable source distinct from a completed no-match search" {
  run "$CHECKER" --root "$FIXTURES/sk04/negative-unavailable-as-no-match" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "ledger.md: E_SOURCE_UNAVAILABLE_INVALID" ]
}

@test "KC boundary disclaimer is accepted" {
  run "$CHECKER" --root "$FIXTURES/positive/disclaimer" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "affirmative KC self-label phrasings are refused" {
  local idx=0 phrase candidate
  for phrase in \
    "This brief is a Knowledge Contract." \
    "This document constitutes an official Knowledge Contract." \
    "The product artifact serves as a Knowledge Contract." \
    "It is not a Knowledge Contract, but the document is a Knowledge Contract."; do
    idx=$((idx + 1))
    candidate="$BATS_TEST_TMPDIR/affirmative-$idx"
    cp -R "$FIXTURES/positive/disclaimer" "$candidate"
    python3 - "$phrase" "$candidate/opportunity.md" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[2]); s=p.read_text(); old='This brief is not a Knowledge Contract.'
assert s.count(old)==1
p.write_text(s.replace(old,sys.argv[1],1))
PY
    run "$CHECKER" --root "$candidate" --artifact opportunity.md
    [ "$status" -eq 1 ]
    [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
  done
}

@test "observed claim without raw ref emits only E_OBSERVED_RAW_REQUIRED" {
  run "$CHECKER" --root "$FIXTURES/negative/5-5" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_OBSERVED_RAW_REQUIRED" ]
}

@test "user-reported evidence cannot be labeled observed" {
  run "$CHECKER" --root "$FIXTURES/negative/5-6" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_USER_REPORTED_AS_OBSERVED" ]
}

@test "accepted protocol cannot consume a draft hypothesis" {
  run "$CHECKER" --root "$FIXTURES/negative/5-7" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "protocol.md: E_INPUT_NOT_READY" ]
}

@test "input reference to a superseded revision emits E_INPUT_SUPERSEDED" {
  run "$CHECKER" --root "$FIXTURES/negative/input-superseded" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "decision.md: E_INPUT_SUPERSEDED" ]
}

@test "draft artifact with observed claim emits E_DRAFT_OBSERVED_CLAIM" {
  run "$CHECKER" --root "$FIXTURES/negative/draft-observed" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_DRAFT_OBSERVED_CLAIM" ]
}

@test "KC self-label fixture is refused" {
  run "$CHECKER" --root "$FIXTURES/negative/ct12-kc-self-label" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "checker reports usage errors as exit 2" {
  run "$CHECKER" --root "$FIXTURES/positive/complete"
  [ "$status" -eq 2 ]
}

@test "checker refuses an artifact path outside the declared root" {
  run "$CHECKER" --root "$FIXTURES/positive/complete" --artifact "$CHECKER"
  [ "$status" -eq 2 ]
}

@test "--files validates an explicit valid subset" {
  run "$CHECKER" --root "$DECISION_V2" --files decision.md ledger.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--files refuses duplicate entries with usage exit" {
  run "$CHECKER" --root "$DECISION_V2" --files decision.md decision.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate --files entry"* ]]
}

@test "--files refuses a missing entry with usage exit" {
  run "$CHECKER" --root "$DECISION_V2" --files missing.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files refuses a parent traversal entry with usage exit" {
  run "$CHECKER" --root "$DECISION_V2" --files ../decision.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files refuses an absolute path outside the declared root" {
  run "$CHECKER" --root "$DECISION_V2" --files "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files cannot be combined with --bundle" {
  run "$CHECKER" --root "$DECISION_V2" --bundle . --files decision.md
  [ "$status" -eq 2 ]
}

@test "--files cannot be combined with --artifact" {
  run "$CHECKER" --root "$DECISION_V2" --artifact decision.md --files decision.md
  [ "$status" -eq 2 ]
}

#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FLOOR="$REPO_ROOT/dev-tools/dr-verify-floor.sh"
  RUNNER="$REPO_ROOT/dev-tools/self-verify-auto-fix.sh"
  WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  TARGET_REL="datarim/prd/PRD-TUNE-0140.md"
  TARGET="$WORKSPACE/$TARGET_REL"
  MANIFEST="$WORKSPACE/datarim/.auto/manifest.txt"
  FINDING="$WORKSPACE/datarim/.auto/finding.json"
  JOURNAL="$WORKSPACE/datarim/qa/self-verification-auto-fix-transactions"
  HISTORY="$WORKSPACE/datarim/qa/self-verification-auto-fix-history/records"
  mkdir -p "$(dirname "$TARGET")" "$WORKSPACE/datarim/plans" "$WORKSPACE/datarim/tasks" "$WORKSPACE/datarim/.auto"
  : >"$WORKSPACE/.datarim-test-only"
  printf '%s\n' "$TARGET_REL" >"$MANIFEST"
}

teardown() {
  if [ -d "$WORKSPACE" ]; then
    chmod -R u+w "$WORKSPACE" 2>/dev/null || true
  fi
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

write_finding() {
  local source_layer="${1:-floor}"
  local finding_class="${2:-formatting}"
  local detector="${3:-final-newline-detector-v1}"
  local fixer="${4:-final-newline-v1}"
  local line="${5:-null}"
  local digest
  digest="$(sha256_file "$TARGET")"
  python3 - "$FINDING" "$source_layer" "$finding_class" "$detector" "$fixer" "$line" "$digest" "$TARGET_REL" <<'PY'
import json
import sys

path, source_layer, finding_class, detector, fixer, line, digest, target = sys.argv[1:]
record = {
    "finding_id": "F-floor-1",
    "source_layer": source_layer,
    "artifact_ref": target,
    "ac_criteria": [],
    "severity": "low",
    "category": "correctness",
    "evidence": {
        "type": "test_output",
        "source": f"stage_text:{detector}",
        "excerpt": "deterministic stage text finding",
    },
    "check_name": f"stage_text:{detector}",
    "finding_class": finding_class,
    "detector_version": detector,
    "fixer_id": fixer,
    "target": target,
    "preimage_sha256": digest,
    "line": None if line == "null" else int(line),
    "risk_level": "low",
    "sensitivity": "none",
    "deterministic": True,
    "discarded": False,
    "evidence_verified": True,
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
PY
}

set_finding_field() {
  local field="$1"
  local value_json="$2"
  python3 - "$FINDING" "$field" "$value_json" <<'PY'
import json
import sys

path, field, raw = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    record = json.load(handle)
record[field] = json.loads(raw)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
PY
}

seed_history() {
  local false_positive="$1"
  local confirmed="$2"
  local finding_class="${3:-formatting}"
  local detector="${4:-final-newline-detector-v1}"
  local fixer="${5:-final-newline-v1}"
  local index outcome
  mkdir -p "$HISTORY"
  for ((index = 1; index <= false_positive + confirmed; index++)); do
    if [ "$index" -le "$false_positive" ]; then
      outcome="false_positive"
    else
      outcome="confirmed"
    fi
    python3 - "$HISTORY/history-$index.json" "$index" "$outcome" "$finding_class" "$detector" "$fixer" <<'PY'
import json
import sys

path, index, outcome, finding_class, detector, fixer = sys.argv[1:]
record_id = f"history-{index}"
record = {
    "record_id": record_id,
    "finding_id": f"historical-finding-{index}",
    "finding_class": finding_class,
    "detector_version": detector,
    "fixer_id": fixer,
    "outcome": outcome,
    "recorded_at": "2026-07-18T00:00:00Z",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
PY
    chmod 444 "$HISTORY/history-$index.json"
  done
  chmod 555 "$HISTORY"
}

run_runner() {
  run_runner_id hook-0001
}

run_runner_id() {
  local transaction_id="$1"
  run "$RUNNER" \
    --task TUNE-0140 \
    --stage prd \
    --workspace "$WORKSPACE" \
    --finding-file "$FINDING" \
    --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" \
    --transaction-id "$transaction_id"
}

json_field_equals() {
  local payload="$1"
  local field="$2"
  local expected="$3"
  python3 - "$payload" "$field" "$expected" <<'PY'
import json
import sys

payload, field, expected = sys.argv[1:]
actual = json.loads(payload)[field]
raise SystemExit(0 if str(actual).lower() == expected.lower() else 1)
PY
}

@test "floor emits a canonical missing-final-newline finding" {
  printf 'plain text' >"$TARGET"
  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *'"finding_class": "formatting"'* ]] \
    && [[ "$output" == *'"fixer_id": "final-newline-v1"'* ]] \
    && [[ "$output" == *'"artifact_ref": "datarim/prd/PRD-TUNE-0140.md"'* ]] \
    && [[ "$output" == *'"check_name": "stage_text:final-newline-detector-v1"'* ]]
}

@test "floor emits a registered trailing-whitespace lint finding" {
  printf 'first\nsecond  \n' >"$TARGET"
  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *'"finding_class": "lint"'* ]] \
    && [[ "$output" == *'"fixer_id": "trailing-whitespace-v1"'* ]] \
    && [[ "$output" == *'"line": 2'* ]]
}

@test "floor emits a registered exact typo finding" {
  printf 'Please recieve this.\n' >"$TARGET"
  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *'"finding_class": "obvious_typo"'* ]] \
    && [[ "$output" == *'"fixer_id": "typo-receive-v1"'* ]]
}

@test "floor ignores malformed text outside the exact stage artifact" {
  printf 'clean\n' >"$TARGET"
  printf 'recieve  ' >"$WORKSPACE/datarim/prd/PRD-OTHER.md"
  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] \
    && [[ "$output" != *'typo-receive-v1'* ]] \
    && [[ "$output" != *'trailing-whitespace-v1'* ]]
}

@test "floor uses one canonical stage artifact resolver" {
  [ "$(grep -cE '^resolve_stage_artifact\(\)' "$FLOOR")" -eq 1 ] \
    && grep -Fq 'artifact="$(resolve_stage_artifact)"' "$FLOOR"
}

@test "runner rejects a finding not emitted by the floor" {
  printf 'plain text' >"$TARGET"
  write_finding dispatch
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition advisory \
    && json_field_equals "$output" reason_code untrusted_source \
    && json_field_equals "$output" finding_id F-floor-1
}

@test "runner rejects an unverified finding" {
  printf 'plain text' >"$TARGET"
  write_finding
  set_finding_field evidence_verified false
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code ineligible_metadata
}

@test "runner rejects a safety finding" {
  printf 'plain text' >"$TARGET"
  write_finding
  set_finding_field category '"safety"'
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code ineligible_metadata
}

@test "runner rejects elevated risk sensitivity nondeterminism and discarded findings" {
  local field value
  for field in risk_level sensitivity deterministic discarded; do
    printf 'plain text' >"$TARGET"
    write_finding
    case "$field" in
      risk_level) value='"medium"' ;;
      sensitivity) value='"low"' ;;
      deterministic) value='false' ;;
      discarded) value='true' ;;
    esac
    set_finding_field "$field" "$value"
    if [ ! -d "$HISTORY" ]; then
      seed_history 0 1
    fi
    run_runner
    [ "$status" -eq 0 ] \
      && json_field_equals "$output" reason_code ineligible_metadata \
      || return 1
  done
}

@test "runner rejects an unregistered detector and fixer tuple" {
  printf 'plain text' >"$TARGET"
  write_finding floor formatting unregistered-detector-v1 unregistered-fixer-v1
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code unknown_recipe
}

@test "runner rejects path traversal before filesystem resolution" {
  printf 'plain text' >"$TARGET"
  write_finding
  set_finding_field target '"../../outside.md"'
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code invalid_input
}

@test "runner rejects a target absent from the evidence manifest" {
  printf 'plain text' >"$TARGET"
  write_finding
  printf '%s\n' 'datarim/prd/another.md' >"$MANIFEST"
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code target_not_manifested
}

@test "runner rejects a target symlink" {
  local real_target="$BATS_TEST_TMPDIR/real.md"
  printf 'plain text' >"$real_target"
  ln -s "$real_target" "$TARGET"
  write_finding
  seed_history 0 1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code unsafe_target
}

@test "runner rejects stale preimage metadata" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 1
  printf 'changed text' >"$TARGET"
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code stale_preimage
}

@test "runner fails closed when authoritative history is absent" {
  printf 'plain text' >"$TARGET"
  write_finding
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code history_unavailable
}

@test "runner fails closed when authoritative history is writable" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 1
  chmod 755 "$HISTORY"
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code history_unverifiable
}

@test "runner fails closed on a malformed immutable history record" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 1
  chmod 755 "$HISTORY"
  chmod 644 "$HISTORY/history-1.json"
  printf '{"record_id":"history-1"}\n' >"$HISTORY/history-1.json"
  chmod 444 "$HISTORY/history-1.json"
  chmod 555 "$HISTORY"
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code history_unverifiable
}

@test "runner fails closed on duplicate or filename-mismatched history identity" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 2
  chmod 755 "$HISTORY"
  chmod 644 "$HISTORY/history-2.json"
  python3 - "$HISTORY/history-2.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    record = json.load(handle)
record["record_id"] = "history-1"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
PY
  chmod 444 "$HISTORY/history-2.json"
  chmod 555 "$HISTORY"
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code history_unverifiable
}

@test "runner rejects malformed finding identities anywhere in authoritative history" {
  local invalid
  for invalid in '""' '"bad\\u0001id"' '"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; do
    printf 'plain text' >"$TARGET"
    write_finding
    seed_history 0 1
    chmod 755 "$HISTORY"
    chmod 644 "$HISTORY/history-1.json"
    python3 - "$HISTORY/history-1.json" "$invalid" <<'PY'
import json
import sys

path, raw = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    record = json.load(handle)
record["finding_id"] = json.loads(raw)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
PY
    chmod 444 "$HISTORY/history-1.json"
    chmod 555 "$HISTORY"
    run_runner
    [ "$status" -eq 0 ] \
      && json_field_equals "$output" reason_code history_unverifiable \
      || return 1
    chmod -R u+w "$HISTORY"
    rm -rf "$HISTORY"
  done
}

@test "runner rejects an unsupported tuple anywhere in authoritative history" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 1 formatting final-newline-detector-v9 final-newline-v9
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" reason_code history_unverifiable
}

@test "history rate exactly thirty percent stays advisory" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 3 7
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition advisory \
    && json_field_equals "$output" reason_code history_rate_too_high
}

@test "history rate below thirty percent applies final newline transaction" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 2 5
  run_runner
  local final_byte
  final_byte="$(tail -c 1 "$TARGET" | od -An -t u1 | tr -d ' ')"
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && [ "$final_byte" = "10" ] \
    && [ -f "$JOURNAL/prepared-hook-0001.json" ] \
    && [ -f "$JOURNAL/terminal-hook-0001.json" ]
}

@test "two false positives in ten samples remains eligible" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 2 8
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && json_field_equals "$output" history_false_positive 2 \
    && json_field_equals "$output" history_total 10 \
    && json_field_equals "$output" history_rate_basis_points 2000
}

@test "registered trailing-whitespace transaction changes only the selected line" {
  printf 'first  \nsecond  \n' >"$TARGET"
  write_finding floor lint trailing-whitespace-detector-v1 trailing-whitespace-v1 1
  seed_history 0 3 lint trailing-whitespace-detector-v1 trailing-whitespace-v1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && [ "$(sed -n '1p' "$TARGET")" = "first" ] \
    && [ "$(sed -n '2p' "$TARGET")" = "second  " ]
}

@test "registered typo transaction replaces exact whole words only" {
  printf 'recieve receiver recieve\n' >"$TARGET"
  write_finding floor obvious_typo typo-receive-detector-v1 typo-receive-v1 1
  seed_history 0 3 obvious_typo typo-receive-detector-v1 typo-receive-v1
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && [ "$(sed -n '1p' "$TARGET")" = "receive receiver receive" ]
}

@test "prepared transaction replays from the unchanged before image" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_prepared "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ] && [ -f "$JOURNAL/prepared-hook-0001.json" ]

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && [ -f "$JOURNAL/terminal-hook-0001.json" ]
}

@test "prepared transaction recovers after the target replacement boundary" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_target_replace "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ] \
    && [ -f "$JOURNAL/prepared-hook-0001.json" ] \
    && [ ! -e "$JOURNAL/terminal-hook-0001.json" ]

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition already_applied \
    && json_field_equals "$output" postcondition_verified true \
    && [ -f "$JOURNAL/terminal-hook-0001.json" ]
}

@test "valid terminal replay verifies the live after image and full identity" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  run_runner
  [ "$status" -eq 0 ] && json_field_equals "$output" disposition applied

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition already_applied \
    && json_field_equals "$output" postcondition_verified true
}

@test "terminal replay fails closed when identity is corrupt or target is the before image" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  run_runner
  [ "$status" -eq 0 ] && json_field_equals "$output" disposition applied

  chmod u+w "$JOURNAL/terminal-hook-0001.json"
  python3 - "$JOURNAL/terminal-hook-0001.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    terminal = json.load(handle)
terminal["detector_version"] = "wrong-detector-v1"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(terminal, handle)
PY
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition failed \
    && json_field_equals "$output" reason_code journal_conflict

  chmod u+w "$JOURNAL/terminal-hook-0001.json"
  python3 - "$JOURNAL/prepared-hook-0001.json" "$JOURNAL/terminal-hook-0001.json" <<'PY'
import json
import sys

prepared_path, terminal_path = sys.argv[1:]
with open(prepared_path, encoding="utf-8") as handle:
    prepared = json.load(handle)
with open(terminal_path, encoding="utf-8") as handle:
    terminal = json.load(handle)
terminal["detector_version"] = prepared["detector_version"]
with open(terminal_path, "w", encoding="utf-8") as handle:
    json.dump(terminal, handle)
PY
  printf 'plain text' >"$TARGET"
  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition failed \
    && json_field_equals "$output" reason_code journal_conflict
}

@test "prepared replay uses and verifies the original file mode" {
  printf 'plain text' >"$TARGET"
  chmod 640 "$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_prepared "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ]
  chmod 600 "$TARGET"

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition applied \
    && [ "$(stat -c '%a' "$TARGET")" = "640" ]
}

@test "before-image replay rolls back a perturbed postimage" {
  printf 'plain text' >"$TARGET"
  chmod 640 "$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_prepared "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ]

  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_PERTURB=after_target_replace "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition rolled_back \
    && json_field_equals "$output" rollback_verified true \
    && [ "$(cat "$TARGET")" = "plain text" ] \
    && [ "$(stat -c '%a' "$TARGET")" = "640" ]
}

@test "line-scoped replay rejects a changed line identity" {
  printf 'first  \nsecond  \n' >"$TARGET"
  write_finding floor lint trailing-whitespace-detector-v1 trailing-whitespace-v1 1
  seed_history 0 3 lint trailing-whitespace-detector-v1 trailing-whitespace-v1
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_prepared "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ]
  set_finding_field line 2

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition failed \
    && json_field_equals "$output" reason_code journal_conflict \
    && [ "$(sed -n '1p' "$TARGET")" = "first  " ] \
    && [ "$(sed -n '2p' "$TARGET")" = "second  " ]
}

@test "prepared after-image with altered mode rolls back exact bytes and mode" {
  printf 'plain text' >"$TARGET"
  chmod 640 "$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_target_replace "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ]
  chmod 600 "$TARGET"

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition rolled_back \
    && json_field_equals "$output" rollback_verified true \
    && [ "$(cat "$TARGET")" = "plain text" ] \
    && [ "$(stat -c '%a' "$TARGET")" = "640" ]
}

@test "prepared replay fails closed on a neither-image conflict" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  run env DR_AUTOFIX_TEST_MODE=1 DR_AUTOFIX_TEST_FAILPOINT=after_prepared "$RUNNER" \
    --task TUNE-0140 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$FINDING" --manifest "$MANIFEST" \
    --journal-dir "$JOURNAL" --transaction-id hook-0001
  [ "$status" -eq 97 ]
  printf 'third image' >"$TARGET"

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition failed \
    && json_field_equals "$output" reason_code journal_conflict
}

@test "live task-stage lock keeps the transaction advisory" {
  printf 'plain text' >"$TARGET"
  write_finding
  seed_history 0 3
  local lock="$WORKSPACE/datarim/qa/.self-verify-auto-fix-TUNE-0140-prd.lock"
  mkdir -p "$lock"
  printf '{"pid":%s,"transaction_id":"other-0001"}\n' "$$" >"$lock/owner.json"

  run_runner
  [ "$status" -eq 0 ] \
    && json_field_equals "$output" disposition advisory \
    && json_field_equals "$output" reason_code lock_conflict \
    && [ "$(cat "$TARGET")" = "plain text" ]
}

@test "parent-style two-finding loop refreshes evidence and keeps distinct results" {
  local first_floor first_preimage first_result second_floor second_preimage second_result
  printf 'first  \nsecond  \n' >"$TARGET"
  seed_history 0 3 lint trailing-whitespace-detector-v1 trailing-whitespace-v1

  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ]
  first_floor="$output"
  printf '%s\n' "$first_floor" | python3 -c 'import json,sys; rows=[json.loads(line) for line in sys.stdin if line.startswith("{")]; print(json.dumps(next(row for row in rows if row.get("line") == 1)))' >"$FINDING"
  first_preimage="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["preimage_sha256"])' "$FINDING")"
  run_runner_id hook-0001
  [ "$status" -eq 0 ] && json_field_equals "$output" disposition applied
  first_result="$output"

  run "$FLOOR" --task TUNE-0140 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ]
  second_floor="$output"
  printf '%s\n' "$second_floor" | python3 -c 'import json,sys; rows=[json.loads(line) for line in sys.stdin if line.startswith("{")]; print(json.dumps(next(row for row in rows if row.get("line") == 2)))' >"$FINDING"
  second_preimage="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["preimage_sha256"])' "$FINDING")"
  run_runner_id hook-0002
  [ "$status" -eq 0 ] && json_field_equals "$output" disposition applied
  second_result="$output"

  [ "$first_preimage" != "$second_preimage" ] \
    && [ "$(sed -n '1p' "$TARGET")" = "first" ] \
    && [ "$(sed -n '2p' "$TARGET")" = "second" ] \
    && [[ "$first_result" == *'terminal-hook-0001.json'* ]] \
    && [[ "$second_result" == *'terminal-hook-0002.json'* ]]
}

@test "runner rechecks target identity and preimage after acquiring the mutation lock" {
  local locked_body execute_body
  locked_body="$(sed -n '/^def run_locked/,/^def execute_transaction/p' "$RUNNER")"
  execute_body="$(sed -n '/^def execute_transaction/,/^def main/p' "$RUNNER")"
  [[ "$locked_body" == *'locked_digest = revalidate_locked_target(context)'* ]] \
    && [[ "$locked_body" == *'locked_digest != context["finding"].get("preimage_sha256")'* ]] \
    && [[ "$execute_body" == *'owner = acquire_lock(lock_dir, args.transaction_id)'* ]] \
    && [[ "$execute_body" == *'return run_locked(context)'* ]]
}

@test "embedded runner functions stay within method-size and parameter limits" {
  run python3 - "$RUNNER" <<'PY'
import ast
import sys

text = open(sys.argv[1], encoding="utf-8").read()
body = text.split("<<'PY'\n", 1)[1].rsplit("\nPY\n", 1)[0]
tree = ast.parse(body)
oversized = []
overparameterized = []
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        size = node.end_lineno - node.lineno + 1
        if size > 50:
            oversized.append(f"{node.name}:{size}")
        parameters = len(node.args.posonlyargs) + len(node.args.args) + len(node.args.kwonlyargs)
        if parameters > 7:
            overparameterized.append(f"{node.name}:{parameters}")
if oversized or overparameterized:
    print("oversized=" + " ".join(sorted(oversized)))
    print("overparameterized=" + " ".join(sorted(overparameterized)))
    raise SystemExit(1)
PY
  [ "$status" -eq 0 ]
}

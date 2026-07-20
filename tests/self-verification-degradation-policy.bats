#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2089,SC2090

setup() {
  set -e
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  POLICY="$REPO_ROOT/dev-tools/self-verify-degradation-policy.sh"
  FLOOR="$REPO_ROOT/dev-tools/dr-verify-floor.sh"
  AUTOFIX="$REPO_ROOT/dev-tools/self-verify-auto-fix.sh"
  WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  LEDGER_DIR="$WORKSPACE/datarim/.auto/self-verification-budget"
  LEDGER="$LEDGER_DIR/cycle-1.json"
  mkdir -p "$LEDGER_DIR"
  INVOCATION_START="$(date -u -d '2 seconds ago' +%Y-%m-%dT%H:%M:%SZ)"
}

teardown() {
  if [ -d "$WORKSPACE" ]; then
    chmod -R u+w "$WORKSPACE" 2>/dev/null || true
  fi
}

write_ledger() {
  local token_remaining="${1:-96000}"
  local cost_remaining="${2:-none}"
  local source="${3:-runtime_ledger}"
  python3 - "$LEDGER" "$token_remaining" "$cost_remaining" "$source" <<'PY'
import datetime as dt
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
remaining = int(sys.argv[2])
cost_remaining = sys.argv[3]
source = sys.argv[4]
payload = {
    "schema_version": 1,
    "policy_version": "tune-0139-v1",
    "signal_source": source,
    "cycle_id": "cycle-1",
    "task_id": "TUNE-0139",
    "stage": "do",
    "invocation_id": "invocation-1",
    "sequence": 1,
    "observed_at": (dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "tokens": {
        "unit": "tokens",
        "limit": 96000,
        "consumed": 96000 - remaining,
        "reserved": 0,
        "remaining": remaining,
    },
    "roles": {
        name: {"input_bytes": 20000, "estimated_tokens": 9000}
        for name in ("reviewer", "tester", "security")
    },
}
if cost_remaining != "none":
    cost_remaining = int(cost_remaining)
    payload["cost"] = {
        "unit": "microunits",
        "limit": 1000,
        "consumed": 1000 - cost_remaining,
        "reserved": 0,
        "remaining": cost_remaining,
    }
    for role in payload["roles"].values():
        role["estimated_cost_microunits"] = 100
path.write_text(json.dumps(payload), encoding="utf-8")
path.chmod(0o600)
PY
}

mutate_ledger() {
  local statement="$1"
  python3 - "$LEDGER" "$statement" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
exec(sys.argv[2], {"payload": payload})
path.write_text(json.dumps(payload), encoding="utf-8")
path.chmod(0o600)
PY
}

ledger_digest() {
  sha256sum "$LEDGER" | awk '{print $1}'
}

run_policy() {
  run "$POLICY" \
    --workspace "$WORKSPACE" \
    --ledger-file "$LEDGER" \
    --task TUNE-0139 \
    --stage "do" \
    --invocation invocation-1 \
    --cycle cycle-1 \
    --previous-sequence 0 \
    --expected-sequence 1 \
    --expected-digest "$(ledger_digest)" \
    --invocation-start "$INVOCATION_START" "$@"
}

assert_complete_profile() {
  local profile="$1"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *'"execution_status":"complete"'* ]] \
    && [[ "$output" == *"\"selected_profile\":\"$profile\""* ]] \
    && [[ "$output" == *"\"verification_coverage\":\"$profile\""* ]]
}

assert_invalid() {
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'"execution_status":"incomplete"'* ]] \
    && [[ "$output" == *'"reason_code":"invalid_budget_evidence"'* ]] \
    && [[ "$output" == *'"selected_profile":null'* ]]
}

@test "test harness rejects corrupted intermediate output fields" {
  status=0
  output='{"execution_status":"incomplete","selected_profile":"full","verification_coverage":"full"}'
  run assert_complete_profile full
  [ "$status" -ne 0 ] || return 1

  status=1
  output='{"execution_status":"incomplete","reason_code":"wrong","selected_profile":null}'
  run assert_invalid
  [ "$status" -ne 0 ] || return 1
}

@test "V-AC-01: exact full token boundary selects full" {
  write_ledger 27000
  run_policy
  assert_complete_profile full || return 1
  [[ "$output" == *'"trigger_axes":[]'* ]] || return 1
  [[ "$output" == *'"kept_roles":["reviewer","tester","security"]'* ]] || return 1
}

@test "V-AC-02: one token below full drops adversarial bundle first" {
  write_ledger 26999
  run_policy
  assert_complete_profile deep_only || return 1
  [[ "$output" == *'"omitted_passes":["multi_vote_adversarial"]'* ]] || return 1
  [[ "$output" == *'"omitted_roles":["tester","security"]'* ]] || return 1
  [[ "$output" == *'"trigger_axes":["tokens"]'* ]] || return 1
}

@test "V-AC-02: exact deep boundary keeps the reviewer" {
  write_ledger 9000
  run_policy
  assert_complete_profile deep_only || return 1
  [[ "$output" == *'"kept_roles":["reviewer"]'* ]] || return 1
}

@test "V-AC-03: one token below deep drops all model passes but keeps floor" {
  write_ledger 8999
  run_policy
  assert_complete_profile floor_only || return 1
  [[ "$output" == *'"kept_passes":["deterministic_floor"]'* ]] || return 1
  [[ "$output" == *'"omitted_passes":["multi_vote_adversarial","deep_cross_artifact"]'* ]] || return 1
  [[ "$output" == *'"kept_roles":[]'* ]] || return 1
}

@test "V-AC-03: zero remaining is an audited floor-only decision" {
  write_ledger 0
  run_policy
  assert_complete_profile floor_only || return 1
  [[ "$output" == *'"degradation_applied":true'* ]] || return 1
}

@test "V-AC-01: the most restrictive declared axis wins" {
  write_ledger 96000 250
  run_policy
  assert_complete_profile deep_only || return 1
  [[ "$output" == *'"trigger_axes":["cost"]'* ]] || return 1
}

@test "V-AC-05: floor-only records every axis that rejected a stronger profile" {
  write_ledger 8999 250
  run_policy
  assert_complete_profile floor_only || return 1
  [[ "$output" == *'"trigger_axes":["tokens","cost"]'* ]] || return 1
}

@test "V-AC-01: fixed deterministic proxy selects nominal full" {
  write_ledger 96000 none deterministic_proxy
  run_policy
  assert_complete_profile full || return 1
  [[ "$output" == *'"signal_source":"deterministic_proxy"'* ]] || return 1
}

@test "V-AC-04: deterministic proxy cannot manufacture pressure" {
  write_ledger 26999 none deterministic_proxy
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: cost-only evidence is invalid" {
  write_ledger 96000 1000
  mutate_ledger 'payload.pop("tokens")'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: replayed prior and next sequence is invalid" {
  write_ledger
  run "$POLICY" --workspace "$WORKSPACE" --ledger-file "$LEDGER" \
    --task TUNE-0139 --stage "do" --invocation invocation-1 --cycle cycle-1 \
    --previous-sequence 1 --expected-sequence 1 \
    --expected-digest "$(ledger_digest)" --invocation-start "$INVOCATION_START"
  assert_invalid || return 1
}

@test "V-AC-04: wrong digest is invalid" {
  write_ledger
  run_policy --expected-digest aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  assert_invalid || return 1
}

@test "V-AC-04: stale evidence is invalid" {
  write_ledger
  mutate_ledger 'payload["observed_at"] = "2020-01-01T00:00:00Z"'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: future and pre-invocation evidence is invalid" {
  write_ledger
  mutate_ledger 'payload["observed_at"] = "2099-01-01T00:00:00Z"'
  run_policy
  assert_invalid || return 1
  write_ledger
  INVOCATION_START="2099-01-01T00:00:00Z"
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: role token estimate must match the fixed proxy" {
  write_ledger
  mutate_ledger 'payload["roles"]["reviewer"]["estimated_tokens"] = 8999'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: role over the 32000-token ceiling is invalid, not pressure" {
  write_ledger
  mutate_ledger 'payload["roles"]["reviewer"] = {"input_bytes": 112004, "estimated_tokens": 32001}'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: missing cost estimate and aggregate cost overflow are invalid" {
  write_ledger 96000 1000
  mutate_ledger 'payload["roles"]["security"].pop("estimated_cost_microunits")'
  run_policy
  assert_invalid || return 1
  write_ledger 96000 1000
  mutate_ledger 'm=2**63-1; payload["cost"]={"unit":"microunits","limit":m,"consumed":0,"reserved":0,"remaining":m}; [role.update({"estimated_cost_microunits":m}) for role in payload["roles"].values()]'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: bool float negative overflow and bad conservation are invalid" {
  local statement
  for statement in \
    'payload["tokens"]["consumed"] = True' \
    'payload["tokens"]["consumed"] = 1.5' \
    'payload["tokens"]["consumed"] = -1' \
    'payload["tokens"]["consumed"] = 2**63' \
    'payload["tokens"]["limit"] = 95999'; do
    write_ledger
    mutate_ledger "$statement"
    run_policy
    assert_invalid || return 1
  done
}

@test "V-AC-04: unknown and missing schema fields are invalid" {
  write_ledger
  mutate_ledger 'payload["caller_selected_tier"] = "floor_only"'
  run_policy
  assert_invalid || return 1
  write_ledger
  mutate_ledger 'payload.pop("cycle_id")'
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: malformed JSON is invalid" {
  printf '{' > "$LEDGER"
  chmod 0600 "$LEDGER"
  run_policy
  assert_invalid || return 1
}

@test "V-AC-04: writable mode symlink and path escape are invalid" {
  write_ledger
  chmod 0644 "$LEDGER"
  run_policy
  assert_invalid || return 1
  rm -f "$LEDGER"
  printf '{}' > "$BATS_TEST_TMPDIR/outside.json"
  chmod 0600 "$BATS_TEST_TMPDIR/outside.json"
  ln -s "$BATS_TEST_TMPDIR/outside.json" "$LEDGER"
  run_policy
  assert_invalid || return 1
  run "$POLICY" --workspace "$WORKSPACE" --ledger-file "$BATS_TEST_TMPDIR/outside.json" \
    --task TUNE-0139 --stage "do" --invocation invocation-1 --cycle cycle-1 \
    --previous-sequence 0 --expected-sequence 1 \
    --expected-digest "$(sha256sum "$BATS_TEST_TMPDIR/outside.json" | awk '{print $1}')" \
    --invocation-start "$INVOCATION_START"
  assert_invalid || return 1
}

@test "V-AC-04: a replaced ledger cannot reuse the frozen digest" {
  write_ledger
  local frozen
  frozen="$(ledger_digest)"
  mutate_ledger 'payload["tokens"]["remaining"] = 0; payload["tokens"]["consumed"] = 96000'
  run "$POLICY" --workspace "$WORKSPACE" --ledger-file "$LEDGER" \
    --task TUNE-0139 --stage "do" --invocation invocation-1 --cycle cycle-1 \
    --previous-sequence 0 --expected-sequence 1 --expected-digest "$frozen" \
    --invocation-start "$INVOCATION_START"
  assert_invalid || return 1
}

@test "V-AC-04: every required option is enforced and unknown options are misuse" {
  write_ledger
  run "$POLICY" --unknown-option value
  [ "$status" -eq 2 ] || return 1
  local option skip argument
  local -a base_args missing_args
  base_args=(
    --workspace "$WORKSPACE"
    --ledger-file "$LEDGER"
    --task TUNE-0139
    --stage "do"
    --invocation invocation-1
    --cycle cycle-1
    --previous-sequence 0
    --expected-sequence 1
    --expected-digest "$(ledger_digest)"
    --invocation-start "$INVOCATION_START"
  )
  for option in workspace ledger-file task stage invocation cycle previous-sequence expected-sequence expected-digest invocation-start; do
    missing_args=()
    skip=0
    for argument in "${base_args[@]}"; do
      if [ "$skip" -eq 1 ]; then
        skip=0
        continue
      fi
      if [ "$argument" = "--$option" ]; then
        skip=1
        continue
      fi
      missing_args+=("$argument")
    done
    run "$POLICY" "${missing_args[@]}"
    [ "$status" -eq 2 ] || return 1
  done
}

@test "V-AC-05: complete output is audit-ready and redacted" {
  write_ledger 26999 250
  run_policy
  assert_complete_profile deep_only || return 1
  local field
  for field in policy_version base_profile selected_profile verification_coverage degradation_applied signal_source signal_digest signal_sequence budget_axes role_estimates kept_passes omitted_passes kept_roles omitted_roles trigger_axes reason_code reason; do
    [[ "$output" == *"\"$field\""* ]] || return 1
  done
  if printf '%s' "$output" | grep -Eqi 'ledger-file|workspace|account|provider|session|bearer|prompt|endpoint|cycle-1|invocation-1'; then
    return 1
  fi
}

@test "V-AC-09: implementation contains descriptor identity and no-follow controls" {
  grep -Fq 'O_NOFOLLOW' "$POLICY" || return 1
  grep -Fq 'os.fstat' "$POLICY" || return 1
  grep -Fq 'st_ino' "$POLICY" || return 1
  grep -Fq 'st_dev' "$POLICY" || return 1
}

@test "V-AC-06: policy consumes refreshed floor state after an eligible auto-fix" {
  local target_rel="datarim/prd/PRD-TUNE-0139.md"
  local target="$WORKSPACE/$target_rel"
  local manifest="$WORKSPACE/datarim/.auto/manifest.txt"
  local finding="$WORKSPACE/datarim/.auto/finding.json"
  local history="$WORKSPACE/datarim/qa/self-verification-auto-fix-history/records"
  local journal="$WORKSPACE/datarim/qa/self-verification-auto-fix-transactions"
  mkdir -p "$(dirname "$target")" "$WORKSPACE/datarim/plans" "$WORKSPACE/datarim/tasks" "$history"
  : > "$WORKSPACE/.datarim-test-only"
  printf 'plain text' > "$target"
  printf '%s\n' "$target_rel" > "$manifest"

  run "$FLOOR" --task TUNE-0139 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *'"fixer_id": "final-newline-v1"'* ]] || return 1
  printf '%s\n' "$output" | python3 -c 'import json,sys; rows=[json.loads(line) for line in sys.stdin if line.lstrip().startswith("{")]; print(json.dumps(next(row for row in rows if row.get("fixer_id") == "final-newline-v1")))' > "$finding"
  python3 - "$history" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for index in range(1, 4):
    record = {
        "record_id": f"history-{index}",
        "finding_id": f"historical-finding-{index}",
        "finding_class": "formatting",
        "detector_version": "final-newline-detector-v1",
        "fixer_id": "final-newline-v1",
        "outcome": "confirmed",
        "recorded_at": "2026-07-18T00:00:00Z",
    }
    path = root / f"history-{index}.json"
    path.write_text(json.dumps(record), encoding="utf-8")
    path.chmod(0o444)
root.chmod(0o555)
PY
  run "$AUTOFIX" --task TUNE-0139 --stage prd --workspace "$WORKSPACE" \
    --finding-file "$finding" --manifest "$manifest" --journal-dir "$journal" \
    --transaction-id invocation-1-fix-1
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *'"disposition":"applied"'* ]] || return 1

  run "$FLOOR" --task TUNE-0139 --stage prd --workspace "$WORKSPACE"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *'"fixer_id": "final-newline-v1"'* ]] || return 1
  python3 - "$finding" "$target" <<'PY'
import hashlib
import json
import pathlib
import sys

finding = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
target = pathlib.Path(sys.argv[2]).read_bytes()
raise SystemExit(0 if finding["preimage_sha256"] != hashlib.sha256(target).hexdigest() else 1)
PY
  write_ledger 26999
  run_policy
  assert_complete_profile deep_only || return 1
}

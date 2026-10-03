#!/usr/bin/env bash
# Run the sorted recursive dr-orchestrate Bats manifest with count/skip guards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  echo 'usage: check-orchestrate-regression.sh --baseline-files N --minimum-files N --baseline-tests N [--allow-skip redis-unavailable]' >&2
  exit 2
}

BASELINE_FILES=""; MINIMUM_FILES=""; BASELINE_TESTS=""; ALLOW_SKIP=""
while (( $# > 0 )); do
  case "$1" in
    --baseline-files) BASELINE_FILES="${2:-}"; shift 2 ;;
    --minimum-files) MINIMUM_FILES="${2:-}"; shift 2 ;;
    --baseline-tests) BASELINE_TESTS="${2:-}"; shift 2 ;;
    --allow-skip) ALLOW_SKIP="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
for value in "$BASELINE_FILES" "$MINIMUM_FILES" "$BASELINE_TESTS"; do
  [[ "$value" =~ ^[0-9]+$ ]] || usage
done
[[ -z "$ALLOW_SKIP" || "$ALLOW_SKIP" == redis-unavailable ]] || usage
(( MINIMUM_FILES >= BASELINE_FILES )) || { echo "FAIL: minimum-files is below baseline-files" >&2; exit 1; }

REGRESSION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dr-orchestrate-regression.XXXXXX")"
cleanup() {
  tmux kill-server >/dev/null 2>&1 || true
  rm -rf -- "$REGRESSION_TMP"
}
trap cleanup EXIT
export HOME="$REGRESSION_TMP/home"
export XDG_CONFIG_HOME="$REGRESSION_TMP/config"
export TMUX_TMPDIR="$REGRESSION_TMP/tmux"
unset TMUX
unset AUDIT_DIR STATE_DIR DR_ORCH_STATE_DIR DR_ORCH_RULES_USER DR_ORCH_RULES_LEARNED
unset DR_ORCH_PROPOSALS_DIR DR_ORCH_TOMBSTONES_DIR DR_ORCH_DELIVERY_DIR DR_ORCH_LEARNED_AUDIT
unset DR_ORCH_PROPOSAL_MOCK_LOG DR_ORCH_PROPOSAL_QUEUE DR_ORCH_ACTION_EXECUTOR_LOG
unset DR_ORCH_AUTONOMY_AUDIT DR_AUTONOMY_AUDIT DR_ORCH_FB_RULES DR_AUTONOMY_RULES
unset DATARIM_SPACES_ROOT DATARIM_ACTIVE_SPACE PHASE3_NETWORK_LOG
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$TMUX_TMPDIR"
chmod 700 "$HOME" "$XDG_CONFIG_HOME" "$TMUX_TMPDIR"

TEST_ROOT="${DR_ORCH_REGRESSION_TEST_ROOT:-$ROOT/plugins/dr-orchestrate/tests}"
BATS_BIN="${DR_ORCH_BATS_BIN:-$(command -v bats || true)}"
[[ -d "$TEST_ROOT" && -x "$BATS_BIN" ]] || { echo "FAIL: test root or Bats executable unavailable" >&2; exit 1; }

mapfile -t bats_files < <(LC_ALL=C find "$TEST_ROOT" -type f -name '*.bats' -print | LC_ALL=C sort)
file_count="${#bats_files[@]}"
(( file_count >= BASELINE_FILES && file_count >= MINIMUM_FILES )) || {
  echo "FAIL: recursive Bats files=$file_count baseline=$BASELINE_FILES minimum=$MINIMUM_FILES" >&2
  exit 1
}

required_raw="${DR_ORCH_REQUIRED_PHASE3_SUITES:-test_resolver_history.bats:test_learned_rules.bats}"
IFS=: read -r -a required_suites <<<"$required_raw"
for required in "${required_suites[@]}"; do
  found=0
  for file in "${bats_files[@]}"; do
    [[ "$file" == */"$required" || "$file" == "$TEST_ROOT/$required" ]] && { found=1; break; }
  done
  (( found == 1 )) || { echo "FAIL: required Phase 3 suite missing: $required" >&2; exit 1; }
done

test_count=0
for file in "${bats_files[@]}"; do
  count="$(LC_ALL=C grep -cE '^[[:space:]]*@test[[:space:]]+' "$file" || true)"
  (( count > 0 )) || { echo "FAIL: zero-test Bats file: $file" >&2; exit 1; }
  test_count=$((test_count + count))
done
(( test_count > BASELINE_TESTS )) || {
  echo "FAIL: recursive tests=$test_count must exceed baseline=$BASELINE_TESTS" >&2
  exit 1
}

tap="$REGRESSION_TMP/regression.tap"
set +e
"$BATS_BIN" --tap "${bats_files[@]}" >"$tap" 2>&1
bats_status=$?
set -e
cat "$tap"
(( bats_status == 0 )) || { echo "FAIL: recursive Bats run exited $bats_status" >&2; exit 1; }

while IFS= read -r skip_line; do
  [[ -n "$skip_line" ]] || continue
  if [[ "$ALLOW_SKIP" != redis-unavailable ]] \
    || ! grep -Eiq 'redis' <<<"$skip_line"; then
    echo "FAIL: unapproved skip: $skip_line" >&2
    exit 1
  fi
done < <(grep -Ei '^ok [0-9]+ .*# skip' "$tap" || true)

echo "PASS: recursive_files=$file_count recursive_tests=$test_count baseline_files=$BASELINE_FILES baseline_tests=$BASELINE_TESTS"

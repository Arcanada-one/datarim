#!/usr/bin/env bash
# Measure the observed false-positive rate on a fixed deterministic corpus.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../plugins/dr-orchestrate/tests/helpers/phase3-env.bash
source "$ROOT/plugins/dr-orchestrate/tests/helpers/phase3-env.bash"

usage() {
  echo "usage: check-escape-false-positives.sh --iterations <positive-integer>" >&2
  exit 2
}

ITERATIONS=""
while (( $# > 0 )); do
  case "$1" in
    --iterations) ITERATIONS="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || usage
(( ITERATIONS <= 100000 )) || { echo "FAIL: iterations exceeds deterministic safety cap" >&2; exit 1; }

phase3_env_setup
trap phase3_env_cleanup EXIT
SECURITY="$PHASE3_PLUGIN_ROOT/scripts/security.sh"
[[ -x "$SECURITY" ]] || { echo "FAIL: security helper is not executable" >&2; exit 1; }
# shellcheck source=../plugins/dr-orchestrate/scripts/security.sh
source "$SECURITY"

CANARY="$PHASE3_ENV_ROOT/escape-canary"
malicious=(
  $'\x1b[31mred\x1b[0m'
  $'\x1b]0;title\x07'
  $'\x1bP1;2|payload\x1b\\'
  $'prefix\x1b[2Jsuffix'
  $'\x1b]0;$(touch '"$CANARY"$')\x07'
)
for payload in "${malicious[@]}"; do
  if check_escape "$payload" >/dev/null 2>&1; then
    echo "FAIL: malicious escape fixture was accepted" >&2
    exit 1
  fi
done
[[ ! -e "$CANARY" ]] || { echo "FAIL: escape fixture produced a side effect" >&2; exit 1; }

false_positives=0
for ((i = 1; i <= ITERATIONS; i++)); do
  safe="/dr-plan TUNE-$((100000 + i)) safe_case_$i"
  if ! check_escape "$safe" >/dev/null 2>&1 \
    || ! check_whitelist "$safe" >/dev/null 2>&1; then
    false_positives=$((false_positives + 1))
  fi
done

printf 'iterations=%d false_positives=%d observed_rate=%d/%d fixed_corpus_only=true population_confidence_claim=false\n' \
  "$ITERATIONS" "$false_positives" "$false_positives" "$ITERATIONS"
(( false_positives == 0 ))

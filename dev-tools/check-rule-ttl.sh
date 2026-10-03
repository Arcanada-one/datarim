#!/usr/bin/env bash
# Verify learned-rule TTL and re-validation boundaries without wall-clock sleep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../plugins/dr-orchestrate/tests/helpers/phase3-env.bash
source "$ROOT/plugins/dr-orchestrate/tests/helpers/phase3-env.bash"

usage() {
  echo "usage: check-rule-ttl.sh --ttl <seconds> --revalidate <seconds>" >&2
  exit 2
}

TTL=""; REVALIDATE=""
while (( $# > 0 )); do
  case "$1" in
    --ttl) TTL="${2:-}"; shift 2 ;;
    --revalidate) REVALIDATE="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$TTL" =~ ^[1-9][0-9]*$ && "$REVALIDATE" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$TTL" == 604800 && "$REVALIDATE" == 86400 ]] || {
  echo "FAIL: Phase 3 requires ttl=604800 and revalidate=86400" >&2
  exit 1
}

phase3_env_setup
trap phase3_env_cleanup EXIT
LOADER="$PHASE3_PLUGIN_ROOT/scripts/rules_loader.sh"
LIFECYCLE="$PHASE3_PLUGIN_ROOT/scripts/learned_rules.sh"
[[ -x "$LOADER" && -x "$LIFECYCLE" ]] || {
  echo "FAIL: learned-rule loader/lifecycle is not executable" >&2
  exit 1
}

NOW=2000000000
export DR_ORCH_NOW_EPOCH="$NOW"
HASH="$(printf 'phase3-ttl' | shasum -a 256 | awk '{print $1}')"

write_boundary_rules() {
  cat >"$DR_ORCH_RULES_LEARNED" <<YAML
patterns:
  - match: "fresh rule"
    action: "/dr-plan"
    confidence: 0.95
    created_at: $((NOW - REVALIDATE))
    last_validated_at: $((NOW - REVALIDATE + 1))
    expires_at: $((NOW + TTL - REVALIDATE))
    proposal_hash: "$HASH"
    generation: "$HASH"
  - match: "due rule"
    action: "/dr-plan"
    confidence: 0.95
    created_at: $((NOW - REVALIDATE))
    last_validated_at: $((NOW - REVALIDATE))
    expires_at: $((NOW + TTL - REVALIDATE))
    proposal_hash: "$HASH"
    generation: "$HASH"
  - match: "expired rule"
    action: "/dr-plan"
    confidence: 0.95
    created_at: $((NOW - TTL))
    last_validated_at: $((NOW - REVALIDATE + 1))
    expires_at: $NOW
    proposal_hash: "$HASH"
    generation: "$HASH"
YAML
  chmod 600 "$DR_ORCH_RULES_LEARNED"
}

assert_boundary_loads() {
  local active inactive
  active="$(bash "$LOADER" load)"
  inactive="$(bash "$LOADER" load_inactive_learned)"
  [[ "$(jq -r '[.[] | select(.provenance=="learned") | .match] | sort | join(",")' <<<"$active")" == "fresh rule" ]] || return 1
  [[ "$(jq -r '[.[].match] | sort | join(",")' <<<"$inactive")" == "due rule,expired rule" ]] || return 1
}

assert_purge_and_renewed_load() {
  bash "$LIFECYCLE" maintenance >/dev/null
  [[ "$(yq -r '[.patterns[] | select(.match=="expired rule")] | length' "$DR_ORCH_RULES_LEARNED")" == 0 ]] || return 1
  yq -i '(.patterns[] | select(.match=="due rule") | .last_validated_at) = env(DR_ORCH_NOW_EPOCH)' \
    "$DR_ORCH_RULES_LEARNED"
  local active
  active="$(bash "$LOADER" load)"
  [[ "$(jq -r '[.[] | select(.provenance=="learned") | .match] | sort | join(",")' <<<"$active")" == "due rule,fresh rule" ]] || return 1
}

write_boundary_rules
assert_boundary_loads || { echo "FAIL: exact due/expiry boundary was not fail-closed" >&2; exit 1; }
assert_purge_and_renewed_load || { echo "FAIL: purge or renewed-rule load contract failed" >&2; exit 1; }
echo "PASS: ttl=$TTL revalidate=$REVALIDATE boundaries=fresh,due,expired sleep_calls=0"

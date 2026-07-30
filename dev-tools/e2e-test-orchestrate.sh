#!/usr/bin/env bash
# Hermetic Phase 3 intent-to-mock-notification acceptance workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../plugins/dr-orchestrate/tests/helpers/phase3-env.bash
source "$ROOT/plugins/dr-orchestrate/tests/helpers/phase3-env.bash"

usage() {
  echo 'usage: e2e-test-orchestrate.sh --intent <text> --expect-audit --expect-telegram' >&2
  exit 2
}

INTENT=""; EXPECT_AUDIT=0; EXPECT_TELEGRAM=0
while (( $# > 0 )); do
  case "$1" in
    --intent) INTENT="${2:-}"; shift 2 ;;
    --expect-audit) EXPECT_AUDIT=1; shift ;;
    --expect-telegram) EXPECT_TELEGRAM=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "$INTENT" && "$INTENT" != -* && "$INTENT" != *$'\n'* && ${#INTENT} -le 256 ]] || usage
(( EXPECT_AUDIT == 1 && EXPECT_TELEGRAM == 1 )) || usage

phase3_env_setup
trap phase3_env_cleanup EXIT
LIFECYCLE="$PHASE3_PLUGIN_ROOT/scripts/learned_rules.sh"
PARSER="$PHASE3_PLUGIN_ROOT/scripts/semantic_parser.sh"
GATE="$PHASE3_PLUGIN_ROOT/scripts/action_gate.sh"
RUNNER="$PHASE3_PLUGIN_ROOT/scripts/cmd_run.sh"
for dependency in "$LIFECYCLE" "$PARSER" "$GATE" "$RUNNER"; do
  [[ -x "$dependency" ]] || { echo "FAIL: missing executable integration dependency: $dependency" >&2; exit 1; }
done

cat >"$PHASE3_ENV_ROOT/bin/dr-orch-mock-e2e" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' '{"action":"/dr-plan","confidence":0.95,"reason":"e2e fixture"}'
MOCK
chmod 700 "$PHASE3_ENV_ROOT/bin/dr-orch-mock-e2e"
export DR_ORCH_SUBAGENT_CHAIN=mock-e2e

# An omitted action_kind must first normalize to framework_command and traverse
# the immutable space gate. Prove deny-before-executor ordering before enabling
# the same hermetic space for the successful cycle.
sed -i 's/cross_project_write: auto/cross_project_write: operator/' \
  "$DATARIM_SPACES_ROOT/phase3-test/space.yml"
blocked_output="$(bash "$RUNNER" --pane phase3-missing:0.0 --unknown-prompt "$INTENT")"
[[ "$blocked_output" == *"reason=space_policy"* ]] || {
  echo "FAIL: inferred action_kind fallback did not gate before execution" >&2
  exit 1
}
[[ ! -s "$DR_ORCH_ACTION_EXECUTOR_LOG" ]] || {
  echo "FAIL: space-denied inference reached the executor" >&2
  exit 1
}
[[ ! -d "$DR_ORCH_DELIVERY_DIR" \
  || -z "$(find "$DR_ORCH_DELIVERY_DIR" -maxdepth 1 -type f -print -quit)" ]] || {
  echo "FAIL: space-denied inference created a proposal" >&2
  exit 1
}
sed -i 's/cross_project_write: operator/cross_project_write: auto/' \
  "$DATARIM_SPACES_ROOT/phase3-test/space.yml"

# The first cycle is intentionally a parser miss. It must traverse the actual
# inference -> gate -> controlled executor -> proposal integration path.
bash "$RUNNER" --pane phase3-missing:0.0 --unknown-prompt "$INTENT" >/dev/null
notification="$(find "$DR_ORCH_DELIVERY_DIR" -maxdepth 1 -type f -name '*.json' -print -quit)"
proposal_id="$(jq -r '.proposal_id // .callback_id // .id // empty' "$notification")"
[[ "$proposal_id" =~ ^[A-Za-z0-9_-]{16,256}$ ]] || {
  echo "FAIL: proposal did not emit a bounded opaque callback ID" >&2
  exit 1
}
[[ -n "$notification" && -s "$notification" ]] || { echo "FAIL: mock notification was not emitted" >&2; exit 1; }
jq -e --arg id "$proposal_id" '.proposal_id==$id and (.prompt|type=="string")' "$notification" >/dev/null || {
  echo "FAIL: mock notification is not bound to the callback ID" >&2
  exit 1
}

bash "$LIFECYCLE" consume_callback "$proposal_id" Y \
  "$DR_ORCH_ACTOR" "$DR_ORCH_SESSION_CONTEXT" >/dev/null
decision="$(bash "$PARSER" parse "$INTENT")"
[[ "$(jq -r '.action' <<<"$decision")" == /dr-plan \
  && "$(jq -r '.provenance' <<<"$decision")" == learned ]] || {
  echo "FAIL: affirmative callback did not create an exact learned hit" >&2
  exit 1
}

payload="$(jq -n -c --arg command /dr-plan '{command:$command}')"
bash "$GATE" gate --action framework_command --payload "$payload" >/dev/null
: >"$DR_ORCH_ACTION_EXECUTOR_LOG"
DR_ORCH_PANE_CAPTURE_OVERRIDE="$INTENT" \
  bash "$RUNNER" --pane "$SESSION_NAME:0.0" >/dev/null
[[ "$(tail -n 1 "$DR_ORCH_ACTION_EXECUTOR_LOG")" == /dr-plan ]] || {
  echo "FAIL: controlled executor seam did not receive /dr-plan" >&2
  exit 1
}
[[ -z "$(find "$DR_ORCH_DELIVERY_DIR" -maxdepth 1 -type f -name '*.json' -print -quit)" ]] || {
  echo "FAIL: active learned hit emitted a redundant proposal" >&2
  exit 1
}

audit_file="$(find "$AUDIT_DIR" -maxdepth 1 -type f -name 'audit-*.jsonl' -print -quit)"
[[ -n "$audit_file" && -s "$audit_file" ]] || { echo "FAIL: cycle audit was not written" >&2; exit 1; }
jq -e -s 'any(.[]; .event=="cycle_checkpoint" and .phase=="prepare") and
  any(.[]; .event=="cycle_checkpoint" and .phase=="terminal") and
  any(.[]; .event=="learned_rule_prepare") and
  any(.[]; .event=="learned_rule_commit") and
  any(.[]; .outcome=="resolved")' "$audit_file" >/dev/null || {
  echo "FAIL: canonical audit lacks cycle, learned mutation, or resolved evidence" >&2
  exit 1
}
! grep -Fq -- "$proposal_id" "$audit_file" || { echo "FAIL: raw callback ID leaked into audit" >&2; exit 1; }
[[ ! -s "$PHASE3_NETWORK_LOG" ]] || { echo "FAIL: workflow attempted a network client" >&2; exit 1; }

echo "PASS: intent_to_proposal_to_callback_to_learned_hit_to_gate_to_executor_to_audit_to_mock_notification"

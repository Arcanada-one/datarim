#!/usr/bin/env bash
# dr-orchestrate-soak.sh — V-AC-22 soak harness traffic driver.
#
# Drives mixed traffic against `dr-orchestrate run` so the audit sink emits
# schema_v2 outcome/stage/reason events that `measure-orchestrator-soak.sh`
# can verdict. Replaces the legacy passive harness that only invoked
# `cmd_run.sh` no-op and never exercised semantic_parser / escalation_backend
# (see TUNE-0209 / INFRA-0138).
#
# Each cycle picks one of three modes by weighted random draw:
#   resolved   — slash-command prompt from RESOLVED_PROMPTS corpus (parser hits)
#   escalated  — non-slash text from ESCALATED_PROMPTS corpus (parser misses → subagent → escalation)
#   noop       — invoke cmd_run.sh with no args (legacy pane-capture path)
#
# Defaults: 70/20/10 resolved/escalated/noop, 5s cycle sleep, 48h deadline.
# Tune via env knobs:
#   DR_SOAK_DURATION_HOURS  — soak deadline in hours (default 48; integer)
#   DR_SOAK_DURATION_SECONDS — soak deadline in seconds (overrides HOURS; for smoke runs)
#   DR_SOAK_CYCLE_SLEEP     — seconds between cycles (default 5)
#   DR_SOAK_W_RESOLVED      — relative weight resolved corpus (default 70)
#   DR_SOAK_W_ESCALATED     — relative weight escalated corpus (default 20)
#   DR_SOAK_W_NOOP          — relative weight no-op mode (default 10)
#   DR_SOAK_CMD             — path to cmd_run.sh
#   DR_SOAK_AUDIT_DIR       — exported as DR_ORCH_AUDIT_DIR for child
#
# Reuses Bash $RANDOM (0..32767). Threading: single-process loop, no parallelism.
# Exit codes from cmd_run.sh are logged but never abort the soak (per legacy
# behavior — soak measures distribution, not individual call success).
#
# Owner: framework. Origin: TUNE-0209 (replaces ad-hoc /usr/local/bin wrapper
# created at INFRA-0137 soak launch). Install: see § Deploy at file bottom.

set -u

DURATION_HOURS="${DR_SOAK_DURATION_HOURS:-48}"
DURATION_SECONDS="${DR_SOAK_DURATION_SECONDS:-}"
CYCLE_SLEEP="${DR_SOAK_CYCLE_SLEEP:-5}"
W_RESOLVED="${DR_SOAK_W_RESOLVED:-70}"
W_ESCALATED="${DR_SOAK_W_ESCALATED:-20}"
W_NOOP="${DR_SOAK_W_NOOP:-10}"
CMD="${DR_SOAK_CMD:-/opt/datarim/plugins/dr-orchestrate/scripts/cmd_run.sh}"

if [[ -n "${DR_SOAK_AUDIT_DIR:-}" ]]; then
  export DR_ORCH_AUDIT_DIR="$DR_SOAK_AUDIT_DIR"
fi

W_SUM=$((W_RESOLVED + W_ESCALATED + W_NOOP))
if (( W_SUM <= 0 )); then
  echo "[soak] ERR weights sum to 0; refusing to start" >&2
  exit 2
fi
if [[ ! -x "$CMD" ]]; then
  echo "[soak] ERR CMD '$CMD' missing or not executable" >&2
  exit 2
fi

RESOLVED_PROMPTS=(
  "/dr-status"
  "/dr-help"
  "/dr-init"
  "/dr-prd"
  "/dr-plan"
  "/dr-do"
  "/dr-qa"
  "/dr-archive"
  "/dr-continue"
  "/dr-design"
  "/dr-compliance"
  "please run /dr-status"
  "run /dr-help now"
  "/dr-do please"
)

ESCALATED_PROMPTS=(
  "hello world"
  "random text foo bar"
  "what is the weather today"
  "summarize this for me"
  "не уверен что делать"
  "explain quantum entanglement briefly"
  "abc"
  "how do I configure this"
  "tell me a joke"
)

if [[ -n "$DURATION_SECONDS" ]]; then
  DEADLINE_EPOCH=$(( $(date +%s) + DURATION_SECONDS ))
else
  DEADLINE_EPOCH=$(( $(date +%s) + DURATION_HOURS * 3600 ))
fi
DEADLINE_ISO=$(date -u -d "@$DEADLINE_EPOCH" +%FT%TZ 2>/dev/null \
              || date -u -r "$DEADLINE_EPOCH" +%FT%TZ 2>/dev/null \
              || echo "+$DURATION_HOURS h")

echo "[soak] start pid=$$ deadline=$DEADLINE_ISO cmd=$CMD weights=$W_RESOLVED/$W_ESCALATED/$W_NOOP sleep=${CYCLE_SLEEP}s"

cycle=0
while [ "$(date +%s)" -lt "$DEADLINE_EPOCH" ]; do
  cycle=$((cycle + 1))
  ts=$(date -u +%FT%TZ)
  draw=$(( RANDOM % W_SUM ))
  if (( draw < W_RESOLVED )); then
    mode=resolved
    idx=$(( RANDOM % ${#RESOLVED_PROMPTS[@]} ))
    prompt="${RESOLVED_PROMPTS[$idx]}"
  elif (( draw < W_RESOLVED + W_ESCALATED )); then
    mode=escalated
    idx=$(( RANDOM % ${#ESCALATED_PROMPTS[@]} ))
    prompt="${ESCALATED_PROMPTS[$idx]}"
  else
    mode=noop
    prompt=""
  fi

  echo "[soak] $ts cycle-begin n=$cycle mode=$mode"
  if [[ "$mode" == "noop" ]]; then
    "$CMD" >/dev/null 2>&1
    ec=$?
  else
    "$CMD" --unknown-prompt "$prompt" >/dev/null 2>&1
    ec=$?
  fi
  echo "[soak] $(date -u +%FT%TZ) cycle-end n=$cycle mode=$mode exit=$ec"

  sleep "$CYCLE_SLEEP"
done

echo "[soak] $(date -u +%FT%TZ) deadline reached, exiting after $cycle cycles"

# Deploy:
#   scp dev-tools/dr-orchestrate-soak.sh root@arcana-dev:/usr/local/bin/
#   ssh root@arcana-dev 'chmod 0755 /usr/local/bin/dr-orchestrate-soak.sh'
# Launch (detached):
#   ssh root@arcana-dev 'setsid /usr/local/bin/dr-orchestrate-soak.sh \
#       >>/var/log/dr-orchestrate-soak.log 2>&1 </dev/null & disown'
# Verdict after window:
#   ssh root@arcana-dev '/opt/datarim/dev-tools/measure-orchestrator-soak.sh \
#       --since 48h --max-false-escalate 0.15 --verbose'

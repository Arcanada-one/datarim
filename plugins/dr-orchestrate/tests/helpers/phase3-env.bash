#!/usr/bin/env bash
# Hermetic Phase 3 acceptance environment. Source this file, then call
# phase3_env_setup; phase3_env_cleanup removes only the generated fixture.

phase3_env_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P
}

phase3_env_write_space() {
  cat >"$DATARIM_SPACES_ROOT/phase3-test/space.yml" <<'YAML'
space:
  name: phase3-test
autonomy:
  schema_version: 1
  policy:
    cross_project_write: auto
    verify: auto
YAML
}

phase3_env_write_network_stubs() {
  local tool
  for tool in curl wget nc ncat ssh scp; do
    printf '%s\n' '#!/usr/bin/env bash' \
      'printf "%s\\n" "$(basename "$0") $*" >> "${PHASE3_NETWORK_LOG:?}"' \
      'exit 97' >"$PHASE3_ENV_ROOT/bin/$tool"
    chmod 700 "$PHASE3_ENV_ROOT/bin/$tool"
  done
}

phase3_env_setup() {
  local parent="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  PHASE3_REPO_ROOT="${PHASE3_REPO_ROOT:-$(phase3_env_repo_root)}"
  PHASE3_PLUGIN_ROOT="${PHASE3_PLUGIN_ROOT:-$PHASE3_REPO_ROOT/plugins/dr-orchestrate}"
  PHASE3_ENV_ROOT="$(mktemp -d "$parent/dr-orchestrate-phase3.XXXXXX")"
  export PHASE3_REPO_ROOT PHASE3_PLUGIN_ROOT PHASE3_ENV_ROOT

  export HOME="$PHASE3_ENV_ROOT/home"
  export XDG_CONFIG_HOME="$PHASE3_ENV_ROOT/config"
  export DATARIM_RUNTIME="$PHASE3_REPO_ROOT"
  export DR_ORCH_DIR="$PHASE3_PLUGIN_ROOT"
  export AUDIT_DIR="$PHASE3_ENV_ROOT/audit"
  export DR_ORCH_STATE_DIR="$PHASE3_ENV_ROOT/state"
  export STATE_DIR="$DR_ORCH_STATE_DIR"
  export DR_ORCH_RULES_DEFAULT="$PHASE3_PLUGIN_ROOT/rules/default.yaml"
  export DR_ORCH_RULES_USER="$XDG_CONFIG_HOME/dr-orchestrate/rules/user.yaml"
  export DR_ORCH_RULES_LEARNED="$DR_ORCH_STATE_DIR/learned-rules.yaml"
  DR_ORCH_AUDIT_FILE="$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"
  export DR_ORCH_AUDIT_FILE
  export DR_ORCH_PROPOSALS_DIR="$DR_ORCH_STATE_DIR/learned-rule-proposals"
  export DR_ORCH_TOMBSTONES_DIR="$DR_ORCH_STATE_DIR/learned-rule-tombstones"
  export DR_ORCH_DELIVERY_DIR="$DR_ORCH_STATE_DIR/learned-rule-delivery"
  export DR_ORCH_LEARNED_AUDIT="$DR_ORCH_AUDIT_FILE"
  export DR_ORCH_PROPOSAL_MOCK_LOG="$DR_ORCH_STATE_DIR/proposals.jsonl"
  export DR_ORCH_PROPOSAL_QUEUE="$DR_ORCH_STATE_DIR/proposal-queue.jsonl"
  export DR_ORCH_ACTION_EXECUTOR_LOG="$DR_ORCH_STATE_DIR/executor.log"
  export DR_ORCH_AUTONOMY_AUDIT="$DR_ORCH_STATE_DIR/autonomy.jsonl"
  export DR_AUTONOMY_AUDIT="$DR_ORCH_AUTONOMY_AUDIT"
  export DATARIM_SPACES_ROOT="$PHASE3_ENV_ROOT/spaces"
  export DATARIM_ACTIVE_SPACE=phase3-test
  export DR_ORCH_FB_RULES="$PHASE3_ENV_ROOT/autonomy/fb-rules.yaml"
  export DR_AUTONOMY_RULES="$DR_ORCH_FB_RULES"
  export DR_ORCH_USER_CONFIG="$XDG_CONFIG_HOME/dr-orchestrate/user-config.yaml"
  export DR_ORCH_ACTOR=phase3-actor
  export DR_ORCH_SESSION_CONTEXT=phase3-session
  export SESSION_NAME=phase3-session
  export DR_ORCH_NOW_EPOCH="${DR_ORCH_NOW_EPOCH:-2000000000}"
  export DR_ORCH_PROPOSAL_BACKEND=mock
  export DR_ORCH_OUTBOUND_BACKEND=mock
  export TMUX_TMPDIR="$PHASE3_ENV_ROOT/tmux"
  export PHASE3_NETWORK_LOG="$PHASE3_ENV_ROOT/network.log"
  unset TMUX

  mkdir -p "$HOME" "$AUDIT_DIR" "$DR_ORCH_STATE_DIR" "$TMUX_TMPDIR" \
    "$(dirname "$DR_ORCH_RULES_USER")" "$(dirname "$DR_ORCH_USER_CONFIG")" \
    "$DATARIM_SPACES_ROOT/phase3-test" "$PHASE3_ENV_ROOT/autonomy" \
    "$PHASE3_ENV_ROOT/bin"
  chmod 700 "$HOME" "$AUDIT_DIR" "$DR_ORCH_STATE_DIR" "$TMUX_TMPDIR"
  printf 'patterns: []\n' >"$DR_ORCH_RULES_USER"
  printf '{}\n' >"$DR_ORCH_USER_CONFIG"
  cp "$PHASE3_REPO_ROOT/dev-tools/rules/fb-rules.yaml" "$DR_ORCH_FB_RULES"
  phase3_env_write_space
  : >"$PHASE3_NETWORK_LOG"
  : >"$DR_ORCH_ACTION_EXECUTOR_LOG"
  phase3_env_write_network_stubs
  export PATH="$PHASE3_ENV_ROOT/bin:$PATH"
}

phase3_env_cleanup() {
  if [[ -n "${PHASE3_ENV_ROOT:-}" && -d "$PHASE3_ENV_ROOT" ]]; then
    tmux kill-server >/dev/null 2>&1 || true
    rm -rf -- "$PHASE3_ENV_ROOT"
  fi
}

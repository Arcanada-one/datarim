#!/usr/bin/env bats

SYSTEM_CODEX_HOME="${DR_ORCH_SYSTEM_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export ADAPTER="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"
  export SETUP="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_window_setup.sh"
  export CONTROLLER="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_window_controller.sh"
  export DR_ORCH_CONTEXT_STATE="$BATS_TEST_TMPDIR/state"
  export DR_ORCH_CONTEXT_TRUST_ROOT="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CODEX_HOME="$HOME/.codex"
  export DR_ORCH_SKIP_RUNTIME_PROBE=1
  export DR_ORCH_ACTIVE_TASK=TUNE-0167
  export DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR"
  chmod 700 "$BATS_TEST_TMPDIR"
  mkdir -p "$DR_ORCH_CONTEXT_STATE" "$CODEX_HOME"
  chmod 700 "$DR_ORCH_CONTEXT_STATE" "$HOME" "$CODEX_HOME"
}

bind_instance() {
  local instance="$1" pid="$2" incarnation
  incarnation="$(jq -r .incarnation "$DR_ORCH_CONTEXT_STATE/instances/$instance.meta.json")"
  bash "$SETUP" bind-process "$instance" "$incarnation" "$pid"
}

trust_generated_codex_profile() {
  local profile="$CODEX_HOME/datarim-orchestrate-context.config.toml" response="" count="" key hash profile_key attempt
  cp "$profile" "$CODEX_HOME/config.toml"; chmod 600 "$CODEX_HOME/config.toml"
  for attempt in 1 2 3 4 5; do
    response="$({ printf '%s\n' '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"tune0167_test","title":"TUNE test","version":"1"}}}' '{"method":"initialized"}' "{\"method\":\"hooks/list\",\"id\":1,\"params\":{\"cwds\":[\"$REPO_ROOT\"]}}"; sleep 1; } | codex app-server 2>/dev/null | jq -c 'select(.id==1)' || true)"
    count="$(jq -r '.result.data[0].hooks|length' <<<"$response" 2>/dev/null || true)"; [ "$count" = 2 ] && break
  done
  [ "$count" = 2 ] || { printf 'ERR: Codex hooks/list did not return two generated hooks after %s attempts\n' "$attempt" >&2; return 1; }
  : >"$CODEX_HOME/config.toml"
  while IFS=$'\t' read -r key hash; do
    profile_key="${key/$CODEX_HOME\/config.toml/$profile}"
    printf '[hooks.state.%s]\ntrusted_hash = %s\n' "$(jq -Rn --arg v "$profile_key" '$v')" "$(jq -Rn --arg v "$hash" '$v')" >>"$CODEX_HOME/config.toml"
  done < <(jq -r '.result.data[0].hooks[] | [.key,.currentHash] | @tsv' <<<"$response")
  chmod 600 "$CODEX_HOME/config.toml"
}

@test "claude null pressure is no action" {
  run bash "$ADAPTER" normalize-claude-pressure --json '{"context_window":{"used_percentage":null}}'
  [ "$status" -eq 3 ] && [ -z "$output" ]
}

@test "claude fractional pressure rounds up" {
  run bash "$ADAPTER" normalize-claude-pressure --json '{"context_window":{"used_percentage":74.01}}'
  [ "$status" -eq 0 ] && [ "$output" = 75 ]
}

@test "claude pressure boundary and invalid-value matrix is fail closed" {
  for pair in '0 0' '49 49' '50 50' '74 74' '74.01 75' '75 75' '89 89' '89.01 90' '90 90' '100 100'; do
    set -- $pair
    actual="$(bash "$ADAPTER" normalize-claude-pressure --json "{\"context_window\":{\"used_percentage\":$1}}")"
    [ "$actual" = "$2" ]
  done
  for value in -1 101 '"NaN"' '"Infinity"' '"-Infinity"'; do
    run bash "$ADAPTER" normalize-claude-pressure --json "{\"context_window\":{\"used_percentage\":$value}}"
    [ "$status" -ne 0 ]
  done
}

@test "claude nonnumeric pressure is rejected" {
  run bash "$ADAPTER" normalize-claude-pressure --json '{"context_window":{"used_percentage":"90"}}'
  [ "$status" -ne 0 ]
}

@test "codex checked ratio rounds up" {
  run bash "$ADAPTER" normalize-codex-pressure --total 741 --window 1000
  [ "$status" -eq 0 ] && [ "$output" = 75 ]
}

@test "codex exact ratio remains exact" {
  run bash "$ADAPTER" normalize-codex-pressure --total 900 --window 1000
  [ "$status" -eq 0 ] && [ "$output" = 90 ]
}

@test "codex usage above window is rejected" {
  run bash "$ADAPTER" normalize-codex-pressure --total 1001 --window 1000
  [ "$status" -ne 0 ]
}

@test "codex large checked ratio does not lose integer precision" {
  run bash "$ADAPTER" normalize-codex-pressure --total 5849999999999999 --window 8999999999999999
  [ "$status" -eq 0 ] && [ "$output" = 65 ]
}

@test "setup requires both trust flags" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: false\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude
  [ "$status" -ne 0 ]
}

@test "setup rejects trust-only opt in" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: false\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" install --runtime claude
  [ "$status" -ne 0 ]
}

@test "setup rejects key-injection-only opt in" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: false\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" install --runtime claude
  [ "$status" -ne 0 ]
}

@test "config and taught-policy path adversaries fail closed" {
  safe="$BATS_TEST_TMPDIR/safe"; mkdir "$safe"; chmod 700 "$safe"; cfg="$safe/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude; [ "$status" -eq 0 ]
  chmod 640 "$cfg"; run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude; [ "$status" -ne 0 ]; chmod 600 "$cfg"
  ln "$cfg" "$safe/config-hard.yaml"; run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude; [ "$status" -ne 0 ]; rm "$safe/config-hard.yaml"
  mv "$cfg" "$safe/config-real.yaml"; ln -s "$safe/config-real.yaml" "$cfg"; run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude; [ "$status" -ne 0 ]; rm "$cfg"; mv "$safe/config-real.yaml" "$cfg"
  chmod 770 "$safe"; run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime claude; [ "$status" -ne 0 ]; chmod 700 "$safe"
  policy="$safe/policy.tsv"; printf 'deep\tfull_clear\t90\001\n' >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=deep bash "$CONTROLLER" evaluate --used-percent 90
  [ "$status" -ne 0 ]
}

@test "setup renders private Claude overlay without changing global config" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" install --runtime claude
  [ "$status" -eq 0 ] && [ -f "$DR_ORCH_CONTEXT_STATE/config/context-window-hooks.claude.json" ] && [ ! -e "$HOME/.claude/settings.json" ]
}

@test "setup renders uniquely named Codex profile" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime codex
  [ "$status" -eq 0 ] && [ -f "$CODEX_HOME/datarim-orchestrate-context.config.toml" ]
}

@test "installed Codex resolves the profile canary and strict TUI without a prompt" {
  command -v codex >/dev/null && command -v tmux >/dev/null || skip "installed Codex and tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  run env -u DR_ORCH_SKIP_RUNTIME_PROBE DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime codex
  [ "$status" -eq 0 ] && [[ "$output" == *"datarim-orchestrate-context.config.toml"* ]]
}

@test "setup rejects a symlinked Codex profile destination" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; victim="$BATS_TEST_TMPDIR/victim"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  : >"$victim"; ln -s "$victim" "$CODEX_HOME/datarim-orchestrate-context.config.toml"
  run env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime codex
  [ "$status" -ne 0 ] && [ ! -s "$victim" ]
}

@test "pane retirement requires proof and removes only the owned mapping" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  output="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-7 bash "$SETUP" install --runtime claude)"
  instance="$(printf '%s\n' "$output" | awk -F= '$1=="instance"{print $2}')"
  sleep 5 & process=$!; bind_instance "$instance" "$process"
  map="$DR_ORCH_CONTEXT_STATE/active/pane-7.map"
  run bash "$SETUP" retire --pane pane-7
  [ "$status" -ne 0 ] && [ "$(cat "$map")" = "$instance" ]
  kill "$process"; wait "$process" 2>/dev/null || true
  run bash "$SETUP" retire --pane pane-7
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; return 1; fi
  [ ! -e "$map" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$instance.retired" ]
}

@test "cap-16 same-pane replacement consumes only its proven-dead old slot" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-0 bash "$SETUP" install --runtime claude)"; old="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  sleep 5 & process=$!; bind_instance "$old" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  for n in $(seq 1 15); do env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE="pane-$n" bash "$SETUP" install --runtime claude >/dev/null; done
  before="$BATS_TEST_TMPDIR/other-fifteen.before"
  for n in $(seq 1 15); do i="$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-$n.map")"; sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-$n.map" "$DR_ORCH_CONTEXT_STATE/instances/$i.cap" "$DR_ORCH_CONTEXT_STATE/instances/$i.meta.json"; done >"$before"
  run env DR_ORCH_TEST_FAIL_REPLACE_AFTER=map_commit DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-0 bash "$SETUP" install --runtime claude
  [ "$status" -ne 0 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.meta.json' | wc -l)" -eq 16 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.cap' | wc -l)" -eq 16 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/active" -name '*.map' | wc -l)" -eq 16 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/replacements" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
  logical_instances="$(for file in "$DR_ORCH_CONTEXT_STATE"/instances/*.meta.json "$DR_ORCH_CONTEXT_STATE"/replacements/*/rollback-metadata.json; do [ -f "$file" ] && jq -r '.instance' "$file"; done | sort -u | wc -l)"
  [ "$logical_instances" -eq 16 ] && [ "$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-0.map")" = "$old" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$old.replaced" ] && [ -f "$DR_ORCH_CONTEXT_STATE/replacements/$old/old-claim.json" ]
  run bash -c 'source "$1"; marker="$2"; cap="$3"; payload="$(mktemp)"; jq -c .payload "$marker" >"$payload"; [ "$(ctx_hmac "$cap" "$payload")" = "$(jq -r .tag "$marker")" ]; rc=$?; rm -f "$payload"; exit "$rc"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/lib/context-window-state.sh" "$DR_ORCH_CONTEXT_STATE/instances/$old.replaced" "$DR_ORCH_CONTEXT_STATE/instances/$old.cap"
  [ "$status" -eq 0 ]
  bash "$SETUP" retire --pane pane-0; bash "$SETUP" doctor >/dev/null
  replacement="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-0 bash "$SETUP" install --runtime claude)"; new="$(printf '%s\n' "$replacement" | awk -F= '$1=="instance"{print $2}')"
  after="$BATS_TEST_TMPDIR/other-fifteen.after"
  for n in $(seq 1 15); do i="$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-$n.map")"; sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-$n.map" "$DR_ORCH_CONTEXT_STATE/instances/$i.cap" "$DR_ORCH_CONTEXT_STATE/instances/$i.meta.json"; done >"$after"
  [ "$new" != "$old" ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.cap' | wc -l)" -eq 16 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/active" -name '*.map' | wc -l)" -eq 16 ]
  cmp -s "$before" "$after"
  [ ! -e "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json" ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/instances/$old.retired-key" ]
  run env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-16 bash "$SETUP" install --runtime claude
  [ "$status" -ne 0 ]
}

@test "dead orchestrator pane is replaced under the lifecycle proof path" {
  command -v tmux >/dev/null || skip "tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; agent_exit="$BATS_TEST_TMPDIR/mock-exit"; agent_live="$BATS_TEST_TMPDIR/mock-live"; session="ctx-replace-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$agent_exit"; printf '#!/usr/bin/env bash\nsleep 30\n' >"$agent_live"; chmod 700 "$agent_exit" "$agent_live"
  env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_RUNTIME=claude DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" \
    bash -c 'source "$1"; session_spawn_interactive "$2" "$3"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session" "$agent_exit"
  pane="$(tmux display-message -p -t "$session" '#{pane_id}')"; map="$DR_ORCH_CONTEXT_STATE/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; old="$(cat "$map")"
  for _ in $(seq 1 30); do [ "$(tmux display-message -p -t "$session" '#{pane_dead}')" = 1 ] && break; sleep 0.05; done
  env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_RUNTIME=claude DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" \
    bash -c 'source "$1"; session_spawn_interactive "$2" "$3"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session" "$agent_live"
  new="$(cat "$map")"
  replaced=0; [ "$new" = "$old" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$old.replaced" ] && [ "$(tmux display-message -p -t "$session" '#{pane_dead}')" = 0 ] && replaced=1
  env DR_ORCH_USER_CONFIG="$cfg" bash -c 'source "$1"; session_close "$2"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session"
  [ "$replaced" -eq 1 ]
}

@test "a zombie process is terminal for replacement proof" {
  [ -r /proc/self/stat ] || skip "procfs process state required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-zombie bash "$SETUP" install --runtime claude)"; instance="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  perl -e '$child=fork(); if (!$child) { sleep 20; exit 0 } print "$child\n"; $|=1; sleep 20' >"$BATS_TEST_TMPDIR/zombie.pid" & keeper=$!
  for _ in $(seq 1 40); do [ -s "$BATS_TEST_TMPDIR/zombie.pid" ] && zombie="$(cat "$BATS_TEST_TMPDIR/zombie.pid")" && break; sleep 0.05; done
  [ "${zombie:-}" != "" ]; bind_instance "$instance" "$zombie"; kill "$zombie"
  for _ in $(seq 1 40); do [ "$(awk '{print $3}' "/proc/$zombie/stat" 2>/dev/null)" = Z ] && break; sleep 0.05; done
  [ "$(awk '{print $3}' "/proc/$zombie/stat")" = Z ]
  run env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-zombie bash "$SETUP" install --runtime claude
  kill "$keeper" 2>/dev/null || true; wait "$keeper" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "same-slot replacement rejects a stale hook incarnation" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-incarnation DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" bash "$SETUP" install --runtime claude)"
  instance="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"; old_incarnation="$(printf '%s\n' "$first" | awk -F= '$1=="incarnation"{print $2}')"
  sleep 5 & process=$!; bind_instance "$instance" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  second="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-incarnation DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" bash "$SETUP" install --runtime claude)"
  new_incarnation="$(printf '%s\n' "$second" | awk -F= '$1=="incarnation"{print $2}')"; [ "$new_incarnation" != "$old_incarnation" ]
  run bash "$SETUP" bind-process "$instance" "$old_incarnation" "$$"
  [ "$status" -ne 0 ] && [ "$(jq -r .runtime_bound "$DR_ORCH_CONTEXT_STATE/instances/$instance.meta.json")" = false ]
  bind_instance "$instance" "$$"
  binding=(DR_ORCH_CONTEXT_INSTANCE="$instance" DR_ORCH_CONTEXT_PANE=pane-incarnation DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR")
  run env "${binding[@]}" DR_ORCH_CONTEXT_INCARNATION="$old_incarnation" bash "$ADAPTER" ingest-claude --kind status --json '{"session_id":"stale","context_window":{"used_percentage":50}}'
  [ "$status" -ne 0 ]
  run env "${binding[@]}" DR_ORCH_CONTEXT_INCARNATION="$new_incarnation" bash "$ADAPTER" ingest-claude --kind status --json '{"session_id":"current","context_window":{"used_percentage":50}}'
  [ "$status" -eq 0 ] && [ "$(jq -r .incarnation "$DR_ORCH_CONTEXT_STATE/instances/$instance.pressure.json")" = "$new_incarnation" ]
}

@test "same-pane replacement rolls back every pre-commit fault" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-fault bash "$SETUP" install --runtime claude)"; old="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  sleep 5 & process=$!; bind_instance "$old" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  for fault in old_key new_cap new_meta; do
    before="$(sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-fault.map" "$DR_ORCH_CONTEXT_STATE/instances/$old.cap" "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json")"
    run env DR_ORCH_TEST_FAIL_REPLACE_AFTER="$fault" DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-fault bash "$SETUP" install --runtime claude
    [ "$status" -ne 0 ] && [ "$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-fault.map")" = "$old" ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.cap' | wc -l)" -eq 1 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.meta.json' | wc -l)" -eq 1 ]
    [ "$before" = "$(sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-fault.map" "$DR_ORCH_CONTEXT_STATE/instances/$old.cap" "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json")" ]
  done
  run env DR_ORCH_TEST_FAIL_REPLACE_AFTER=map_commit DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-fault bash "$SETUP" install --runtime claude
  [ "$status" -ne 0 ]; committed="$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-fault.map")"; [ "$committed" = "$old" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$committed.meta.json" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$committed.replaced" ]
  run bash -c 'source "$1"; old_claim="$2"; old_cap="$3"; marker="$4"; new_cap="$5"; op="$(mktemp)"; np="$(mktemp)"; jq -c .payload "$old_claim" >"$op"; jq -c .payload "$marker" >"$np"; [ "$(ctx_hmac "$old_cap" "$op")" = "$(jq -r .tag "$old_claim")" ] && [ "$(ctx_hmac "$new_cap" "$np")" = "$(jq -r .tag "$marker")" ] && [ "$(ctx_sha256 "$old_claim")" = "$(jq -r .payload.old_claim_digest "$marker")" ]; rc=$?; rm -f "$op" "$np"; exit "$rc"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/lib/context-window-state.sh" "$DR_ORCH_CONTEXT_STATE/replacements/$old/old-claim.json" "$DR_ORCH_CONTEXT_STATE/replacements/$old/rollback-capability" "$DR_ORCH_CONTEXT_STATE/instances/$old.replaced" "$DR_ORCH_CONTEXT_STATE/instances/$old.cap"
  [ "$status" -eq 0 ]
  bash "$SETUP" doctor >/dev/null
  [ ! -e "$DR_ORCH_CONTEXT_STATE/replacements/$old" ] && [ -f "$DR_ORCH_CONTEXT_STATE/instances/$old.replaced-old" ]
  run bash "$SETUP" retire --pane pane-fault
  [ "$status" -eq 0 ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/active/pane-fault.map" ]
}

@test "prepare and replacement serialize without stranding a retired transaction" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; workspace="$BATS_TEST_TMPDIR/workspace"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks"; chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; chmod 600 "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"; chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-race DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" bash "$SETUP" install --runtime claude)"; old="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  sleep 5 & process=$!; bind_instance "$old" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  incarnation="$(jq -r .incarnation "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json")"
  bash "$CONTROLLER" prepare --task TUNE-0167 --workspace "$workspace" --runtime claude --instance "$old" --incarnation "$incarnation" --pane pane-race --conversation conv-race --mode full_clear >"$BATS_TEST_TMPDIR/prepare.out" 2>/dev/null & p1=$!
  env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-race DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" bash "$SETUP" install --runtime claude >"$BATS_TEST_TMPDIR/replace.out" 2>/dev/null & p2=$!
  s1=1; s2=1; wait "$p1" && s1=0; wait "$p2" && s2=0
  [ "$((s1 + s2))" -eq 1 ]
  [ "$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-race.map")" = "$old" ] && [ -e "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json" ]
}

@test "doctor restores a real pre-commit replacement crash before reporting ready" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-precommit bash "$SETUP" install --runtime claude)"; instance="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  cap="$DR_ORCH_CONTEXT_STATE/instances/$instance.cap"; meta="$DR_ORCH_CONTEXT_STATE/instances/$instance.meta.json"; before="$(sha256sum "$cap" "$meta")"
  stage="$DR_ORCH_CONTEXT_STATE/replacements/$instance"; mkdir "$stage"; chmod 700 "$stage"
  payload="$BATS_TEST_TMPDIR/old-claim-payload"; envelope="$stage/old-claim.json"; jq -n -c --arg instance "$instance" '{kind:"instance_replacement_claim",instance:$instance}' >"$payload"; chmod 600 "$payload"
  tag="$(bash -c 'source "$1"; ctx_hmac "$2" "$3"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/lib/context-window-state.sh" "$cap" "$payload")"; jq -n -c --slurpfile payload "$payload" --arg tag "$tag" '{payload:$payload[0],tag:$tag}' >"$envelope"; chmod 600 "$envelope"
  mv "$cap" "$stage/rollback-capability"; mv "$meta" "$stage/rollback-metadata.json"
  run bash "$SETUP" doctor
  [ "$status" -eq 0 ] && [[ "$output" == *"context_window_state=ready"* ]] && [ ! -e "$stage" ] && [ "$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-precommit.map")" = "$instance" ]
  [ "$before" = "$(sha256sum "$cap" "$meta")" ]
}

@test "retired instance cap evicts exact insertion-oldest record under timestamp ties" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  first=""; second=""
  for n in $(seq 1 16); do
    out="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE="pane-oldest-$n" bash "$SETUP" install --runtime claude)"; instance="$(printf '%s\n' "$out" | awk -F= '$1=="instance"{print $2}')"
    [ "$n" -ne 1 ] || first="$instance"; [ "$n" -ne 2 ] || second="$instance"
    bash "$SETUP" retire --pane "pane-oldest-$n"
  done
  run env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-oldest-new bash "$SETUP" install --runtime claude
  [ "$status" -eq 0 ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/instances/$first.meta.json" ] && [ -e "$DR_ORCH_CONTEXT_STATE/instances/$second.meta.json" ]
}

@test "prepare and retirement serialize without stranding a retired transaction" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; workspace="$BATS_TEST_TMPDIR/workspace"; printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks"; chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; chmod 600 "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"; chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  first="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-retire-race DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" bash "$SETUP" install --runtime claude)"; old="$(printf '%s\n' "$first" | awk -F= '$1=="instance"{print $2}')"
  sleep 5 & process=$!; bind_instance "$old" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  incarnation="$(jq -r .incarnation "$DR_ORCH_CONTEXT_STATE/instances/$old.meta.json")"
  bash "$CONTROLLER" prepare --task TUNE-0167 --workspace "$workspace" --runtime claude --instance "$old" --incarnation "$incarnation" --pane pane-retire-race --conversation conv-race --mode full_clear >"$BATS_TEST_TMPDIR/prepare.out" 2>/dev/null & p1=$!
  bash "$CONTROLLER" retire --instance "$old" --pane pane-retire-race >"$BATS_TEST_TMPDIR/retire.out" 2>/dev/null & p2=$!
  s1=1; s2=1; wait "$p1" && s1=0; wait "$p2" && s2=0
  [ "$((s1 + s2))" -eq 1 ]
  if [ "$s1" -eq 0 ]; then [ "$(cat "$DR_ORCH_CONTEXT_STATE/active/pane-retire-race.map")" = "$old" ]; else [ ! -e "$DR_ORCH_CONTEXT_STATE/active/pane-retire-race.map" ]; fi
}

@test "stale recovery requires a distinct epoch from a live tmux witness" {
  command -v tmux >/dev/null || skip "tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; old_epoch=11111111111111111111111111111111; new_epoch=22222222222222222222222222222222; label="ctx-recovery-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  output="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-recovery DR_ORCH_CONTEXT_EPOCH="$old_epoch" DR_ORCH_CONTEXT_SOCKET="$BATS_TEST_TMPDIR/missing.sock" bash "$SETUP" install --runtime claude)"
  instance="$(printf '%s\n' "$output" | awk -F= '$1=="instance"{print $2}')"; sleep 5 & process=$!; bind_instance "$instance" "$process"; kill "$process"; wait "$process" 2>/dev/null || true
  tmux -L "$label" new-session -d -s witness 'sleep 30'; socket="$(tmux -L "$label" display-message -p -t witness '#{socket_path}')"; tmux -S "$socket" set-option -g @datarim_context_epoch "$old_epoch"
  run env DR_ORCH_CONTEXT_TMUX_SOCKET="$socket" bash "$SETUP" doctor --recover-stale-instances
  [ "$status" -ne 0 ] && [ -f "$DR_ORCH_CONTEXT_STATE/active/pane-recovery.map" ]
  tmux -S "$socket" set-option -g @datarim_context_epoch "$new_epoch"
  run env DR_ORCH_CONTEXT_TMUX_SOCKET="$socket" bash "$SETUP" doctor --recover-stale-instances
  tmux -S "$socket" kill-server 2>/dev/null || true
  [ "$status" -eq 0 ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/active/pane-recovery.map" ]
}

@test "stale recovery accepts pane-id reuse only with a new live epoch" {
  command -v tmux >/dev/null || skip "tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; old_epoch=33333333333333333333333333333333; new_epoch=44444444444444444444444444444444; old_label="ctx-old-$$"; new_label="ctx-new-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  tmux -L "$old_label" new-session -d -s old 'sleep 30'; old_socket="$(tmux -L "$old_label" display-message -p -t old '#{socket_path}')"; pane="$(tmux -S "$old_socket" display-message -p -t old '#{pane_id}')"; tmux -S "$old_socket" set-option -g @datarim_context_epoch "$old_epoch"
  output="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE="$pane" DR_ORCH_CONTEXT_EPOCH="$old_epoch" DR_ORCH_CONTEXT_SOCKET="$old_socket" bash "$SETUP" install --runtime claude)"; instance="$(printf '%s\n' "$output" | awk -F= '$1=="instance"{print $2}')"; old_pid="$(tmux -S "$old_socket" display-message -p -t "$pane" '#{pane_pid}')"; bind_instance "$instance" "$old_pid"; tmux -S "$old_socket" kill-server
  tmux -L "$new_label" new-session -d -s new 'sleep 30'; new_socket="$(tmux -L "$new_label" display-message -p -t new '#{socket_path}')"; reused="$(tmux -S "$new_socket" display-message -p -t new '#{pane_id}')"; tmux -S "$new_socket" set-option -g @datarim_context_epoch "$new_epoch"
  run env DR_ORCH_CONTEXT_TMUX_SOCKET="$new_socket" bash "$SETUP" doctor --recover-stale-instances
  tmux -S "$new_socket" kill-server 2>/dev/null || true
  [ "$status" -eq 0 ] && [ "$reused" = "$pane" ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map" ]
}

@test "mixed recovery retires stale records and preserves live records byte-exactly" {
  command -v tmux >/dev/null || skip "tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; old_epoch=55555555555555555555555555555555; new_epoch=66666666666666666666666666666666; label="ctx-mixed-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  stale_out="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-a-stale DR_ORCH_CONTEXT_EPOCH="$old_epoch" DR_ORCH_CONTEXT_SOCKET="$BATS_TEST_TMPDIR/missing.sock" bash "$SETUP" install --runtime claude)"; stale="$(printf '%s\n' "$stale_out" | awk -F= '$1=="instance"{print $2}')"; sleep 5 & stale_pid=$!; bind_instance "$stale" "$stale_pid"; kill "$stale_pid"; wait "$stale_pid" 2>/dev/null || true
  tmux -L "$label" new-session -d -s witness 'sleep 30'; socket="$(tmux -L "$label" display-message -p -t witness '#{socket_path}')"; tmux -S "$socket" set-option -g @datarim_context_epoch "$new_epoch"
  live_out="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-z-live DR_ORCH_CONTEXT_EPOCH="$new_epoch" DR_ORCH_CONTEXT_SOCKET="$socket" bash "$SETUP" install --runtime claude)"; live="$(printf '%s\n' "$live_out" | awk -F= '$1=="instance"{print $2}')"; sleep 30 & live_pid=$!; bind_instance "$live" "$live_pid"
  before="$(sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-z-live.map" "$DR_ORCH_CONTEXT_STATE/instances/$live.cap" "$DR_ORCH_CONTEXT_STATE/instances/$live.meta.json")"
  run env DR_ORCH_CONTEXT_TMUX_SOCKET="$socket" bash "$SETUP" doctor --recover-stale-instances
  after="$(sha256sum "$DR_ORCH_CONTEXT_STATE/active/pane-z-live.map" "$DR_ORCH_CONTEXT_STATE/instances/$live.cap" "$DR_ORCH_CONTEXT_STATE/instances/$live.meta.json")"; kill "$live_pid"; wait "$live_pid" 2>/dev/null || true; tmux -S "$socket" kill-server 2>/dev/null || true
  [ "$status" -ne 0 ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/active/pane-a-stale.map" ] && [ "$before" = "$after" ]
}

@test "section-aware config enables real tmux launch and proven teardown" {
  command -v tmux >/dev/null || skip "tmux required"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; agent="$BATS_TEST_TMPDIR/mock-agent"; session="ctx-launch-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  printf '#!/usr/bin/env bash\nsleep 30\n' >"$agent"; chmod 700 "$agent"
  run env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_RUNTIME=claude DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" \
    bash -c 'source "$1"; session_spawn_interactive "$2" "$3"; session_close "$2"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session" "$agent"
  [ "$status" -eq 0 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/instances" -name '*.retired' | wc -l)" -eq 1 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/active" -name '*.map' | wc -l)" -eq 0 ]
}

@test "real bound Codex launch emits a correlated SessionStart readiness marker" {
  command -v codex >/dev/null && command -v tmux >/dev/null || skip "installed Codex and tmux required"
  [ -f "$SYSTEM_CODEX_HOME/auth.json" ] || skip "authenticated Codex installation required"
  cp "$SYSTEM_CODEX_HOME/auth.json" "$CODEX_HOME/auth.json"; chmod 600 "$CODEX_HOME/auth.json"
  cfg="$BATS_TEST_TMPDIR/config.yaml"; session="ctx-codex-hook-$$"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n' >"$cfg"; chmod 600 "$cfg"
  env DR_ORCH_USER_CONFIG="$cfg" bash "$SETUP" render --runtime codex >/dev/null
  trust_generated_codex_profile
  env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_RUNTIME=codex DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" \
    bash -c 'source "$1"; session_spawn_interactive "$2" "codex --no-alt-screen --strict-config"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session"
  pane="$(tmux display-message -p -t "$session" '#{pane_id}')"; map="$DR_ORCH_CONTEXT_STATE/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; instance="$(cat "$map")"; ready="$DR_ORCH_CONTEXT_STATE/instances/$instance.ready.json"; meta="$DR_ORCH_CONTEXT_STATE/instances/$instance.meta.json"
  for _ in $(seq 1 40); do capture="$(tmux capture-pane -p -t "$session")"; if grep -qF 'Do you trust the contents of this directory?' <<<"$capture"; then tmux send-keys -t "$session" Enter; break; fi; sleep 0.1; done
  printf 'TUNE0167_HOOK_PROBE' >"$BATS_TEST_TMPDIR/hook-probe"; tmux load-buffer -b ctx-hook-probe "$BATS_TEST_TMPDIR/hook-probe"; tmux paste-buffer -d -b ctx-hook-probe -t "$pane"; sleep 2; tmux send-keys -t "$pane" Enter
  for _ in $(seq 1 80); do [ -f "$ready" ] && break; sleep 0.1; done
  proven=0
  if [ -f "$ready" ] && [[ "$(jq -r .conversation "$ready")" =~ ^[0-9a-f-]{36}$ ]] && [ "$(jq -r .profile_digest "$ready")" = "$(jq -r .overlay_digest "$meta")" ]; then proven=1; fi
  if [ "$proven" -ne 1 ]; then
    tmux capture-pane -p -t "$pane" >&3 2>/dev/null || true; jq . "$meta" >&3; sha256sum "$(jq -r .overlay "$meta")" >&3; sed -n '1,120p' "$(jq -r .overlay "$meta")" >&3
    incarnation="$(jq -r .incarnation "$meta")"
    run env DR_ORCH_CONTEXT_INSTANCE="$instance" DR_ORCH_CONTEXT_INCARNATION="$incarnation" DR_ORCH_CONTEXT_PANE="$pane" DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$BATS_TEST_TMPDIR" bash "$ADAPTER" ingest-codex --kind session_start --json '{"session_id":"00000000-0000-0000-0000-000000000000"}'
    printf 'manual_adapter_status=%s output=%s\n' "$status" "$output" >&3
  fi
  env DR_ORCH_USER_CONFIG="$cfg" bash -c 'source "$1"; session_close "$2"' _ "$REPO_ROOT/plugins/dr-orchestrate/scripts/tmux_manager.sh" "$session" || true
  [ "$proven" -eq 1 ]
}

@test "plugin exposes context-pressure hook" {
  run bash "$REPO_ROOT/plugins/dr-orchestrate/scripts/plugin.sh" dispatch on_context_pressure normalize-claude-pressure --json '{"context_window":{"used_percentage":90}}'
  [ "$status" -eq 0 ] && [ "$output" = 90 ]
}

@test "setup doctor does not expose capability bytes" {
  run bash "$SETUP" doctor
  [ "$status" -eq 0 ] && [[ "$output" != *"capability_key"* ]]
}

@test "snapshot hint option is accepted by resolver" {
  run env DR_ORCH_SUBAGENT_CHAIN=mock-none bash "$REPO_ROOT/plugins/dr-orchestrate/scripts/subagent_resolver.sh" resolve --hint /dr-plan -- 'continue task'
  json="$(printf '%s\n' "$output" | tail -1)"
  [ "$status" -eq 0 ] && printf '%s' "$json" | jq -e . >/dev/null
}

@test "cmd_run validates snapshot before forwarding advisory hint" {
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$workspace/datarim/snapshots/TUNE-0167.snapshot.md"
  chmod 600 "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"
  printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"
  chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  run env DR_ORCH_WORKSPACE="$workspace" DR_ORCH_RESOLVER_HINT_LOG="$BATS_TEST_TMPDIR/hint" DR_ORCH_SUBAGENT_CHAIN=mock-none \
    bash "$REPO_ROOT/plugins/dr-orchestrate/scripts/cmd_run.sh" --unknown-prompt 'continue' --task TUNE-0167 --pane pane-1
  [ "$status" -eq 0 ] && [ "$(cat "$BATS_TEST_TMPDIR/hint")" = /dr-do ]
}

@test "cmd_run does not forward a hint from symlinked snapshot" {
  workspace="$BATS_TEST_TMPDIR/workspace"; outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$outside"
  ln -s "$outside" "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"
  printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"
  chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  run env DR_ORCH_WORKSPACE="$workspace" DR_ORCH_RESOLVER_HINT_LOG="$BATS_TEST_TMPDIR/hint" DR_ORCH_SUBAGENT_CHAIN=mock-none \
    bash "$REPO_ROOT/plugins/dr-orchestrate/scripts/cmd_run.sh" --unknown-prompt 'continue' --task TUNE-0167 --pane pane-1
  [ "$status" -eq 0 ] && [ "$(cat "$BATS_TEST_TMPDIR/hint")" = none ]
}

@test "Claude status and Stop hooks drive one selective lifecycle" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; workspace="$BATS_TEST_TMPDIR/workspace"
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n  policy_label: ""\n' >"$cfg"; chmod 600 "$cfg"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; chmod 600 "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"
  printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"
  chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  output="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-8 DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" bash "$SETUP" install --runtime claude)"
  instance="$(printf '%s\n' "$output" | awk -F= '$1=="instance"{print $2}')"; incarnation="$(printf '%s\n' "$output" | awk -F= '$1=="incarnation"{print $2}')"; bind_instance "$instance" "$$"
  binding=(DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_INSTANCE="$instance" DR_ORCH_CONTEXT_INCARNATION="$incarnation" DR_ORCH_CONTEXT_PANE=pane-8 DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions")
  env "${binding[@]}" bash "$ADAPTER" ingest-claude --kind status --json '{"session_id":"conv-8","context_window":{"used_percentage":75}}'
  env "${binding[@]}" bash "$ADAPTER" ingest-claude --kind stop --json '{"session_id":"conv-8"}'
  env "${binding[@]}" bash "$ADAPTER" ingest-claude --kind post_compact --json '{"session_id":"conv-8"}'
  tx_file="$(printf '%s\n' "$DR_ORCH_CONTEXT_STATE"/transactions/*.json)"
  [ "$(cat "$BATS_TEST_TMPDIR/actions")" = "/compact Preserve active Datarim task pointer last completed phase current plan open verification findings and next action" ] && [ "$(jq -r .state "$tx_file")" = completed ]
}

@test "Codex notify derives pressure only from its correlated private rollout" {
  cfg="$BATS_TEST_TMPDIR/config.yaml"; workspace="$BATS_TEST_TMPDIR/workspace"; thread=019f5515-4700-7ec3-afd7-100921e8800f
  printf 'key_injection: true\ncontext_window:\n  enabled: true\n  trust_same_uid_runtime: true\n  policy_label: ""\n' >"$cfg"; chmod 600 "$cfg"
  mkdir -p "$workspace/datarim/snapshots" "$workspace/datarim/tasks" "$CODEX_HOME/sessions/2026/07/19"; chmod 700 "$workspace" "$workspace/datarim" "$workspace/datarim/snapshots" "$workspace/datarim/tasks" "$CODEX_HOME/sessions" "$CODEX_HOME/sessions/2026" "$CODEX_HOME/sessions/2026/07" "$CODEX_HOME/sessions/2026/07/19"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; chmod 600 "$workspace/datarim/snapshots/TUNE-0167.snapshot.md"; printf '# task\n' >"$workspace/datarim/tasks/TUNE-0167-task-description.md"; chmod 600 "$workspace/datarim/tasks/TUNE-0167-task-description.md"
  rollout="$CODEX_HOME/sessions/2026/07/19/rollout-$thread.jsonl"
  printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$thread\"}}" '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":750},"model_context_window":1000}}}' >"$rollout"; chmod 600 "$rollout"
  output="$(env DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_PANE=pane-9 DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" bash "$SETUP" install --runtime codex)"; instance="$(printf '%s\n' "$output" | awk -F= '$1=="instance"{print $2}')"; incarnation="$(printf '%s\n' "$output" | awk -F= '$1=="incarnation"{print $2}')"; bind_instance "$instance" "$$"
  binding=(DR_ORCH_USER_CONFIG="$cfg" DR_ORCH_CONTEXT_INSTANCE="$instance" DR_ORCH_CONTEXT_INCARNATION="$incarnation" DR_ORCH_CONTEXT_PANE=pane-9 DR_ORCH_ACTIVE_TASK=TUNE-0167 DR_ORCH_WORKSPACE="$workspace" DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions")
  run env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind notify --json "{\"type\":\"agent-turn-complete\",\"thread-id\":\"$thread\"}"
  [ "$status" -ne 0 ] && [ ! -e "$BATS_TEST_TMPDIR/actions" ]
  env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind session_start --json "{\"session_id\":\"$thread\"}"
  ready="$DR_ORCH_CONTEXT_STATE/instances/$instance.ready.json"; tmp="$BATS_TEST_TMPDIR/ready"; jq '.conversation="stale-thread"' "$ready" >"$tmp"; chmod 600 "$tmp"; mv "$tmp" "$ready"
  run env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind notify --json "{\"type\":\"agent-turn-complete\",\"thread-id\":\"$thread\"}"
  [ "$status" -ne 0 ] && [ ! -e "$BATS_TEST_TMPDIR/actions" ]
  env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind session_start --json "{\"session_id\":\"$thread\"}"
  profile="$(jq -r .overlay "$DR_ORCH_CONTEXT_STATE/instances/$instance.meta.json")"; cp "$profile" "$BATS_TEST_TMPDIR/profile.backup"; sed -i 's/DATARIM_CONTEXT_PROFILE_CANARY/DATARIM_CONTEXT_PROFILE_TAMPER/' "$profile"
  run env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind notify --json "{\"type\":\"agent-turn-complete\",\"thread-id\":\"$thread\"}"
  [ "$status" -ne 0 ] && [ ! -e "$BATS_TEST_TMPDIR/actions" ]; cp "$BATS_TEST_TMPDIR/profile.backup" "$profile"; chmod 600 "$profile"
  printf '%s\n' '{"type":"event_msg","payload":{"note":"UNRELATED_ROLLOUT_CANARY"}}' >"$CODEX_HOME/sessions/2026/07/19/unrelated.jsonl"; chmod 600 "$CODEX_HOME/sessions/2026/07/19/unrelated.jsonl"
  env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind notify --json "{\"type\":\"agent-turn-complete\",\"thread-id\":\"$thread\",\"input-messages\":\"RAW_NOTIFY_CANARY\",\"last-assistant-message\":\"LAST_ASSISTANT_CANARY\"}"
  env "${binding[@]}" bash "$ADAPTER" ingest-codex --kind post_compact --json "{\"session_id\":\"$thread\"}"
  [ "$(cat "$BATS_TEST_TMPDIR/actions")" = /compact ] && ! rg -q 'RAW_NOTIFY_CANARY|LAST_ASSISTANT_CANARY|UNRELATED_ROLLOUT_CANARY' "$DR_ORCH_CONTEXT_STATE" "$BATS_TEST_TMPDIR/actions"
}

#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  chmod 700 "$BATS_TEST_TMPDIR"
  AUDIT_FILE="$BATS_TEST_TMPDIR/audit.jsonl"
}

@test "V-AC-25: trailing prepare is marked interrupted exactly once" {
  run bash -c '
    source "$1/scripts/audit_sink.sh"
    emit "$2" "$(make_cycle_checkpoint prepare cycle-1 session-a %1 /dr-plan pending)"
    recover_cycle_checkpoint "$2" session-a %1
    recover_cycle_checkpoint "$2" session-a %1
    jq -s -e '\''[.[] | select(.phase=="recovery" and .outcome=="recovered_interrupted")] | length == 1'\'' "$2"
  ' _ "$PLUGIN_ROOT" "$AUDIT_FILE"
  [ "$status" -eq 0 ]
}

@test "V-AC-25: terminal checkpoint prevents recovery" {
  run bash -c '
    source "$1/scripts/audit_sink.sh"
    emit "$2" "$(make_cycle_checkpoint prepare cycle-2 session-a %1 /dr-plan pending)"
    emit "$2" "$(make_cycle_checkpoint terminal cycle-2 session-a %1 /dr-plan delivered exit_0)"
    recover_cycle_checkpoint "$2" session-a %1
    jq -s -e '\''[.[] | select(.phase=="recovery")] | length == 0'\'' "$2"
  ' _ "$PLUGIN_ROOT" "$AUDIT_FILE"
  [ "$status" -eq 0 ]
}

@test "V-AC-25: recovery never invokes an executor seam" {
  executor="$BATS_TEST_TMPDIR/executor.log"
  run env DR_ORCH_ACTION_EXECUTOR_LOG="$executor" bash -c '
    source "$1/scripts/audit_sink.sh"
    emit "$2" "$(make_cycle_checkpoint prepare cycle-3 session-a %1 /dr-plan pending)"
    recover_cycle_checkpoint "$2" session-a %1
    test ! -e "$DR_ORCH_ACTION_EXECUTOR_LOG"
  ' _ "$PLUGIN_ROOT" "$AUDIT_FILE"
  [ "$status" -eq 0 ]
}

@test "V-AC-29: audit lock symlink is rejected without victim mutation" {
  victim="$BATS_TEST_TMPDIR/victim"
  printf 'DO-NOT-TRUNCATE' >"$victim"
  ln -s "$victim" "$AUDIT_FILE.lock"
  run bash "$PLUGIN_ROOT/scripts/audit_sink.sh" emit "$AUDIT_FILE" '{}'
  [ "$status" -ne 0 ]
  [ "$(cat "$victim")" = DO-NOT-TRUNCATE ]
}

@test "V-AC-25: concurrent recovery emits exactly one marker" {
  run bash -c '
    source "$1/scripts/audit_sink.sh"
    emit "$2" "$(make_cycle_checkpoint prepare cycle-race session-a %1 /dr-plan pending)"
    pids=()
    for _ in $(seq 1 16); do recover_cycle_checkpoint "$2" session-a %1 & pids+=("$!"); done
    for pid in "${pids[@]}"; do wait "$pid"; done
    test "$(jq -s '\''[.[] | select(.phase=="recovery")] | length'\'' "$2")" -eq 1
  ' _ "$PLUGIN_ROOT" "$AUDIT_FILE"
  [ "$status" -eq 0 ]
}

@test "V-AC-25: recovery crosses a UTC day rotation" {
  old="$BATS_TEST_TMPDIR/audit-2026-07-17.jsonl"
  current="$BATS_TEST_TMPDIR/audit-2026-07-18.jsonl"
  run bash -c '
    source "$1/scripts/audit_sink.sh"
    emit "$2" "$(make_cycle_checkpoint prepare cycle-midnight session-a %1 /dr-plan pending)"
    pids=()
    for _ in $(seq 1 16); do
      recover_latest_cycle_checkpoint "$(dirname "$2")" "$3" session-a %1 & pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    test "$(jq -s '\''[.[] | select(.phase=="recovery" and .cycle_id=="cycle-midnight")] | length'\'' "$3")" -eq 1
  ' _ "$PLUGIN_ROOT" "$old" "$current"
  [ "$status" -eq 0 ]
}

@test "legacy owner-controlled 0644 audit migrates to private mode" {
  printf '{}\n' >"$AUDIT_FILE"
  chmod 0644 "$AUDIT_FILE"
  run bash "$PLUGIN_ROOT/scripts/audit_sink.sh" emit "$AUDIT_FILE" '{}'
  [ "$status" -eq 0 ]
  [ "$(bash -c 'source "$1/scripts/lib/portable-stat.sh"; portable_mode "$2"' \
    _ "$PLUGIN_ROOT" "$AUDIT_FILE")" = 600 ]
  [ "$(wc -l <"$AUDIT_FILE")" -eq 2 ]
}

@test "descriptor validation is portable and does not depend on procfs" {
  run grep -R -Fq '/proc/' "$PLUGIN_ROOT/scripts/audit_sink.sh" \
    "$PLUGIN_ROOT/scripts/lib/learned-rules-store.sh"
  [ "$status" -ne 0 ]
  grep -qF 'portable_identity "/dev/fd/' "$PLUGIN_ROOT/scripts/audit_sink.sh"
  grep -qF 'portable_identity /dev/fd/9' "$PLUGIN_ROOT/scripts/lib/learned-rules-store.sh"
}

@test "group-writable audit parent is rejected" {
  chmod 0777 "$BATS_TEST_TMPDIR"
  run bash "$PLUGIN_ROOT/scripts/audit_sink.sh" emit "$AUDIT_FILE" '{}'
  [ "$status" -ne 0 ]
  [ ! -e "$AUDIT_FILE" ]
}

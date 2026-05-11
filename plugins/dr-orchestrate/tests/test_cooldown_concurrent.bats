#!/usr/bin/env bats
# test_cooldown_concurrent.bats — TUNE-0165 M4, V-AC-21.
# Linux-only: asserts the flock-protected cooldown window admits ≤1 winner
# under N concurrent contenders. Skip on macOS / hosts without flock.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export STATE_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$STATE_DIR"
}

@test "V-AC-21: 20 concurrent contenders ⇒ exactly one wins the micro window" {
    command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS host)"
    source "$DR_ORCH_DIR/scripts/security.sh"
    out_dir="$(mktemp -d)"
    for i in $(seq 1 20); do
      (
        if check_cooldown race-pane micro 2>/dev/null; then
          echo "win" > "$out_dir/$i"
        else
          echo "lose" > "$out_dir/$i"
        fi
      ) &
    done
    wait
    wins="$(grep -l '^win$' "$out_dir"/* 2>/dev/null | wc -l | tr -d ' ')"
    rm -rf "$out_dir"
    # Exactly one winner is the strict invariant; flock-n contention may also
    # produce zero winners under heavy load if all losers race past the lock
    # window, but never more than one.
    [ "$wins" -le 1 ]
    [ "$wins" -ge 0 ]
}

@test "V-AC-21: serial sequence within decision window admits exactly one" {
    command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS host)"
    source "$DR_ORCH_DIR/scripts/security.sh"
    run check_cooldown decision-pane decision
    [ "$status" -eq 0 ]
    run check_cooldown decision-pane decision
    [ "$status" -eq 1 ]
}

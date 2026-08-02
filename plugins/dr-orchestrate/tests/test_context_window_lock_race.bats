#!/usr/bin/env bats
# Bats resolves the fixture library at runtime.
# shellcheck disable=SC1090

setup() {
  export LIB="$BATS_TEST_DIRNAME/../scripts/lib/context-window-state.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export LOCK="$BATS_TEST_TMPDIR/state/transactions/.store.lock"
  mkdir -p "$HOME" "$(dirname "$LOCK")"
  chmod 700 "$HOME" "$BATS_TEST_TMPDIR/state" "$(dirname "$LOCK")"
}

@test "owner publication grace does not reclaim a live creator" {
  (
    source "$LIB"
    mkdir "$LOCK"
    : >"$BATS_TEST_TMPDIR/creator-ready"
    sleep 0.1
    printf '%s %s\n' "$BASHPID" "$(ctx_process_birth "$BASHPID")" >"$LOCK/owner"
    chmod 600 "$LOCK/owner"
    : >"$BATS_TEST_TMPDIR/owner-published"
    sleep 0.2
    ctx_lock_release "$LOCK"
  ) &
  creator=$!

  attempts=0
  while [ ! -f "$BATS_TEST_TMPDIR/creator-ready" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || false
    sleep 0.01
  done

  run bash -c 'source "$1"; ctx_lock_acquire "$2"; ctx_lock_release "$2"' _ "$LIB" "$LOCK"
  creator_status=0
  wait "$creator" || creator_status=$?

  [ "$status" -eq 0 ] \
    && [ "$creator_status" -eq 0 ] \
    && [ -f "$BATS_TEST_TMPDIR/owner-published" ] \
    && [ "$(find "$BATS_TEST_TMPDIR/state/transactions" -maxdepth 1 -name '.store.lock.stale.*' | wc -l)" -eq 0 ]
}

@test "stale-owner reclaimer cannot remove a fresh lock generation" {
  mkdir "$LOCK"
  printf '999999 stale-birth\n' >"$LOCK/owner"
  chmod 600 "$LOCK/owner"

  (
    source "$LIB"
    ctx_process_birth() {
      if [ "$1" = 999999 ]; then
        printf 'stale-birth\n'
      elif [ -r "/proc/$1/stat" ]; then
        command awk '{print $22}' "/proc/$1/stat"
      else
        ps -p "$1" -o lstart= 2>/dev/null | shasum -a 256 | awk 'NF{print $1}'
      fi
    }
    ctx_process_live() {
      if [ "$1" = 999999 ]; then
        : >"$BATS_TEST_TMPDIR/stale-observed"
        while [ ! -f "$BATS_TEST_TMPDIR/fresh-ready" ]; do sleep 0.01; done
        return 1
      fi
      kill -0 "$1" 2>/dev/null
    }
    if ctx_lock_acquire "$LOCK"; then
      [ -f "$BATS_TEST_TMPDIR/winner-holding" ] && : >"$BATS_TEST_TMPDIR/fresh-lock-stolen"
      ctx_lock_release "$LOCK"
    fi
  ) &
  contender=$!

  attempts=0
  while [ ! -f "$BATS_TEST_TMPDIR/stale-observed" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || false
    sleep 0.01
  done

  mkdir "$LOCK/.reclaim"
  old_lock="$BATS_TEST_TMPDIR/old-lock"
  mv "$LOCK" "$old_lock"
  rm -f "$old_lock/owner"
  rmdir "$old_lock/.reclaim" "$old_lock"
  mkdir "$LOCK"
  winner_pid="$BASHPID"
  winner_birth="$(bash -c 'source "$1"; ctx_process_birth "$2"' _ "$LIB" "$winner_pid")"
  printf '%s %s\n' "$winner_pid" "$winner_birth" >"$LOCK/owner"
  chmod 600 "$LOCK/owner"
  : >"$BATS_TEST_TMPDIR/winner-holding"
  : >"$BATS_TEST_TMPDIR/fresh-ready"
  sleep 0.2

  protected_status=0
  if ! { [ -d "$LOCK" ] && [ -f "$LOCK/owner" ] && [ ! -f "$BATS_TEST_TMPDIR/fresh-lock-stolen" ]; }; then
    protected_status=1
  fi
  rm -f "$BATS_TEST_TMPDIR/winner-holding"
  rm -f "$LOCK/owner"
  rmdir "$LOCK" 2>/dev/null || true
  contender_status=0
  wait "$contender" || contender_status=$?

  [ "$protected_status" -eq 0 ] && [ "$contender_status" -eq 0 ]
}

@test "competing waiters fail closed on an ownerless lock" {
  mkdir "$LOCK"

  for id in 1 2; do
    (
      source "$LIB"
      if ctx_lock_acquire "$LOCK"; then
        : >"$BATS_TEST_TMPDIR/ownerless-stolen-$id"
        ctx_lock_release "$LOCK"
      else
        : >"$BATS_TEST_TMPDIR/ownerless-refused-$id"
      fi
    ) &
  done
  wait

  [ -d "$LOCK" ] \
    && [ ! -e "$BATS_TEST_TMPDIR/ownerless-stolen-1" ] \
    && [ ! -e "$BATS_TEST_TMPDIR/ownerless-stolen-2" ] \
    && [ -e "$BATS_TEST_TMPDIR/ownerless-refused-1" ] \
    && [ -e "$BATS_TEST_TMPDIR/ownerless-refused-2" ]
}

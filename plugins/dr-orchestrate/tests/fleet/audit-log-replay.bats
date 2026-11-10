#!/usr/bin/env bats
# audit-log-replay.bats — V-AC-3: audit log trim archives before XTRIM.
# Integration tests skip (exit 77) when Redis unavailable.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
AUDIT_TRIM="$PLUGIN_ROOT/scripts/fleet_audit_trim.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  TMP="$(mktemp -d)"
  export DR_FLEET_AUDIT_ARCHIVE_DIR="$TMP/archive"
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

teardown() {
  rm -rf "$TMP"
  if (( REDIS_AVAILABLE )); then
    redis-cli -u "$REDIS_URL" DEL "stream:fleet:audit-log" >/dev/null 2>&1 || true
  fi
}

# ── function existence (no Redis needed) ─────────────────────────────────────

@test "V-AC-3: fleet_audit_trim.sh is executable" {
  [ -x "$AUDIT_TRIM" ]
}

@test "V-AC-3: the trim is exact, not approximate" {
    # An approximate XTRIM (MAXLEN "~") keeps whole macro nodes, so the stream
    # can stay far above --max-len. This check needs no Redis, so the contract
    # is protected on runners that have none — where the integration test below
    # skips. The detector accepts every quoting of the approximate form
    # (MAXLEN ~, MAXLEN "~", MAXLEN '~'), so it cannot be side-stepped by
    # quoting, and it also pins the exact form that must be present. Comment
    # lines are stripped first: the script documents why an approximate trim
    # is wrong, and prose must not be read as code.
    sed 's/^[[:space:]]*#.*//' "$AUDIT_TRIM" > "$TMP/trim.nocomment"
    run grep -E 'MAXLEN[[:space:]]+["'"'"']?~' "$TMP/trim.nocomment"
    [ "$status" -ne 0 ]
    run grep -E 'XTRIM[[:space:]]+"?\$STREAM_KEY"?[[:space:]]+MAXLEN[[:space:]]+"?\$MAX_LEN"?' "$TMP/trim.nocomment"
    [ "$status" -eq 0 ]
}

@test "V-AC-3: the approximate-trim detector flags every quoting" {
    for variant in 'MAXLEN ~' 'MAXLEN "~"' "MAXLEN '~'"; do
        printf 'redis-cli XTRIM "$STREAM_KEY" %s "$MAX_LEN"\n' "$variant" > "$TMP/approx.sh"
        run grep -E 'MAXLEN[[:space:]]+["'"'"']?~' "$TMP/approx.sh"
        [ "$status" -eq 0 ]
    done
}

@test "V-AC-3: fleet_audit_trim.sh --help exits 0" {
  run bash "$AUDIT_TRIM" --help
  [ "$status" -eq 0 ]
}

@test "V-AC-3: fleet_audit_trim.sh --dry-run flag accepted" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash "$AUDIT_TRIM" --dry-run
  [ "$status" -eq 0 ]
}

# ── Redis integration ─────────────────────────────────────────────────────────

@test "V-AC-3: trim archives entries before XTRIM" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  # Seed audit log stream with 5 entries
  for i in $(seq 1 5); do
    redis-cli -u "$REDIS_URL" XADD "stream:fleet:audit-log" '*' \
      id "uuid-$i" ts "2026-06-09T00:00:0${i}Z" type audit from test to test >/dev/null
  done
  run bash "$AUDIT_TRIM" --max-len 2
  [ "$status" -eq 0 ]
  # Archive file should exist
  archive_count=$(find "$DR_FLEET_AUDIT_ARCHIVE_DIR" -name "*.jsonl.gz" 2>/dev/null | wc -l | tr -d ' ')
  [ "$archive_count" -gt 0 ]
  # Stream should be trimmed
  len=$(redis-cli -u "$REDIS_URL" XLEN "stream:fleet:audit-log")
  [ "$len" -le 2 ]
}

@test "V-AC-3: trim creates archive directory if not exists" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  rm -rf "$DR_FLEET_AUDIT_ARCHIVE_DIR"
  redis-cli -u "$REDIS_URL" XADD "stream:fleet:audit-log" '*' \
    id "uuid-seed" ts "2026-06-09T00:00:00Z" type audit from test to test >/dev/null
  run bash "$AUDIT_TRIM" --max-len 1000000
  [ "$status" -eq 0 ]
  [ -d "$DR_FLEET_AUDIT_ARCHIVE_DIR" ]
}

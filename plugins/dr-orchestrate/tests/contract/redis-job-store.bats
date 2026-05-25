#!/usr/bin/env bats
# redis-job-store.bats — TUNE-0295 Phase B
# Async job store backed by Redis. Stubbed redis-cli via PATH override.
# V-AC: V-AC-3 (async machinery), V-AC-9 (fail-soft on connect failure).

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
STORE="$PLUGIN_ROOT/scripts/redis_job_store.sh"

setup() {
  TMP="$(mktemp -d)"
  BIN="$TMP/bin"
  mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
  export DR_ORCH_REDIS_STORE_FILE="$TMP/data"
  export DR_ORCH_JOB_TTL="3600"

  cat >"$BIN/redis-cli" <<'EOF'
#!/usr/bin/env bash
while [[ "${1:-}" == "-u" ]]; do shift 2; done
store="${DR_ORCH_REDIS_STORE_FILE:-/tmp/redis-store/data}"
mkdir -p "$(dirname "$store")"
touch "$store"
cmd="$1"; key="${2:-}"
case "$cmd" in
  SET)
    val="$3"
    grep -v "^$key|" "$store" >"$store.tmp" 2>/dev/null || true
    mv "$store.tmp" "$store"
    printf '%s|%s\n' "$key" "$val" >>"$store"
    echo "OK"
    ;;
  GET)
    line="$(grep "^$key|" "$store" | tail -1 || true)"
    [[ -n "$line" ]] && printf '%s' "${line#*|}"
    ;;
  TTL)
    if grep -q "^$key|" "$store"; then echo "3594"; else echo "-2"; fi
    ;;
  DEL)
    grep -v "^$key|" "$store" >"$store.tmp" 2>/dev/null || true
    mv "$store.tmp" "$store"; echo "1"
    ;;
  PING) echo "PONG" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/redis-cli"
}

teardown() { rm -rf "$TMP"; }

@test "V-AC-3 §store: set+get round-trip" {
  source "$STORE"
  job_store_set "abc-uuid" '{"status":"pending"}'
  run job_store_get "abc-uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"pending"'* ]]
}

@test "V-AC-3 §store: get missing returns code 404 marker" {
  source "$STORE"
  run job_store_get "no-such-uuid"
  [ "$status" -eq 1 ]
}

@test "V-AC-3 §store: update overwrites previous value" {
  source "$STORE"
  job_store_set "xyz-uuid" '{"status":"pending"}'
  job_store_set "xyz-uuid" '{"status":"complete","data":{}}'
  run job_store_get "xyz-uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"complete"'* ]]
}

@test "V-AC-3 §store: TTL probe returns numeric / -2 distinguishably" {
  source "$STORE"
  job_store_set "ttl-uuid" 'x'
  run job_store_ttl "ttl-uuid"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  run job_store_ttl "missing-uuid"
  [ "$output" = "-2" ]
}

@test "V-AC-9 §fail-soft: redis-cli unreachable → 503 marker, not crash" {
  # Replace redis-cli with one that always fails (simulate connect-refused).
  cat >"$BIN/redis-cli" <<'EOF'
#!/usr/bin/env bash
echo "Could not connect to Redis at 127.0.0.1:6379: Connection refused" >&2
exit 1
EOF
  chmod +x "$BIN/redis-cli"
  source "$STORE"
  run job_store_set "any-uuid" 'x'
  [ "$status" -ne 0 ]
  # Must NOT exit shell with set -e leakage; function returns non-zero.
  run job_store_get "any-uuid"
  [ "$status" -ne 0 ]
}

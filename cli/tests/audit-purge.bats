#!/usr/bin/env bats
# V-AC-20 — retention purge: <90d untouched, 90-180d gzipped to archive/, >180d deleted.
# Source: TUNE-0271 plan § Detailed Design 4.2.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    REPO_ROOT="$(cd "$CLI_DIR/.." && pwd)"
    AUDIT_LIB="$CLI_DIR/lib/audit.sh"
    CHECK_SCRIPT="$REPO_ROOT/dev-tools/check-cli-audit-schema.sh"
    [ -f "$AUDIT_LIB" ] || skip "audit.sh missing"

    TMP_DIR="$(mktemp -d)"
    export DATARIM_CLI_AUDIT_DIR="$TMP_DIR/audit"
    mkdir -p "$DATARIM_CLI_AUDIT_DIR"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" || true
}

# Build a fixture of N files at evenly spaced ages from 0..N days ago.
_seed_fixture() {
    local n="$1"
    local today_epoch i age_epoch datestr
    today_epoch=$(date -u +%s)
    for i in $(seq 0 $((n - 1))); do
        age_epoch=$(( today_epoch - i * 86400 ))
        datestr=$(python3 -c "import datetime,sys; print(datetime.datetime.utcfromtimestamp(int(sys.argv[1])).strftime('%Y-%m-%d'))" "$age_epoch")
        printf '{"schema_version":1,"ts":"%sT00:00:00.000Z","session_id":"x","calling_agent":"y","subcommand":"run","args_hash":"sha256:%064x","reversibility":"reversible","outcome":"success","duration_ms":1,"exit_code":0}\n' \
            "$datestr" 0 > "$DATARIM_CLI_AUDIT_DIR/cli-audit-$datestr.jsonl"
    done
}

@test "V-AC-20: 100-file fixture — <90d untouched, 90-180d archived, >180d deleted" {
    _seed_fixture 200
    # Sanity: 200 raw files before purge.
    raw_count=$(ls "$DATARIM_CLI_AUDIT_DIR"/cli-audit-*.jsonl 2>/dev/null | wc -l | tr -d ' ')
    [ "$raw_count" -eq 200 ]

    run "$CHECK_SCRIPT" --purge-older-than 90d
    [ "$status" -eq 0 ]

    # Bucketise: count files in each band.
    young=0; archived=0
    for f in "$DATARIM_CLI_AUDIT_DIR"/cli-audit-*.jsonl; do
        [ -f "$f" ] || continue
        young=$((young + 1))
    done
    for f in "$DATARIM_CLI_AUDIT_DIR"/archive/cli-audit-*.jsonl.gz; do
        [ -f "$f" ] || continue
        archived=$((archived + 1))
    done
    # Days 0..89 untouched: 90 raw files.
    [ "$young" -eq 90 ]
    # Days 90..179 archived: 90 gz files.
    [ "$archived" -eq 90 ]
    # Days 180..199 deleted: 20 files gone.
    deleted=$((200 - young - archived))
    [ "$deleted" -eq 20 ]
}

@test "V-AC-20: re-running purge is idempotent (no re-archiving)" {
    _seed_fixture 100
    "$CHECK_SCRIPT" --purge-older-than 90d
    first_archived=$(ls "$DATARIM_CLI_AUDIT_DIR"/archive/ 2>/dev/null | wc -l | tr -d ' ')
    "$CHECK_SCRIPT" --purge-older-than 90d
    second_archived=$(ls "$DATARIM_CLI_AUDIT_DIR"/archive/ 2>/dev/null | wc -l | tr -d ' ')
    [ "$first_archived" -eq "$second_archived" ]
}

@test "V-AC-20: rejects unsupported purge window (Phase 3 only ships 90d)" {
    run "$CHECK_SCRIPT" --purge-older-than 30d
    [ "$status" -eq 2 ]
}

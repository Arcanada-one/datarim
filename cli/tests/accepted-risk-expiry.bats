#!/usr/bin/env bats
# V-AC-15 / V-AC-26 — accepted-risk-aal entry validation + expiry gate.
# V-AC-27           — 7-day pre-expiry stderr warning.
# Source: TUNE-0271 plan § Detailed Design 4.4.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    REPO_ROOT="$(cd "$CLI_DIR/.." && pwd)"
    VALIDATOR="$REPO_ROOT/dev-tools/check-accepted-risk-aal.sh"
    LIB="$CLI_DIR/lib/accepted-risk-check.sh"
    REAL_FILE="$REPO_ROOT/accepted-risk-aal.yml"
    [ -x "$VALIDATOR" ] || skip "validator missing"
    [ -f "$REAL_FILE" ] || skip "real accepted-risk-aal.yml missing"
}

@test "V-AC-15: retired real register blocks TUNE-0268 with exit 23" {
    run "$VALIDATOR" --task TUNE-0268
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
}

@test "V-AC-15: real accepted-risk-aal.yml is a valid empty register" {
    run "$VALIDATOR" --file "$REAL_FILE"
    [ "$status" -eq 0 ]
    ! grep -q '^  - id:' "$REAL_FILE"
}

@test "V-AC-26: backdated entry (expires yesterday) → exit 23" {
    fixture="$(mktemp)"
    yesterday=$(python3 -c "import datetime; print((datetime.date.today() - datetime.timedelta(days=1)).isoformat())")
    cat >"$fixture" <<EOF
schema_version: 1
entries:
  - id: tune-0268-aal3-cli
    title: "Expired test entry"
    accepted_at: 2026-01-01
    expires: $yesterday
    review_required_by: $yesterday
    operator: test
    mandate_overridden: documentation/mandates/aal-mandate.md
    mandate_ceiling: 2
    declared_level: 3
    scope: ["test"]
    mitigations: ["dual_channel_notifier_fail_closed"]
    risk_summary: "test"
    rollback: "test"
EOF
    run "$VALIDATOR" --file "$fixture" --task TUNE-0268
    [ "$status" -eq 23 ]
    [[ "$output" == *"EXPIRED"* ]]
    rm -f "$fixture"
}

@test "V-AC-27: entry expiring in 6 days → exit 0 with warning on stderr" {
    fixture="$(mktemp)"
    soon=$(python3 -c "import datetime; print((datetime.date.today() + datetime.timedelta(days=6)).isoformat())")
    cat >"$fixture" <<EOF
schema_version: 1
entries:
  - id: tune-0268-aal3-cli
    title: "Near-expiry test entry"
    accepted_at: 2026-01-01
    expires: $soon
    review_required_by: $soon
    operator: test
    mandate_overridden: documentation/mandates/aal-mandate.md
    mandate_ceiling: 2
    declared_level: 3
    scope: ["test"]
    mitigations: ["dual_channel_notifier_fail_closed"]
    risk_summary: "test"
    rollback: "test"
EOF
    run "$VALIDATOR" --file "$fixture" --task TUNE-0268
    [ "$status" -eq 0 ]
    [[ "$output" == *"expires in 6 days"* ]]
    rm -f "$fixture"
}

@test "V-AC-27: entry expiring in 30 days → exit 0, no warning" {
    fixture="$(mktemp)"
    later=$(python3 -c "import datetime; print((datetime.date.today() + datetime.timedelta(days=30)).isoformat())")
    cat >"$fixture" <<EOF
schema_version: 1
entries:
  - id: tune-0268-aal3-cli
    title: "Distant-expiry test entry"
    accepted_at: 2026-01-01
    expires: $later
    review_required_by: $later
    operator: test
    mandate_overridden: documentation/mandates/aal-mandate.md
    mandate_ceiling: 2
    declared_level: 3
    scope: ["test"]
    mitigations: ["dual_channel_notifier_fail_closed"]
    risk_summary: "test"
    rollback: "test"
EOF
    run "$VALIDATOR" --file "$fixture" --task TUNE-0268
    [ "$status" -eq 0 ]
    [[ "$output" != *"expires in"* ]]
    rm -f "$fixture"
}

@test "V-AC-26: missing entry for task → exit 23" {
    fixture="$(mktemp)"
    cat >"$fixture" <<EOF
schema_version: 1
entries:
  - id: tune-9999-other
    title: "x"
    accepted_at: 2026-05-23
    expires: 2026-08-21
    review_required_by: 2026-08-21
    operator: x
    mandate_overridden: x
    mandate_ceiling: 2
    declared_level: 3
    scope: ["x"]
    mitigations: ["x"]
    risk_summary: "x"
    rollback: "x"
EOF
    run "$VALIDATOR" --file "$fixture" --task TUNE-0268
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
    rm -f "$fixture"
}

@test "V-AC-15: accepted-risk gate revalidates when the register changes" {
    [ -f "$LIB" ] || skip "lib missing"
    fixture_root="$BATS_TEST_TMPDIR/fixture-root"
    mkdir -p "$fixture_root/dev-tools" "$fixture_root/cli/lib"
    cp "$VALIDATOR" "$fixture_root/dev-tools/check-accepted-risk-aal.sh"
    cp "$LIB" "$fixture_root/cli/lib/accepted-risk-check.sh"
    fixture_lib="$fixture_root/cli/lib/accepted-risk-check.sh"
    accepted=$(date -u +%F)
    later=$(python3 -c "import datetime; print((datetime.date.today() + datetime.timedelta(days=30)).isoformat())")
    cat >"$fixture_root/accepted-risk-aal.yml" <<EOF
schema_version: 1
entries:
  - id: tune-0268-aal3-cli
    title: "Active test entry"
    accepted_at: $accepted
    expires: $later
    review_required_by: $later
    operator: test
    mandate_overridden: documentation/mandates/aal-mandate.md
    mandate_ceiling: 2
    declared_level: 3
    scope: ["test"]
    mitigations: ["test"]
    risk_summary: "test"
    rollback: "test"
EOF
    run bash -c ". '$fixture_lib'; aal_check TUNE-0268"
    [ "$status" -eq 0 ]
    cat >"$fixture_root/accepted-risk-aal.yml" <<'EOF'
schema_version: 1
entries: []
EOF
    run bash -c ". '$fixture_lib'; aal_check TUNE-0268"
    [ "$status" -eq 23 ]
}

@test "V-AC-15: caller-controlled TMPDIR cache bytes cannot bypass validation" {
    [ -f "$LIB" ] || skip "lib missing"
    cache_root="$BATS_TEST_TMPDIR/poisoned-tmp"
    mkdir -p "$cache_root/datarim-cli-aal-cache"
    risk_hash="$(shasum -a 256 "$REAL_FILE" | awk '{print $1}')"
    cache_key="$(printf '%s' "TUNE-0268-$VALIDATOR-$risk_hash" | shasum -a 256 | awk '{print $1}')"
    : > "$cache_root/datarim-cli-aal-cache/$cache_key"

    run bash -c "export TMPDIR='$cache_root'; . '$LIB'; aal_check TUNE-0268"
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
}

@test "expired acceptance makes installer fail closed with exit 23" {
    target="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$target"
    run env HOME="$BATS_TEST_TMPDIR/home" "$CLI_DIR/install.sh" --dry-run --target-bin "$target"
    [ "$status" -eq 23 ]
    [[ "$output" == *"accepted-risk-aal validation failed (exit 23)"* ]]
    [ ! -e "$target/datarim" ]
}

@test "retired acceptance blocks mutation before external dispatch" {
    run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$REPO_ROOT" \
        "$CLI_DIR/datarim" run /dr-status
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
    [[ "$output" != *"connect-failed-after-retries"* ]]
}

@test "retired acceptance blocks every mutation-capable CLI family" {
    assert_blocked() {
        run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$REPO_ROOT" \
            "$CLI_DIR/datarim" "$@"
        [ "$status" -eq 23 ] \
            && [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
    }
    assert_blocked tasks move TUNE-9999 "do" \
        && assert_blocked backlog add --id TUNE-9999 --priority P4 --complexity L1 --title probe \
        && assert_blocked tmux kill %0 \
        && assert_blocked audit resume \
        && assert_blocked audit purge \
        && assert_blocked plugin enable /tmp/example \
        && assert_blocked plugin disable example \
        && assert_blocked plugin sync \
        && assert_blocked plugin doctor --fix
}

@test "retired acceptance blocks backlog add before it appends" {
    workspace="$BATS_TEST_TMPDIR/mutation-workspace"
    backlog="$workspace/datarim/backlog.md"
    mkdir -p "$(dirname "$backlog")"
    printf '# Backlog\n' > "$backlog"
    before="$(shasum -a 256 "$backlog" | awk '{print $1}')"

    run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$REPO_ROOT" \
        DATARIM_WORKSPACE_ROOT="$workspace" "$CLI_DIR/datarim" backlog add \
        --id TUNE-9999 --priority P4 --complexity L1 --title probe
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
    [ "$before" = "$(shasum -a 256 "$backlog" | awk '{print $1}')" ]
    ! grep -q 'TUNE-9999' "$backlog"
}

@test "caller-controlled DATARIM_ROOT cannot replace validator provenance" {
    spoof_root="$BATS_TEST_TMPDIR/spoof-root"
    workspace="$BATS_TEST_TMPDIR/spoof-workspace"
    backlog="$workspace/datarim/backlog.md"
    mkdir -p "$spoof_root/dev-tools" "$(dirname "$backlog")"
    cp /bin/true "$spoof_root/dev-tools/check-accepted-risk-aal.sh"
    printf 'schema_version: 1\nentries: []\n' > "$spoof_root/accepted-risk-aal.yml"
    printf '# Backlog\n' > "$backlog"
    before="$(shasum -a 256 "$backlog" | awk '{print $1}')"

    run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$spoof_root" \
        DATARIM_WORKSPACE_ROOT="$workspace" DATARIM_CLI_AUDIT_DIR="$BATS_TEST_TMPDIR/audit" \
        "$CLI_DIR/datarim" backlog add --id TUNE-9999 --priority P4 --complexity L1 --title spoof
    [ "$status" -eq 23 ]
    [[ "$output" == *"no active entry matching task TUNE-0268"* ]]
    [ "$before" = "$(shasum -a 256 "$backlog" | awk '{print $1}')" ]
    ! grep -q 'TUNE-9999' "$backlog"
}

@test "retired acceptance keeps protective audit halt available" {
    halt="$BATS_TEST_TMPDIR/HALT"
    agent_id="$($CLI_DIR/lib/uuid7-gen.sh)"
    run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$REPO_ROOT" \
        DATARIM_CLI_AGENT_ID="$agent_id" DATARIM_CLI_HALT_PATH="$halt" \
        "$CLI_DIR/datarim" audit halt
    [ "$status" -eq 0 ] && [ -f "$halt" ]
}

@test "retired acceptance keeps version available" {
    run env HOME="$BATS_TEST_TMPDIR/home" DATARIM_ROOT="$REPO_ROOT" \
        "$CLI_DIR/datarim" version
    [ "$status" -eq 0 ]
}

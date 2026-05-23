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

@test "V-AC-15: real accepted-risk-aal.yml passes validator for TUNE-0268" {
    run "$VALIDATOR" --task TUNE-0268
    [ "$status" -eq 0 ]
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

@test "V-AC-26: missing entry for task → exit 1" {
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
    [ "$status" -eq 1 ]
    rm -f "$fixture"
}

@test "V-AC-15: cli/lib/accepted-risk-check.sh caches successful check" {
    [ -f "$LIB" ] || skip "lib missing"
    # First call populates cache; second short-circuits.
    cache_dir="${TMPDIR:-/tmp}/datarim-cli-aal-cache"
    rm -rf "$cache_dir"
    run bash -c "DATARIM_ROOT='$REPO_ROOT' . '$LIB'; aal_check TUNE-0268"
    [ "$status" -eq 0 ]
    [ -d "$cache_dir" ]
    # Second invocation is silent + 0.
    run bash -c "DATARIM_ROOT='$REPO_ROOT' . '$LIB'; aal_check TUNE-0268"
    [ "$status" -eq 0 ]
}

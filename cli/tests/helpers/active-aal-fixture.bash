setup_active_aal_fixture() {
    local framework_root="$1" fixture_root="$2" accepted_at expires
    mkdir -p "$fixture_root"
    cp -R "$framework_root/cli" "$fixture_root/cli"
    mkdir -p "$fixture_root/dev-tools"
    cp "$framework_root/dev-tools/check-accepted-risk-aal.sh" \
        "$fixture_root/dev-tools/check-accepted-risk-aal.sh"
    accepted_at="$(date -u +%F)"
    expires="$(python3 -c 'import datetime; print((datetime.date.today() + datetime.timedelta(days=30)).isoformat())')"
    cat >"$fixture_root/accepted-risk-aal.yml" <<EOF
schema_version: 1
entries:
  - id: tune-0268-aal3-cli
    title: "Active Bats-only AAL acceptance"
    accepted_at: $accepted_at
    expires: $expires
    review_required_by: $expires
    operator: test
    mandate_overridden: documentation/mandates/aal-mandate.md
    mandate_ceiling: 2
    declared_level: 3
    scope: ["test-only mutation paths"]
    mitigations: ["isolated fixtures"]
    risk_summary: "Temporary acceptance confined to an isolated Bats process."
    rollback: "Bats removes the temporary fixture directory."
EOF
    # Exercise an isolated installation root. The shipped gate deliberately
    # ignores DATARIM_ROOT so callers cannot select their own validator.
    CLI_DIR="$fixture_root/cli"
    DATARIM_BIN="$CLI_DIR/datarim"
    MOCK="$CLI_DIR/tests/fixtures/mock-webhook.py"
    UUID_GEN="$CLI_DIR/lib/uuid7-gen.sh"
    export CLI_DIR DATARIM_BIN MOCK UUID_GEN
    unset DATARIM_ROOT
}

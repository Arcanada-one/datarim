setup_active_aal_fixture() {
    local framework_root="$1" fixture_root="$2" accepted_at expires
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
    export DATARIM_ROOT="$fixture_root"
}

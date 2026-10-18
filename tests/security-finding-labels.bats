#!/usr/bin/env bats
# Structural controls for the compliance security-finding label consumer.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-security-finding-labels.py"
    REPORT="$BATS_TEST_TMPDIR/report.md"
    COMMAND="$REPO_ROOT/commands/dr-compliance.md"
    TEMPLATE="$REPO_ROOT/templates/compliance-report-template.md"
}

@test "compliance command invokes the report template's label validator" {
    grep -qF 'dev-tools/check-security-finding-labels.py' "$COMMAND"
    grep -qF 'security-finding-evidence:begin' "$TEMPLATE"
    grep -qF 'security-finding-evidence:end' "$TEMPLATE"
}

@test "compliance report template contains a valid no-claim positive example" {
    grep -q '^### Security finding evidence' "$TEMPLATE"
    run python3 -I "$SCRIPT" --report "$TEMPLATE"
    [ "$status" -eq 0 ]
}

write_report() {
    cat > "$REPORT" <<EOF
# Compliance report

<!-- security-finding-evidence:begin -->
\`\`\`json
$1
\`\`\`
<!-- security-finding-evidence:end -->
EOF
}

@test "accepts a bounded static hypothesis without claiming a test ran" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-1",
        "evidence_label": "hypothesis",
        "reproduction_state": "not_attempted",
        "assessment_scope": "static",
        "scope": "One bounded configuration path.",
        "mechanism": "A source condition may permit an unsafe fallback.",
        "evidence_refs": [],
        "origin": "author_reported",
        "witness": null,
        "custody_ref": null
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 0 ]
}

@test "accepts a runtime reproduction only with independent witness and custody references" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-1",
        "evidence_label": "supported",
        "reproduction_state": "reproduced",
        "assessment_scope": "qualified_runtime",
        "scope": "One bounded test environment.",
        "mechanism": "The described path reproduced under the cited control.",
        "evidence_refs": ["evidence/run-1.log"],
        "origin": "independent_witness",
        "witness": {
          "identity": "Test Witness A",
          "evidence_ref": "evidence/run-1.log"
        },
        "custody_ref": "evidence/run-1.log"
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 0 ]
}

@test "accepts legacy review as static historical evidence only" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-1",
        "evidence_label": "legacy_review",
        "reproduction_state": "not_attempted",
        "assessment_scope": "static",
        "scope": "Historical review of one source path.",
        "mechanism": "The older review described the control boundary.",
        "evidence_refs": ["archive/review.md#finding"],
        "origin": "artifact_cited",
        "witness": null,
        "custody_ref": null
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 0 ]
}

@test "rejects a self-reported test promoted to tested or reproduced" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-2",
        "evidence_label": "supported",
        "reproduction_state": "tested",
        "assessment_scope": "qualified_runtime",
        "scope": "One bounded execution path.",
        "mechanism": "An author assertion claims a reproduction.",
        "evidence_refs": ["report.md#test"],
        "origin": "author_reported",
        "witness": null,
        "custody_ref": null,
        "tested": true
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsupported field"* ]]
    [[ "$output" == *"invalid reproduction_state"* ]]
    [[ "$output" == *"requires independent_witness"* ]]
}

@test "rejects runtime labels without identified witness and evidence custody" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-3",
        "evidence_label": "supported",
        "reproduction_state": "reproduced",
        "assessment_scope": "qualified_runtime",
        "scope": "One bounded execution path.",
        "mechanism": "A controlled runtime case reproduced the behavior.",
        "evidence_refs": ["run-log.txt"],
        "origin": "independent_witness",
        "witness": null,
        "custody_ref": null
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires identified witness"* ]]
    [[ "$output" == *"requires a custody reference"* ]]
}

@test "rejects supported findings without a cited source" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-4",
        "evidence_label": "supported",
        "reproduction_state": "not_attempted",
        "assessment_scope": "static",
        "scope": "One bounded source path.",
        "mechanism": "A source branch allows the fallback.",
        "evidence_refs": [],
        "origin": "artifact_cited",
        "witness": null,
        "custody_ref": null
      }]
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"supported findings require an evidence reference"* ]]
}

@test "rejects duplicate keys" {
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [],
      "findings": []
    }'
    run python3 -I "$SCRIPT" --report "$REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"duplicate-key JSON"* ]]
}

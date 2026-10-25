#!/usr/bin/env bats
# Structural controls for the compliance security-finding label consumer.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-security-finding-labels.py"
    PATH_RESOLVER="$REPO_ROOT/dev-tools/resolve-compliance-report-path.py"
    REPORT="$BATS_TEST_TMPDIR/report.md"
    COMMAND="$REPO_ROOT/commands/dr-compliance.md"
    TEMPLATE="$REPO_ROOT/templates/compliance-report-template.md"
}

@test "compliance command validates and emits the exact reserved report path" {
    grep -qF 'dev-tools/check-security-finding-labels.py' "$COMMAND"
    grep -qF 'dev-tools/resolve-compliance-report-path.py' "$COMMAND"
    grep -qF -- '--report "$report_path"' "$COMMAND"
    grep -qF 'cat -- "$report_path"' "$COMMAND"
    grep -qF '&& "$label_validation_status" -ne 1' "$COMMAND"
    ! grep -qF -- '--report "datarim/reports/compliance-report-{TASK-ID}.md"' "$COMMAND"
    ! grep -qF -- '--report "datarim/reports/compliance-report-${TASK_ID}.md"' "$REPO_ROOT/skills/compliance/SKILL.md"
    grep -qF 'security-finding-evidence:begin' "$TEMPLATE"
    grep -qF 'security-finding-evidence:end' "$TEMPLATE"
}

@test "reserves the initial persistent report path without creating a second destination" {
    local root="$BATS_TEST_TMPDIR/initial"
    mkdir -p "$root/datarim/reports"

    run python3 -I "$PATH_RESOLVER" --root "$root" --task-id TUNE-0001
    [ "$status" -eq 0 ]
    [[ "$output" == file:*"/datarim/reports/compliance-report-TUNE-0001.md" ]]
    [ -f "${output#*:}" ]
    [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "${output#*:}")" = "0o600" ]
}

@test "reserves the next versioned persistent path for a rerun" {
    local root="$BATS_TEST_TMPDIR/rerun"
    mkdir -p "$root/datarim/reports"
    : > "$root/datarim/reports/compliance-report-TUNE-0001.md"

    run python3 -I "$PATH_RESOLVER" --root "$root" --task-id TUNE-0001
    [ "$status" -eq 0 ]
    [ "$output" = "file:$root/datarim/reports/compliance-report-TUNE-0001-v2.md" ]
    [ -f "$root/datarim/reports/compliance-report-TUNE-0001-v2.md" ]
    [ ! -e "$root/datarim/reports/compliance-report-TUNE-0001-v3.md" ]
}

@test "chat-only mode uses a private temporary file and validates the bytes emitted" {
    local root="$BATS_TEST_TMPDIR/chat"
    local report_path temp_dir emitted

    mkdir -p "$root"
    run python3 -I "$PATH_RESOLVER" --root "$root" --task-id TUNE-0001
    [ "$status" -eq 0 ]
    [[ "$output" == chat:*"/report.md" ]]
    report_path="${output#*:}"
    temp_dir="$(dirname -- "$report_path")"
    [ ! -e "$root/datarim/reports" ]
    [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$temp_dir")" = "0o700" ]
    [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$report_path")" = "0o600" ]

    write_report '{"schema":"security-finding-evidence/v1","findings":[]}' "$report_path"
    run python3 -I "$SCRIPT" --report "$report_path"
    [ "$status" -eq 0 ]

    emitted="$BATS_TEST_TMPDIR/emitted-report.md"
    cat "$report_path" > "$emitted"
    cmp -s "$report_path" "$emitted"
}

@test "chat correction reruns the checker, resets status, and emits the corrected bytes" {
    local initial="$BATS_TEST_TMPDIR/initial-chat.md"
    local invalid="$BATS_TEST_TMPDIR/invalid-chat.md"
    local corrected="$BATS_TEST_TMPDIR/corrected-chat.md"
    local validator_snippet="$BATS_TEST_TMPDIR/validator-snippet.sh"
    local chat_snippet="$BATS_TEST_TMPDIR/chat-snippet.sh"
    local emitted="$BATS_TEST_TMPDIR/emitted-corrected.md"
    local checker_errors="$BATS_TEST_TMPDIR/checker-errors.txt"

    python3 - "$COMMAND" "$validator_snippet" "$chat_snippet" <<'PY'
import re
import sys
import textwrap
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = [textwrap.dedent(block) for block in re.findall(r"(?ms)^[ \t]*```bash[ \t]*\n(.*?)^[ \t]*```[ \t]*$", source)]
validator = [block[block.index("validate_security_finding_labels()"):] for block in blocks if "validate_security_finding_labels()" in block]
chat = [block for block in blocks if '[[ "$report_destination" == "chat"' in block]
if len(validator) != 1 or len(chat) != 1:
    raise SystemExit("expected one validator function block and one chat output block")
Path(sys.argv[2]).write_text(validator[0], encoding="utf-8")
Path(sys.argv[3]).write_text(chat[0], encoding="utf-8")
PY

    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-chat-retry",
        "evidence_label": "supported",
        "reproduction_state": "reproduced",
        "assessment_scope": "qualified_runtime",
        "scope": "One bounded chat-only path.",
        "mechanism": "An author assertion attempts to promote runtime evidence.",
        "evidence_refs": ["report.md#finding"],
        "origin": "author_reported",
        "witness": null,
        "custody_ref": null
      }]
    }' "$invalid"
    write_report '{
      "schema": "security-finding-evidence/v1",
      "findings": [{
        "id": "F-chat-retry",
        "evidence_label": "hypothesis",
        "reproduction_state": "not_attempted",
        "assessment_scope": "static",
        "scope": "One bounded chat-only path.",
        "mechanism": "The corrected report retains a static hypothesis without a runtime claim.",
        "evidence_refs": ["report.md#finding"],
        "origin": "author_reported",
        "witness": null,
        "custody_ref": null
      }]
    }' "$corrected"

    # The prior behavior retained status 1 after correction, suppressing chat output.
    cp -- "$invalid" "$initial"
    run env DATARIM_RUNTIME="$REPO_ROOT" report_path="$initial" report_destination=chat \
        VALIDATOR_SNIPPET="$validator_snippet" CORRECTED_REPORT="$corrected" CHAT_SNIPPET="$chat_snippet" CHECKER_ERRORS="$checker_errors" \
        bash -c 'source "$VALIDATOR_SNIPPET" 2>"$CHECKER_ERRORS"; [ "$label_validation_status" -eq 1 ] || exit 10; cp -- "$CORRECTED_REPORT" "$report_path"; source "$CHAT_SNIPPET"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    cp -- "$invalid" "$initial"
    run env DATARIM_RUNTIME="$REPO_ROOT" report_path="$initial" report_destination=chat \
        VALIDATOR_SNIPPET="$validator_snippet" CORRECTED_REPORT="$corrected" CHAT_SNIPPET="$chat_snippet" EMITTED="$emitted" CHECKER_ERRORS="$checker_errors" \
        bash -c 'source "$VALIDATOR_SNIPPET" 2>"$CHECKER_ERRORS"; [ "$label_validation_status" -eq 1 ] || exit 10; cp -- "$CORRECTED_REPORT" "$report_path"; validate_security_finding_labels 2>>"$CHECKER_ERRORS"; [ "$label_validation_status" -eq 0 ] || exit 11; source "$CHAT_SNIPPET" > "$EMITTED"'
    [ "$status" -eq 0 ]
    cmp -s "$corrected" "$initial"
    cmp -s "$corrected" "$emitted"
}

@test "compliance report template contains a valid no-claim positive example" {
    grep -q '^### Security finding evidence' "$TEMPLATE"
    run python3 -I "$SCRIPT" --report "$TEMPLATE"
    [ "$status" -eq 0 ]
}

write_report() {
    local destination="${2:-$REPORT}"
    cat > "$destination" <<EOF
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

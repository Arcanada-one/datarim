#!/usr/bin/env bats

setup() {
    umask 077
    CHECKER="$BATS_TEST_DIRNAME/../dev-tools/check-agent-frontmatter.sh"
    ROOT="$BATS_TEST_TMPDIR/root with spaces"$'\t'"and-tab"
    : "${AGENT_SUMMARY_EVIDENCE_DIR:?set a private evidence directory for this run}"
    mkdir -p "$ROOT/config" "$ROOT/agents"
    printf 'tiers:\n  custom_tier:\t\n    description: synthetic\n' >"$ROOT/config/model-tiers.yaml"
}

snapshot_inputs() {
    local file
    sha256sum -- "$CHECKER"
    if [[ -f "$ROOT/config/model-tiers.yaml" ]]; then
        sha256sum -- "$ROOT/config/model-tiers.yaml"
    else
        printf 'MISSING  %s\n' "$ROOT/config/model-tiers.yaml"
    fi
    for file in "$ROOT"/agents/*.md; do
        [[ -f "$file" ]] || continue
        sha256sum -- "$file"
    done
}

run_cli() {
    local case_id="$1"
    shift
    local evidence="$AGENT_SUMMARY_EVIDENCE_DIR/$case_id"
    local stdout_file="$evidence.stdout.raw"
    local stderr_file="$evidence.stderr.raw"
    local argv_file="$evidence.argv.nul"
    local before_file="$evidence.inputs.before.sha256"
    local after_file="$evidence.inputs.after.sha256"
    local metadata_file="$evidence.process.txt"
    local started ended cwd pid rc fixture_count=0 file

    [[ -f "$ROOT/config/model-tiers.yaml" ]] && fixture_count=1
    for file in "$ROOT"/agents/*.md; do
        [[ -f "$file" ]] || continue
        fixture_count=$((fixture_count + 1))
    done

    printf '%s\0' "$CHECKER" "$@" >"$argv_file"
    snapshot_inputs >"$before_file"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cwd="$PWD"
    "$CHECKER" "$@" >"$stdout_file" 2>"$stderr_file" &
    pid=$!
    if wait "$pid"; then
        rc=0
    else
        rc=$?
    fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    snapshot_inputs >"$after_file"
    printf 'case_id=%s\nargv_nul=%s\ncwd=%s\npid=%s\nstart_utc=%s\nend_utc=%s\nnumeric_exit=%s\nfixture_file_count=%s\nsource_and_input_hashes_before=%s\nsource_and_input_hashes_after=%s\n' \
        "$case_id" "$argv_file" "$cwd" "$pid" "$started" "$ended" "$rc" "$fixture_count" "$before_file" "$after_file" >"$metadata_file"

    status="$rc"
    if [[ -s "$stdout_file" ]]; then
        output="$(<"$stdout_file")"
    else
        output="$(<"$stderr_file")"
    fi

    if ! cmp -s "$before_file" "$after_file"; then
        printf 'input immutability assertion failed for %s\n' "$case_id" >&2
        return 1
    fi
}

write_valid_agent() {
    local path="$1"
    cat >"$path" <<'YAML'
---
name: Example
description: Synthetic fixture
model: inherit
metadata:
  model_tier: custom_tier
---
YAML
}

@test "summary reports a completed valid scan with fixed six-field shape" {
    write_valid_agent "$ROOT/agents/agent.md"

    run_cli pass --root "$ROOT" --summary-json

    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED"}' ]
}

@test "completed invalid scan uses fixed code and redacts hostile values" {
    cat >"$ROOT/agents/hostile-name-secret-tier.md" <<'YAML'
---
name:
description:
model: private-model-value
metadata:
  model_tier: private-tier-value
---
YAML

    run_cli invalid --root "$ROOT" --summary-json

    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["AGENT_FRONTMATTER_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}' ]
    [[ "$output" != *private-model-value* ]]
    [[ "$output" != *private-tier-value* ]]
    [[ "$output" != *hostile-name-secret-tier* ]]
}

@test "missing registry has unknown count rather than measured zero" {
    rm "$ROOT/config/model-tiers.yaml"

    run_cli missing-registry --root "$ROOT" --summary-json

    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["TIER_REGISTRY_UNAVAILABLE"],"checked_count":null,"checked_count_status":"NOT_MEASURED"}' ]
}

@test "unparsed registry returns the same unavailable branch without leaking values" {
    printf 'not_tiers:\n  private_registry_content:\t\n' >"$ROOT/config/model-tiers.yaml"

    run_cli unparsed-registry --root "$ROOT" --summary-json

    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["TIER_REGISTRY_UNAVAILABLE"],"checked_count":null,"checked_count_status":"NOT_MEASURED"}' ]
    [[ "$output" != *private_registry_content* ]]
}

@test "empty agent set is measured as zero after a valid registry read" {
    run_cli empty --root "$ROOT" --summary-json

    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["NO_AGENT_FILES"],"checked_count":0,"checked_count_status":"MEASURED"}' ]
}

@test "whitespace paths and tabbed tier registry parse with default and JSON parity" {
    write_valid_agent "$ROOT/agents/one with spaces"$'\t'"name.md"
    write_valid_agent "$ROOT/agents/two.md"

    run_cli default --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = $'\n=== Summary ===\nchecked=2 agent frontmatter blocks (allowed tiers: custom_tier )\nRESULT: PASS' ]
    [ ! -s "$AGENT_SUMMARY_EVIDENCE_DIR/default.stderr.raw" ]

    run_cli multiple --root "$ROOT" --summary-json
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":2,"checked_count_status":"MEASURED"}' ]
    [ ! -s "$AGENT_SUMMARY_EVIDENCE_DIR/multiple.stderr.raw" ]
}

@test "help unknown argument and root change failures remain outside summary output" {
    run_cli help --summary-json --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: check-agent-frontmatter.sh"* ]]
    [[ "$output" != *'DatarimAgentFrontmatterValidationSummary/v1'* ]]

    run_cli unknown --summary-json --unknown-private-arg
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown arg: --unknown-private-arg"* ]]

    run_cli bad-root --root "$ROOT/absent" --summary-json
    [ "$status" -ne 0 ]
    [[ "$output" != *'DatarimAgentFrontmatterValidationSummary/v1'* ]]
}

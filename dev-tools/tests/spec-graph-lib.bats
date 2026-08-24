#!/usr/bin/env bats
#
# bats spec for scripts/lib/spec-graph.sh — the shared spec-traceability library
# (R7 common validator contract). Asserts: emit_finding produces valid one-line
# JSON, usage_die exits 2, parse_common_flags rejects unknown flags (exit 2),
# and the registry loader helpers parse dr-spec-rules.yaml.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../scripts/lib/spec-graph.sh"
    RULES="${BATS_TEST_DIRNAME}/../dr-spec-rules.yaml"
    WORK="$(mktemp -d)"
    cd "$WORK"
}

teardown() {
    rm -rf "$WORK"
}

@test "lib sources cleanly without executing" {
    run bash -c "source '$LIB'"
    [ "$status" -eq 0 ]
}

@test "emit_finding produces valid one-line JSON" {
    run bash -c "
        source '$LIB'
        emit_finding high correctness my-check artifact.md 'AC-1' file_quote artifact.md:5 'an excerpt'
    "
    [ "$status" -eq 0 ]
    # exactly one line
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
    # valid JSON
    printf '%s\n' "$output" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]'
}

@test "emit_finding JSON carries the contract fields" {
    run bash -c "
        source '$LIB'
        emit_finding medium completeness covers-resolves doc.md 'V-AC-2' absent doc.md:10 'missing covers'
    "
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c '
import json,sys
f=json.loads(sys.stdin.read())
assert f["severity"]=="medium", f
assert f["category"]=="completeness", f
assert f["check_name"]=="covers-resolves", f
assert f["source_layer"]=="spec-lint", f
assert f["evidence"]["type"]=="absent", f
assert "finding_id" in f, f
'
}

@test "usage_die exits 2" {
    run bash -c "source '$LIB'; usage_die 'bad usage'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"bad usage"* ]]
}

@test "parse_common_flags rejects unknown flag with exit 2" {
    run bash -c "source '$LIB'; parse_common_flags --bogus"
    [ "$status" -eq 2 ]
}

@test "parse_common_flags accepts --format json" {
    run bash -c "
        source '$LIB'
        parse_common_flags --format json
        echo \"FMT=\$SPEC_FORMAT\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"FMT=json"* ]]
}

@test "parse_common_flags rejects invalid --format value with exit 2" {
    run bash -c "source '$LIB'; parse_common_flags --format xml"
    [ "$status" -eq 2 ]
}

@test "load_rules parses the registry into rule ids" {
    run bash -c "
        source '$LIB'
        load_rules '$RULES'
        printf '%s\n' \"\${SPEC_RULE_IDS[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"dreq-id-format"* ]]
    [[ "$output" == *"graph-complete-l3"* ]]
}

@test "is_mandatory reports true for a mandatory rule" {
    run bash -c "
        source '$LIB'
        load_rules '$RULES'
        if is_mandatory graph-complete-l3; then echo MANDATORY; else echo OPTIONAL; fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANDATORY"* ]]
}

@test "rule_severity returns the registry severity" {
    run bash -c "
        source '$LIB'
        load_rules '$RULES'
        rule_severity dreq-id-format
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "error" ]]
}

@test "customer requirement links become Requirement to V-AC edges" {
    cat >"$WORK/expectations.md" <<'EOF'
---
schema_version: 4
---
- **1. Visitor result.**
  - wish_id: visitor-result
  - customer_derived: true
  - requirement_id: req-0001
  - Связанный AC из PRD: V-AC-7
  - #### Текущий статус
    - pending
EOF
    run bash -c "source '$LIB'; collect_customer_requirement_vac_edges '$WORK/expectations.md'"
    [ "$status" -eq 0 ] \
      && [ "$output" = $'req-0001\tV-AC-7\texpectations.md' ]
}

@test "legacy or commented customer metadata does not create graph edges" {
    cat >"$WORK/expectations.md" <<'EOF'
---
schema_version: 3
---
- **1. Legacy wish.**
  - wish_id: legacy-wish
  - customer_derived: true
  - requirement_id: req-0001
  - Связанный AC из PRD: V-AC-7
<!--
  - wish_id: commented-wish
  - customer_derived: true
  - requirement_id: req-0002
  - Связанный AC из PRD: V-AC-8
-->
EOF
    run bash -c "source '$LIB'; collect_customer_requirement_vac_edges '$WORK/expectations.md'"
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "customer receipt becomes evidence implementation live and customer edges" {
    cat >"$WORK/receipt.yaml" <<'EOF'
requirements:
  req-0001:
    coverage_status: MET
    coverage_chain:
      requirement:
        requirement_id: req-0001
      selected_knowledge:
        roles: []
      implementation_delta:
        task_id: task:web:0001
      red_green:
        red: {}
        green: {}
      live_evidence:
        evidence_ref: artifacts/live.json
      customer_disposition:
        status: accepted
EOF
    run bash -c "source '$LIB'; collect_customer_receipt_edges '$WORK/receipt.yaml'"
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF $'req-0001\tselected_knowledge' \
      && printf '%s\n' "$output" | grep -qF $'req-0001\tred_green' \
      && printf '%s\n' "$output" | grep -qF $'req-0001\timplementation_delta' \
      && printf '%s\n' "$output" | grep -qF $'req-0001\tlive_evidence' \
      && printf '%s\n' "$output" | grep -qF $'req-0001\tcustomer_disposition'
}

@test "selected knowledge collector requires immutable revision digest and timestamp" {
    cat >"$WORK/receipt.yaml" <<'EOF'
requirements:
  req-0001:
    coverage_chain:
      selected_knowledge:
        roles:
          - id: reviewer
            revision: "1"
            digest: sha256:1111111111111111111111111111111111111111111111111111111111111111
            selected_at: "2026-01-02T09:10:00Z"
            selected_before_implementation: true
            immutable: true
        skills: [{id: incomplete-inline-entry}]
EOF
    run bash -c "source '$LIB'; collect_customer_selected_knowledge_kinds '$WORK/receipt.yaml'"
    [ "$status" -eq 0 ] \
      && [ "$output" = $'req-0001\troles' ]
}

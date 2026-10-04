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

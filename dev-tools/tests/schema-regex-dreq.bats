#!/usr/bin/env bats
#
# bats spec for the spec-traceability regex constants in
# scripts/lib/schema-regex.sh (R2): D_REQ_ID_RE, COVERS_LINE_RE, D_REQ_REF_RE.
# Asserts each accepts canonical examples and rejects malformed ones.

setup() {
    REGEX_LIB="${BATS_TEST_DIRNAME}/../../scripts/lib/schema-regex.sh"
}

# match <regex-var> <string> -> exit 0 if it matches
match() {
    REGEX_VAR="$1" SUBJECT="$2" bash -c '
        source "'"$REGEX_LIB"'"
        eval "rx=\${$REGEX_VAR}"
        printf "%s" "$SUBJECT" | grep -qE "$rx"
    '
}

@test "D_REQ_ID_RE accepts canonical heading" {
    run match D_REQ_ID_RE '#### D-REQ-01: the validator must build a graph'
    [ "$status" -eq 0 ]
}

@test "D_REQ_ID_RE accepts two-digit ids" {
    run match D_REQ_ID_RE '#### D-REQ-42: another requirement'
    [ "$status" -eq 0 ]
}

@test "D_REQ_ID_RE rejects single-digit id" {
    run match D_REQ_ID_RE '#### D-REQ-1: bad single digit'
    [ "$status" -ne 0 ]
}

@test "D_REQ_ID_RE rejects missing description" {
    run match D_REQ_ID_RE '#### D-REQ-01:'
    [ "$status" -ne 0 ]
}

@test "D_REQ_ID_RE rejects wrong heading level" {
    run match D_REQ_ID_RE '### D-REQ-01: wrong level'
    [ "$status" -ne 0 ]
}

@test "D_REQ_ID_RE rejects trailing garbage in id" {
    run match D_REQ_ID_RE '#### D-REQ-99x: trailing letter'
    [ "$status" -ne 0 ]
}

@test "COVERS_LINE_RE accepts single id" {
    run match COVERS_LINE_RE 'Covers: D-REQ-01'
    [ "$status" -eq 0 ]
}

@test "COVERS_LINE_RE accepts multiple ids" {
    run match COVERS_LINE_RE 'Covers: D-REQ-01, D-REQ-02, D-REQ-10'
    [ "$status" -eq 0 ]
}

@test "COVERS_LINE_RE accepts indented line" {
    run match COVERS_LINE_RE '   Covers: D-REQ-03'
    [ "$status" -eq 0 ]
}

@test "COVERS_LINE_RE rejects wrong prefix" {
    run match COVERS_LINE_RE 'Covers: REQ-01'
    [ "$status" -ne 0 ]
}

@test "COVERS_LINE_RE rejects trailing comma" {
    run match COVERS_LINE_RE 'Covers: D-REQ-01,'
    [ "$status" -ne 0 ]
}

@test "COVERS_LINE_RE rejects single-digit id" {
    run match COVERS_LINE_RE 'Covers: D-REQ-1'
    [ "$status" -ne 0 ]
}

@test "D_REQ_REF_RE matches a bare reference token" {
    run match D_REQ_REF_RE 'see D-REQ-07 for detail'
    [ "$status" -eq 0 ]
}

@test "D_REQ_REF_RE does not match single-digit ref" {
    run bash -c "source '$REGEX_LIB'; printf '%s' 'D-REQ-7' | grep -oE \"\$D_REQ_REF_RE\""
    [ "$status" -ne 0 ]
}

@test "VERIFIES_LINE_RE accepts explicit multiple V-AC plan edge" {
    run match VERIFIES_LINE_RE '  Verifies: V-AC-1, V-AC-2.1'
    [ "$status" -eq 0 ]
}

@test "VERIFIES_LINE_RE rejects incidental V-AC prose" {
    run match VERIFIES_LINE_RE 'This mentions V-AC-1 in prose.'
    [ "$status" -ne 0 ]
}

@test "EVIDENCE_LINE_RE accepts canonical evidence edge" {
    run match EVIDENCE_LINE_RE '- Evidence: V-AC-1 — bats tests/example.bats'
    [ "$status" -eq 0 ]
}

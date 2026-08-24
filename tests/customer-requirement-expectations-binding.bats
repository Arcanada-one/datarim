#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    DELIVERY_SKILL="${REPO_ROOT}/skills/customer-delivery/SKILL.md"
    EXPECTATIONS_SKILL="${REPO_ROOT}/skills/expectations-checklist/SKILL.md"
    EXPECTATIONS_TEMPLATE="${REPO_ROOT}/templates/expectations-template.md"
}

assert_contains() {
    local file="$1"
    local literal="$2"

    grep -Fq -- "$literal" "$file"
}

@test "customer delivery skill is a valid history-agnostic skill entrypoint" {
    [[ -f "$DELIVERY_SKILL" ]]
    assert_contains "$DELIVERY_SKILL" 'name: customer-delivery'
    assert_contains "$DELIVERY_SKILL" 'description:'
    [[ "$(grep -cE '^## U[1-8]\.' "$DELIVERY_SKILL")" -eq 8 ]]
    ! grep -Eq '[A-Z]{2,10}-[0-9]{4}' "$DELIVERY_SKILL"
}

@test "customer delivery skill preserves verbatim remarks under atomic stable requirement IDs" {
    assert_contains "$DELIVERY_SKILL" 'verbatim'
    assert_contains "$DELIVERY_SKILL" 'atomic'
    assert_contains "$DELIVERY_SKILL" 'stable Requirement ID'
    assert_contains "$DELIVERY_SKILL" 'paraphrase'
}

@test "customer delivery skill defines the complete acceptance and pre-work contracts" {
    for literal in \
        'before-state' 'after-state' 'evidence method' 'responsible owner' \
        'role' 'skill' 'blueprint' 'constraint' 'policy' 'success criterion' \
        'selected before implementation starts' 'post-hoc attribution' \
        'Gap' 'Unbound'; do
        assert_contains "$DELIVERY_SKILL" "$literal"
    done
}

@test "customer delivery skill defines coverage closure and review evolution semantics" {
    for literal in \
        'red/green evidence' 'merged revision' 'deployed revision' \
        'live evidence' 'customer disposition' 'NOT MET' \
        'green CI != deployed' 'deployed != visually accepted' \
        'enabling work != customer outcome' 'derived from the Requirement graph' \
        'ABSENT' 'WEAK' 'STALE' 'MIS_SCOPED' 'NOT_BOUND' 'NO_CANON_CHANGE'; do
        assert_contains "$DELIVERY_SKILL" "$literal"
    done
}

@test "customer delivery skill separates enabling and visitor-visible output" {
    assert_contains "$DELIVERY_SKILL" 'enabling changes'
    assert_contains "$DELIVERY_SKILL" 'visitor-visible changes'
    assert_contains "$DELIVERY_SKILL" 'zero visitor-visible changes'
    assert_contains "$DELIVERY_SKILL" 'cannot satisfy'
}

@test "customer delivery skill requires the complete painted visual matrix" {
    for literal in 'RU' 'EN' 'mobile' 'desktop' 'light' 'dark' 'operator'; do
        assert_contains "$DELIVERY_SKILL" "$literal"
    done
    assert_contains "$DELIVERY_SKILL" 'cannot replace'
}

@test "new customer expectation examples bind requirement surface visibility and receipt" {
    for literal in \
        'requirement_id: {req-NNNN}' \
        'surface_class: {VISITOR_VISIBLE | ENABLING}' \
        'visitor_visible: {true | false}' \
        'delivery_receipt: {datarim/receipts/{TASK-ID}-customer-delivery.yaml}'; do
        count="$(grep -Fc -- "$literal" "$EXPECTATIONS_TEMPLATE")"
        [[ "$count" -eq 2 ]]
    done
}

@test "expectations contract makes customer binding mandatory without invalidating legacy files" {
    assert_contains "$EXPECTATIONS_SKILL" 'Every new wish derived from a customer remark MUST carry these four fields:'
    assert_contains "$EXPECTATIONS_SKILL" 'requirement_id'
    assert_contains "$EXPECTATIONS_SKILL" 'surface_class'
    assert_contains "$EXPECTATIONS_SKILL" 'visitor_visible'
    assert_contains "$EXPECTATIONS_SKILL" 'delivery_receipt'
    assert_contains "$EXPECTATIONS_SKILL" 'Legacy expectations files'
    assert_contains "$EXPECTATIONS_SKILL" 'remain valid without these fields'
}

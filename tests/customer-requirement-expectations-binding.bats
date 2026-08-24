#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    CHECK_EXPECTATIONS="${REPO_ROOT}/dev-tools/check-expectations-checklist.sh"
    DELIVERY_SKILL="${REPO_ROOT}/skills/customer-delivery/SKILL.md"
    EXPECTATIONS_SKILL="${REPO_ROOT}/skills/expectations-checklist/SKILL.md"
    EXPECTATIONS_TEMPLATE="${REPO_ROOT}/templates/expectations-template.md"
    SKILLS_REFERENCE="${REPO_ROOT}/documentation/reference/skills.md"
}

assert_contains() {
    local file="$1"
    local literal="$2"

    grep -Fq -- "$literal" "$file"
}

template_has_exact_binding_bullets() {
    local file="$1"
    local item_count
    local field

    item_count="$(grep -cE '^- \*\*[0-9]+\. ' "$file")"
    [ "$item_count" -gt 0 ] || return 1
    for field in customer_requirement requirement_id surface_class visitor_visible delivery_receipt; do
        [ "$(grep -cE "^  - ${field}:" "$file")" -eq "$item_count" ] || return 1
    done
}

write_expectations() {
    local id="$1"
    local schema="$2"
    local binding="${3:-}"
    local evidence=""
    local file="${BATS_TEST_TMPDIR}/${id}/datarim/tasks/${id}-expectations.md"

    mkdir -p "$(dirname "$file")"
    if [ "$schema" -ge 2 ]; then
        evidence="  - evidence_type: static"
    fi
    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: $schema
captured_at: 2026-08-24
captured_by: /dr-prd
status: canonical
---

# $id expectations

## Ожидания

- **1. Customer outcome.**
  - wish_id: customer-outcome
  - Что хочу проверить: The requested outcome is delivered.
  - Как проверить (success criterion): A deterministic signal passes.
  - Связанный AC из PRD: V-AC-1
$binding
$evidence
  - #### История статусов
    - 2026-08-24T00:00:00Z / 2026-08-24 00:00 (UTC) · pending → pending · /dr-prd · reason: item created
  - #### Текущий статус
    - pending
EOF
    printf '%s\n' "${BATS_TEST_TMPDIR}/${id}"
}

valid_customer_binding() {
    local id="$1"
    cat <<EOF
  - customer_requirement: customer-derived
  - requirement_id: req-0001
  - surface_class: VISITOR_VISIBLE
  - visitor_visible: true
  - delivery_receipt: datarim/receipts/${id}-customer-delivery.yaml
EOF
}

@test "customer delivery skill is a valid history-agnostic skill entrypoint" {
    [[ -f "$DELIVERY_SKILL" ]]
    assert_contains "$DELIVERY_SKILL" 'name: customer-delivery'
    assert_contains "$DELIVERY_SKILL" 'description:'
    description="$(sed -n 's/^description: //p' "$DELIVERY_SKILL")"
    [[ "${#description}" -le 155 ]]
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
    template_has_exact_binding_bullets "$EXPECTATIONS_TEMPLATE"
}

@test "commented customer binding bullets do not satisfy the template contract" {
    local mutant="${BATS_TEST_TMPDIR}/commented-bindings.md"
    cp "$EXPECTATIONS_TEMPLATE" "$mutant"
    sed -E -i 's/^(  - (requirement_id|surface_class|visitor_visible|delivery_receipt):.*)$/<!-- \1 -->/' "$mutant"

    run template_has_exact_binding_bullets "$mutant"
    [ "$status" -ne 0 ]
}

@test "schema v4 customer-derived wish with complete binding passes" {
    local id="BIND-0001"
    local root
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 0 ]
}

@test "schema v4 new artifact with zero binding fields fails closed" {
    local id="BIND-0002"
    local root
    root="$(write_expectations "$id" 4)"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing customer_requirement"* ]] \
        && [[ "$output" != *"schema_version must"* ]]
}

@test "schema v4 HTML-commented binding fields fail closed" {
    local id="BIND-0003"
    local binding
    local root
    binding="$(valid_customer_binding "$id" | sed -E 's/^(  - (requirement_id|surface_class|visitor_visible|delivery_receipt):.*)$/<!-- \1 -->/')"
    root="$(write_expectations "$id" 4 "$binding")"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing requirement_id"* ]] \
        && [[ "$output" != *"schema_version must"* ]]
}

@test "schema v4 rejects removal of every customer-derived binding field" {
    local field
    local id
    local binding
    local root
    for field in customer_requirement requirement_id surface_class visitor_visible delivery_receipt; do
        id="BIND-0004"
        binding="$(valid_customer_binding "$id" | sed -E "/^  - ${field}:/d")"
        root="$(write_expectations "$id" 4 "$binding")"
        run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
        if [ "$status" -ne 1 ] || [[ "$output" != *"missing ${field}"* ]]; then
            echo "field-removal mutant survived: ${field}" >&2
            return 1
        fi
        rm -rf "$root"
    done
}

@test "schema v4 not-applicable wish requires a reason and passes without binding fields" {
    local id="BIND-0005"
    local root
    root="$(write_expectations "$id" 4 $'  - customer_requirement: not-applicable\n  - customer_requirement_reason: Internal framework-only wish')"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 0 ]
}

@test "schema v4 not-applicable wish without a reason fails closed" {
    local id="BIND-0006"
    local root
    root="$(write_expectations "$id" 4 '  - customer_requirement: not-applicable')"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing customer_requirement_reason"* ]]
}

@test "schema v4 rejects inconsistent visitor visibility" {
    local id="BIND-0007"
    local binding
    local root
    binding="$(valid_customer_binding "$id" | sed 's/visitor_visible: true/visitor_visible: false/')"
    root="$(write_expectations "$id" 4 "$binding")"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"surface_class and visitor_visible disagree"* ]]
}

@test "legacy schema versions v1 through v3 remain valid without customer binding" {
    local schema
    local id
    local root
    for schema in 1 2 3; do
        id="LEGA-000${schema}"
        root="$(write_expectations "$id" "$schema")"
        run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
        if [ "$status" -ne 0 ]; then
            echo "legacy schema v${schema} rejected: ${output}" >&2
            return 1
        fi
    done
}

@test "expectations contract makes customer binding mandatory without invalidating legacy files" {
    assert_contains "$EXPECTATIONS_SKILL" 'schema_version: 4'
    assert_contains "$EXPECTATIONS_SKILL" 'customer_requirement'
    assert_contains "$EXPECTATIONS_SKILL" 'requirement_id'
    assert_contains "$EXPECTATIONS_SKILL" 'surface_class'
    assert_contains "$EXPECTATIONS_SKILL" 'visitor_visible'
    assert_contains "$EXPECTATIONS_SKILL" 'delivery_receipt'
    assert_contains "$EXPECTATIONS_SKILL" 'Legacy expectations files'
    assert_contains "$EXPECTATIONS_SKILL" 'remain valid without these fields'
}

@test "customer delivery skill is registered in the canonical skills inventory" {
    assert_contains "$SKILLS_REFERENCE" '| customer-delivery | Reference |'

    disk_count="$(find "${REPO_ROOT}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d '[:space:]')"
    documented_count="$(sed -nE 's/^Datarim includes ([0-9]+) reusable skill modules\..*/\1/p' "$SKILLS_REFERENCE")"
    [[ "$documented_count" -eq "$disk_count" ]]
}

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
    [ "$(grep -cE '^schema_version: 4$' "$file")" -eq 1 ] || return 1
    [ "$(grep -cE '^customer_binding_from:' "$file")" -eq 0 ] || return 1
    for field in customer_derived requirement_id surface_class visitor_visible delivery_receipt; do
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
  - customer_derived: true
  - requirement_id: req-0001
  - surface_class: VISITOR_VISIBLE
  - visitor_visible: true
  - delivery_receipt: datarim/receipts/${id}-customer-delivery.yaml
EOF
}

write_migrated_expectations() {
    local id="$1"
    local root="${BATS_TEST_TMPDIR}/${id}"
    local file="${root}/datarim/tasks/${id}-expectations.md"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 4
captured_at: 2026-05-14
captured_by: /dr-prd
status: amended
---

## Ожидания

- **1. Preserved legacy wish.**
  - wish_id: preserved-legacy-wish
  - customer_derived: false
  - evidence_type: static
  - #### История статусов
    - 2026-05-14T00:00:00Z / 2026-05-14 00:00 (UTC) · pending → pending · /dr-prd · reason: item created
  - #### Текущий статус
    - pending

- **2. Appended customer wish.**
  - wish_id: appended-customer-wish
$(valid_customer_binding "$id")
  - evidence_type: static
  - #### История статусов
    - 2026-08-24T00:00:00Z / 2026-08-24 00:00 (UTC) · pending → pending · /dr-prd · reason: item appended
  - #### Текущий статус
    - pending

- **3. Appended non-customer wish.**
  - wish_id: appended-internal-wish
  - customer_derived: false
  - evidence_type: static
  - #### История статусов
    - 2026-08-24T00:00:00Z / 2026-08-24 00:00 (UTC) · pending → pending · /dr-prd · reason: item appended
  - #### Текущий статус
    - pending
EOF
    printf '%s\n' "$root"
}

@test "customer delivery skill is a valid history-agnostic skill entrypoint" {
    [[ -f "$DELIVERY_SKILL" ]] || return 1
    assert_contains "$DELIVERY_SKILL" 'name: customer-delivery' || return 1
    assert_contains "$DELIVERY_SKILL" 'description:' || return 1
    description="$(sed -n 's/^description: //p' "$DELIVERY_SKILL")"
    [[ "${#description}" -le 155 ]] || return 1
    [[ "$(grep -cE '^## U[1-8]\.' "$DELIVERY_SKILL")" -eq 8 ]] || return 1
    if grep -Eq '[A-Z]{2,10}-[0-9]{4}' "$DELIVERY_SKILL"; then return 1; fi
}

@test "customer delivery skill preserves verbatim remarks under atomic stable requirement IDs" {
    assert_contains "$DELIVERY_SKILL" 'verbatim' || return 1
    assert_contains "$DELIVERY_SKILL" 'atomic' || return 1
    assert_contains "$DELIVERY_SKILL" 'stable Requirement ID' || return 1
    assert_contains "$DELIVERY_SKILL" 'paraphrase'
}

@test "customer delivery skill defines the complete acceptance and pre-work contracts" {
    for literal in \
        'before-state' 'after-state' 'evidence method' 'responsible owner' \
        'role' 'skill' 'blueprint' 'constraint' 'policy' 'success criterion' \
        'selected before implementation starts' 'post-hoc attribution' \
        'Gap' 'Unbound'; do
        assert_contains "$DELIVERY_SKILL" "$literal" || return 1
    done
}

@test "customer delivery skill defines coverage closure and review evolution semantics" {
    for literal in \
        'red/green evidence' 'merged revision' 'deployed revision' \
        'live evidence' 'customer disposition' 'NOT MET' \
        'green CI != deployed' 'deployed != visually accepted' \
        'enabling work != customer outcome' 'derived from the Requirement graph' \
        'ABSENT' 'WEAK' 'STALE' 'MIS_SCOPED' 'NOT_BOUND' 'NO_CANON_CHANGE'; do
        assert_contains "$DELIVERY_SKILL" "$literal" || return 1
    done
}

@test "customer delivery skill separates enabling and visitor-visible output" {
    assert_contains "$DELIVERY_SKILL" 'enabling changes' || return 1
    assert_contains "$DELIVERY_SKILL" 'visitor-visible changes' || return 1
    assert_contains "$DELIVERY_SKILL" 'zero visitor-visible changes' || return 1
    assert_contains "$DELIVERY_SKILL" 'cannot satisfy'
}

@test "customer delivery skill requires the complete painted visual matrix" {
    for literal in 'RU' 'EN' 'mobile' 'desktop' 'light' 'dark' 'operator'; do
        assert_contains "$DELIVERY_SKILL" "$literal" || return 1
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
        && [[ "$output" == *"missing customer_derived"* ]] \
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
    for field in customer_derived requirement_id surface_class visitor_visible delivery_receipt; do
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

@test "schema v4 non-customer wish passes without customer binding fields" {
    local id="BIND-0005"
    local root
    root="$(write_expectations "$id" 4 '  - customer_derived: false')"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 0 ]
}

@test "schema v4 wish without customer discriminator fails closed" {
    local id="BIND-0006"
    local root
    root="$(write_expectations "$id" 4)"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing customer_derived"* ]]
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

@test "schema v4 accepts a complete metadata-only migration with mixed wishes" {
    local id="BIND-0008"
    local root
    root="$(write_migrated_expectations "$id")"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 0 ]
}

@test "schema v4 amended file rejects a missing preexisting discriminator" {
    local id="BIND-0017"
    local root
    local file
    root="$(write_migrated_expectations "$id")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -E -i.bak '/^- \*\*1\./,/^- \*\*2\./ { /^  - customer_derived:/d; }' "$file"
    rm -f "${file}.bak"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing customer_derived"* ]]
}

@test "schema v4 rejects coordinated binding strip and cutover advance" {
    local id="BIND-0020"
    local root
    local file
    root="$(write_migrated_expectations "$id")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i.bak '/^schema_version: 4$/a\
customer_binding_from: appended-internal-wish' "$file"
    rm -f "${file}.bak"
    sed -E -i.bak '/^- \*\*2\./,/^- \*\*3\./ { /^  - (customer_derived|requirement_id|surface_class|visitor_visible|delivery_receipt):/d; }' "$file"
    rm -f "${file}.bak"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"customer_binding_from is obsolete in schema_version=4"* ]]
}

@test "verify blocks coordinated binding strip and cutover advance" {
    local id="BIND-0021"
    local root
    local file
    root="$(write_migrated_expectations "$id")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i.bak '/^schema_version: 4$/a\
customer_binding_from: appended-internal-wish' "$file"
    rm -f "${file}.bak"
    sed -E -i.bak '/^- \*\*2\./,/^- \*\*3\./ { /^  - (customer_derived|requirement_id|surface_class|visitor_visible|delivery_receipt):/d; }' "$file"
    rm -f "${file}.bak"

    run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"BLOCKED: expectations file fails structural validation"* ]]
}

@test "schema v4 rejects the obsolete customer binding marker" {
    local id="BIND-0009"
    local root
    local file
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i.bak '/^schema_version: 4$/a\
customer_binding_from: customer-outcome' "$file"
    rm -f "${file}.bak"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"customer_binding_from is obsolete in schema_version=4"* ]]
}

@test "schema v4 canonical file governs its first wish" {
    local id="BIND-0015"
    local root="${BATS_TEST_TMPDIR}/${id}"
    local file="${root}/datarim/tasks/${id}-expectations.md"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 4
captured_at: 2026-08-24
captured_by: /dr-prd
status: canonical
---

## Ожидания

- **1. First wish.**
  - wish_id: first-wish
  - evidence_type: static
  - #### История статусов
    - 2026-08-24T00:00:00Z / 2026-08-24 00:00 (UTC) · pending → pending · /dr-prd · reason: item created
  - #### Текущий статус
    - pending

- **2. Second wish.**
  - wish_id: second-wish
$(valid_customer_binding "$id")
  - evidence_type: static
  - #### История статусов
    - 2026-08-24T00:00:00Z / 2026-08-24 00:00 (UTC) · pending → pending · /dr-prd · reason: item created
  - #### Текущий статус
    - pending
EOF

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"item 1 missing customer_derived"* ]]
}

@test "schema v4 rejects an invalid frontmatter status" {
    local id="BIND-0022"
    local root
    local file
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i 's/status: canonical/status: canonica1/' "$file"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"frontmatter status must be 'canonical' or 'amended'"* ]]
}

@test "verify blocks an invalid frontmatter status" {
    local id="BIND-0023"
    local root
    local file
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i 's/status: canonical/status: canonica1/' "$file"

    run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"BLOCKED: expectations file fails structural validation"* ]]
}

@test "schema v4 rejects duplicate customer binding fields" {
    local id="BIND-0010"
    local binding
    local root
    binding="$(valid_customer_binding "$id")"$'\n  - requirement_id: req-0002'
    root="$(write_expectations "$id" 4 "$binding")"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"duplicate requirement_id"* ]]
}

@test "schema v4 customer_derived false forbids customer binding fields" {
    local id="BIND-0013"
    local root
    root="$(write_expectations "$id" 4 $'  - customer_derived: false\n  - requirement_id: req-0001')"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"customer_derived=false must omit customer binding fields"* ]]
}

@test "schema v4 rejects invalid ID boolean and receipt values" {
    local id="BIND-0011"
    local field
    local replacement
    local expected
    local binding
    local root
    while IFS='|' read -r field replacement expected; do
        binding="$(valid_customer_binding "$id" | sed -E "s@^(  - ${field}:).*@\\1 ${replacement}@")"
        root="$(write_expectations "$id" 4 "$binding")"
        run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
        if [ "$status" -ne 1 ] || [[ "$output" != *"${expected}"* ]]; then
            echo "invalid-value mutant survived for ${field}: ${output}" >&2
            return 1
        fi
        rm -rf "$root"
    done <<EOF
customer_derived|maybe|customer_derived must be boolean true|false
requirement_id|REQ-1|requirement_id must match req-NNNN
surface_class|INTERNAL|surface_class not in enum
visitor_visible|yes|visitor_visible must be boolean true|false
delivery_receipt|other.yaml|delivery_receipt must be datarim/receipts/${id}-customer-delivery.yaml
EOF
}

@test "schema v4 ignores binding fields inside multiline HTML comments" {
    local id="BIND-0012"
    local root
    root="$(write_expectations "$id" 4 $'  - customer_derived: true\n<!--\n  - requirement_id: req-0001\n  - surface_class: VISITOR_VISIBLE\n  - visitor_visible: true\n  - delivery_receipt: datarim/receipts/BIND-0012-customer-delivery.yaml\n-->')"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing requirement_id"* ]]
}

@test "schema v4 ignores an item header inside an HTML comment" {
    local id="BIND-0014"
    local root
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"
    sed -E -i 's/^(- \*\*1\. Customer outcome\.\*\*)$/<!-- \1 -->/' \
        "$root/datarim/tasks/${id}-expectations.md"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"no items found"* ]]
}

@test "schema v4 validates an active item header with a trailing HTML comment" {
    local id="BIND-0015"
    local root
    local file
    root="$(write_migrated_expectations "$id")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i 's/^- \*\*2\. Appended customer wish\.\*\*$/& <!-- active header trailing comment -->/' "$file"
    sed -i '/^  - customer_derived: true$/,/^  - delivery_receipt:/d' "$file"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"item 2 missing customer_derived"* ]] || return 1

    run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"BLOCKED: expectations file fails structural validation"* ]]
}

@test "schema validation rejects duplicate frontmatter keys in task and verify modes" {
    local id
    local root
    local file
    local key
    local duplicate
    for key in schema_version status; do
        id="DUPF-0001"
        root="$(write_expectations "$id" 3)"
        file="$root/datarim/tasks/${id}-expectations.md"
        case "$key" in
            schema_version) duplicate='schema_version: 4' ;;
            status) duplicate='status: canonica1' ;;
        esac
        sed -i "/^${key}:/a ${duplicate}" "$file"

        run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
        if [ "$status" -ne 1 ] || [[ "$output" != *"duplicate frontmatter field '${key}'"* ]]; then
            echo "duplicate ${key} passed task validation: ${output}" >&2
            return 1
        fi

        run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
        if [ "$status" -ne 1 ] || [[ "$output" != *"BLOCKED: expectations file fails structural validation"* ]]; then
            echo "duplicate ${key} passed verify validation: ${output}" >&2
            return 1
        fi
        rm -rf "$root"
    done
}

@test "active expectations heading with a trailing HTML comment passes both modes" {
    local id="HEAD-0001"
    local root
    local file
    root="$(write_expectations "$id" 4 "$(valid_customer_binding "$id")")"
    file="$root/datarim/tasks/${id}-expectations.md"
    sed -i 's/^## Ожидания$/& <!-- active heading trailing comment -->/' "$file"

    run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
    [ "$status" -eq 0 ] || return 1

    run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"PASS"* ]]
}

@test "verify mode blocks a structurally invalid schema v4 artifact" {
    local id="BIND-0016"
    local root
    root="$(write_expectations "$id" 4)"

    run "$CHECK_EXPECTATIONS" --verify "$id" --root "$root"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"BLOCKED: expectations file fails structural validation"* ]]
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

@test "legacy schema versions v1 through v3 reject an invalid frontmatter status" {
    local schema
    local id
    local root
    local file
    for schema in 1 2 3; do
        id="STAT-000${schema}"
        root="$(write_expectations "$id" "$schema")"
        file="$root/datarim/tasks/${id}-expectations.md"
        sed -i 's/status: canonical/status: canonica1/' "$file"
        run "$CHECK_EXPECTATIONS" --task "$id" --root "$root"
        if [ "$status" -ne 1 ] || [[ "$output" != *"frontmatter status must be 'canonical' or 'amended'"* ]]; then
            echo "legacy schema v${schema} accepted invalid status: ${output}" >&2
            return 1
        fi
    done
}

@test "expectations contract makes customer binding mandatory without invalidating legacy files" {
    assert_contains "$EXPECTATIONS_SKILL" 'schema_version: 4' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'customer_binding_from' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'customer_derived' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'requirement_id' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'surface_class' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'visitor_visible' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'delivery_receipt' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'Legacy expectations files' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'MUST NOT receive new wishes' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'metadata-only migration' || return 1
    assert_contains "$EXPECTATIONS_SKILL" 'remain valid without these fields'
}

@test "customer delivery skill is registered in the canonical skills inventory" {
    assert_contains "$SKILLS_REFERENCE" '| customer-delivery | Reference |' || return 1
    assert_contains "$SKILLS_REFERENCE" '| expectations-checklist | Reference | Operator wishlist artefact' || return 1
    assert_contains "$SKILLS_REFERENCE" 'Schema v4 requires explicit customer derivation' || return 1

    disk_count="$(find "${REPO_ROOT}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d '[:space:]')"
    documented_count="$(sed -nE 's/^Datarim includes ([0-9]+) reusable skill modules\..*/\1/p' "$SKILLS_REFERENCE")"
    [[ "$documented_count" -eq "$disk_count" ]]
}

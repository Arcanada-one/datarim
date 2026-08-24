#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

assert_contains() {
    local file="$1" literal="$2"
    grep -qF -- "$literal" "$file"
}

@test "init preserves every customer remark verbatim for atomic Requirement IDs" {
    assert_contains "$REPO_ROOT/commands/dr-init.md" \
        'Customer remarks (verbatim requirement intake)'
}

@test "init creates new expectations with current schema v4 customer classification" {
    assert_contains "$REPO_ROOT/commands/dr-init.md" 'schema_version: 4' \
      && assert_contains "$REPO_ROOT/commands/dr-init.md" 'customer_derived: true | false'
}

@test "PRD authors the complete customer acceptance tuple and live visitor AC" {
    local spec="$REPO_ROOT/commands/dr-prd.md"
    for literal in \
        'originating source and exact quotation' \
        'affected product and surface or route' \
        'locale, viewport, and theme dimensions' \
        'observable before-state and required after-state' \
        'evidence method and responsible owner' \
        'role, skill, blueprint, constraint, policy, and success criterion' \
        'delivery task, code/content paths, and target environment' \
        'customer disposition' \
        'observable visitor-facing change on the live production product'; do
        assert_contains "$spec" "$literal" || return 1
    done
}

@test "plan pins all six knowledge kinds before implementation and forbids post-hoc attribution" {
    local spec="$REPO_ROOT/commands/dr-plan.md"
    assert_contains "$spec" 'role, skill, blueprint, constraint, policy, and success criterion' \
      && assert_contains "$spec" 'immutable revision, digest, and selection timestamp' \
      && assert_contains "$spec" 'Selection after implementation starts is post-hoc attribution and fails'
}

@test "plan creates a NOT_MET receipt prefix before implementation" {
    local spec="$REPO_ROOT/commands/dr-plan.md"
    assert_contains "$spec" 'coverage_status: NOT_MET' \
      && assert_contains "$spec" 'requirement and selected_knowledge edges' \
      && assert_contains "$spec" 'before implementation starts'
}

@test "do blocks implementation until the customer receipt pre-work prefix is ready" {
    local spec="$REPO_ROOT/commands/dr-do.md"
    assert_contains "$spec" 'CUSTOMER DELIVERY RECEIPT PRE-WORK GATE' \
      && assert_contains "$spec" 'customer_delivery_prework' \
      && assert_contains "$spec" 'Do not write code or content until `prework_ready` is `true`'
}

@test "PRD and plan forbid appending to legacy expectations before full v4 migration" {
    for command in dr-prd dr-plan; do
        local spec="$REPO_ROOT/commands/${command}.md"
        assert_contains "$spec" 'v1-v3' \
          && assert_contains "$spec" 'full metadata-only migration to schema v4' \
          || return 1
    done
}

@test "QA hard-gates customer delivery and review evolution" {
    local spec="$REPO_ROOT/commands/dr-qa.md"
    assert_contains "$spec" 'check-customer-delivery.sh' \
      && assert_contains "$spec" '--stage qa' \
      && assert_contains "$spec" 'check-review-evolution.sh' \
      && assert_contains "$spec" 'semantic NOT_MET'
}

@test "compliance hard-gates customer delivery and review evolution" {
    local spec="$REPO_ROOT/commands/dr-compliance.md"
    assert_contains "$spec" 'check-customer-delivery.sh' \
      && assert_contains "$spec" '--stage compliance' \
      && assert_contains "$spec" 'check-review-evolution.sh' \
      && assert_contains "$spec" 'NON-COMPLIANT'
}

@test "archive hard-gates customer delivery and review evolution" {
    local spec="$REPO_ROOT/commands/dr-archive.md"
    assert_contains "$spec" 'check-customer-delivery.sh' \
      && assert_contains "$spec" '--stage archive' \
      && assert_contains "$spec" 'check-review-evolution.sh' \
      && assert_contains "$spec" 'STOP the archive'
}

@test "hard stage commands distinguish enabling evidence from visitor delivery" {
    for command in dr-qa dr-compliance dr-archive; do
        assert_contains "$REPO_ROOT/commands/${command}.md" \
            'Tools, documentation, tests, CI, and ledger output cannot satisfy a visitor-visible requirement' \
          || return 1
    done
}

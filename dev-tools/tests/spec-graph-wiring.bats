#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

@test "pipeline commands invoke the internal spec-graph gate automatically" {
    for file in dr-prd dr-plan dr-do dr-qa dr-compliance dr-verify; do
        grep -qF 'spec-graph-gate.sh' "$REPO_ROOT/commands/${file}.md" || return 1
    done
}

@test "customer hard stages invoke the delivery and review-evolution validators" {
    for pair in 'dr-qa qa' 'dr-compliance compliance' 'dr-archive archive'; do
        read -r command stage <<<"$pair"
        grep -qF 'check-customer-delivery.sh' "$REPO_ROOT/commands/$command.md" \
          && grep -qF -- "--stage $stage" "$REPO_ROOT/commands/$command.md" \
          && grep -qF 'check-review-evolution.sh' "$REPO_ROOT/commands/$command.md" \
          || return 1
    done
}

@test "do command consumes the spec-graph customer pre-work verdict" {
    grep -qF 'customer_delivery_prework' "$REPO_ROOT/commands/dr-do.md" \
      && grep -qF 'prework_ready' "$REPO_ROOT/commands/dr-do.md"
}

@test "spec graph declares customer edge collectors and external closure authority" {
    grep -qF 'collect_customer_requirement_vac_edges' "$REPO_ROOT/scripts/lib/spec-graph.sh" \
      && grep -qF 'collect_customer_receipt_edges' "$REPO_ROOT/scripts/lib/spec-graph.sh" \
      && grep -qF 'check-customer-delivery.sh' "$REPO_ROOT/dev-tools/spec-graph-gate.sh"
}

@test "pipeline agents carry graph authoring and verification responsibilities" {
    grep -qF 'Covers:' "$REPO_ROOT/agents/architect.md" \
      && grep -qF 'Verifies:' "$REPO_ROOT/agents/planner.md" \
      && grep -qF 'Evidence:' "$REPO_ROOT/agents/developer.md" \
      && grep -qF 'Layer 3c' "$REPO_ROOT/agents/reviewer.md" \
      && grep -qF 'spec-graph-gate.sh' "$REPO_ROOT/agents/compliance.md"
}

@test "graph skills describe automatic cross-layer bindings" {
    grep -qF 'Verifies:' "$REPO_ROOT/skills/expectations-checklist/SKILL.md" \
      && grep -qF 'spec-graph-gate.sh' "$REPO_ROOT/skills/self-verification/SKILL.md" \
      && grep -qF 'Evidence:' "$REPO_ROOT/skills/v-ac-axis-split/SKILL.md"
}

@test "templates seed mandatory Covers plus explicit plan and evidence markers" {
    grep -qF 'MUST carry a `Covers:` line' "$REPO_ROOT/templates/prd-template.md" \
      && grep -qF 'Verifies: V-AC-' "$REPO_ROOT/templates/task-template.md" \
      && grep -qF 'Evidence: V-AC-' "$REPO_ROOT/templates/task-template.md"
}

@test "rejected manual surfaces are absent" {
    [ ! -e "$REPO_ROOT/commands/dr-spec.md" ] \
      && [ ! -e "$REPO_ROOT/templates/pre-commit-spec-lint.sample" ] \
      && [ ! -e "$REPO_ROOT/.github/workflows/spec-traceability.yml" ]
}

@test "operator catalogs no longer advertise /dr-spec" {
    ! grep -qF '| `/dr-spec` |' "$REPO_ROOT/CLAUDE.md" \
      && ! grep -qF '| `/dr-spec` |' "$REPO_ROOT/README.md" \
      && ! grep -qF '| `/dr-spec` |' "$REPO_ROOT/documentation/reference/commands.md"
}

@test "internal engine helpers remain present" {
    for file in \
        dev-tools/dr-spec-lint.sh \
        dev-tools/dr-trace.sh \
        dev-tools/dr-lint.sh \
        dev-tools/dr-spec-grade.sh \
        dev-tools/dr-spec-rules.yaml \
        scripts/lib/spec-graph.sh \
        scripts/lib/schema-regex.sh; do
        [ -f "$REPO_ROOT/$file" ] || return 1
    done
}

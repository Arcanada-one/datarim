#!/usr/bin/env bats
# tests/test-role-registry.bats — Fleet role registry validator tests.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    VALIDATOR="$REPO/dev-tools/check-role-registry.sh"
    ROLES="$REPO/config/roles.yaml"
    SCHEMA="$REPO/config/role-registry.schema.json"
    TMP="$BATS_TEST_TMPDIR"
}

@test "validator script exists and is executable" {
    [ -x "$VALIDATOR" ]
}

@test "schema file exists" {
    [ -f "$SCHEMA" ]
}

@test "seed roles.yaml passes validation (exit 0)" {
    run "$VALIDATOR" --file "$ROLES"
    [ "$status" -eq 0 ]
}

@test "seed roles.yaml has >=6 roles" {
    run yq -r '.roles | length' "$ROLES"
    [ "$status" -eq 0 ]
    [ "$output" -ge 6 ]
}

@test "global_max_parallel is 8 (operator cap)" {
    run yq -r '.global_max_parallel' "$ROLES"
    [ "$output" -eq 8 ]
}

@test "every role declares complexity_levels AND default_aal (two separate axes)" {
    # no role may omit either field — axes must be distinct
    run yq -r '[.roles[] | select((.complexity_levels == null) or (.default_aal == null))] | length' "$ROLES"
    [ "$output" -eq 0 ]
}

@test "rejects complexity_level outside 1..5" {
    cat > "$TMP/bad.yaml" <<'EOF'
schema_version: 1
global_max_parallel: 8
roles:
  - id: bad
    description: "x"
    allowed_tools: [Read]
    allowed_paths: ["**"]
    forbidden_actions: [prod-deploy, secret-rotation]
    max_parallel: 2
    complexity_levels: [3, 6]
    default_aal: 1
    starter_skill: "skills/fleet/l3-analyst"
EOF
    run "$VALIDATOR" --file "$TMP/bad.yaml"
    [ "$status" -eq 1 ]
}

@test "rejects max_parallel exceeding global cap" {
    cat > "$TMP/over.yaml" <<'EOF'
schema_version: 1
global_max_parallel: 8
roles:
  - id: greedy
    description: "x"
    allowed_tools: [Read]
    allowed_paths: ["**"]
    forbidden_actions: [prod-deploy, secret-rotation]
    max_parallel: 99
    complexity_levels: [2]
    default_aal: 1
    starter_skill: "skills/fleet/l2-structured"
EOF
    run "$VALIDATOR" --file "$TMP/over.yaml"
    [ "$status" -eq 1 ]
}

@test "rejects autonomous role (default_aal>=3) missing Layer-6 forbidden floor" {
    cat > "$TMP/unsafe.yaml" <<'EOF'
schema_version: 1
global_max_parallel: 8
roles:
  - id: rogue
    description: "x"
    allowed_tools: [Read, Bash]
    allowed_paths: ["**"]
    forbidden_actions: [dns-change]
    max_parallel: 2
    complexity_levels: [4]
    default_aal: 3
    starter_skill: "skills/fleet/l4-expert"
EOF
    run "$VALIDATOR" --file "$TMP/unsafe.yaml"
    [ "$status" -eq 1 ]
}

@test "rejects starter_skill pointing at non-existent skill file" {
    cat > "$TMP/phantom.yaml" <<'EOF'
schema_version: 1
global_max_parallel: 8
roles:
  - id: ghost
    description: "x"
    allowed_tools: [Read]
    allowed_paths: ["**"]
    forbidden_actions: [prod-deploy, secret-rotation]
    max_parallel: 2
    complexity_levels: [1]
    default_aal: 1
    starter_skill: "skills/fleet/does-not-exist"
EOF
    run "$VALIDATOR" --file "$TMP/phantom.yaml"
    [ "$status" -eq 1 ]
}

@test "no secrets in roles.yaml (declarative config only)" {
    # crude secret-pattern lint: no obvious tokens/keys
    run grep -iE '(secret|password|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9/+_-]{12,}' "$ROLES"
    [ "$status" -ne 0 ]
}

@test "usage error returns exit 2" {
    run "$VALIDATOR" --nonsense-flag
    [ "$status" -eq 2 ]
}

@test "validator flags starter_skill whose SKILL.md lacks context_budget_tokens" {
    # Skill must resolve under repo root (so the schema also resolves). Create a
    # throwaway fleet skill WITHOUT context_budget_tokens inside the repo, then
    # clean it up. The role points at it; budget-presence check must fire.
    NB_DIR="$REPO/skills/fleet/_test_no_budget"
    mkdir -p "$NB_DIR"
    cat > "$NB_DIR/SKILL.md" <<'EOF'
---
name: fleet-test-no-budget
description: A fleet skill missing its context budget declaration.
metadata:
  fleet_level: 3
---
# No budget
EOF
    cat > "$TMP/nb.yaml" <<'EOF'
schema_version: 1
global_max_parallel: 8
roles:
  - id: tester
    description: "x"
    allowed_tools: [Read]
    allowed_paths: ["**"]
    forbidden_actions: [prod-deploy, secret-rotation]
    max_parallel: 2
    complexity_levels: [3]
    default_aal: 1
    starter_skill: "skills/fleet/_test_no_budget"
EOF
    run "$VALIDATOR" --file "$TMP/nb.yaml" --root "$REPO"
    rm -rf "$NB_DIR"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "context_budget_tokens"
}

@test "seed roles all reference skills declaring context_budget_tokens" {
    run "$VALIDATOR" --file "$ROLES"
    [ "$status" -eq 0 ]
}

@test "V-AC-1: all five fleet level skills declare an integer context_budget_tokens" {
    # Direct enumeration of the per-level fleet starter skills (independent of
    # role references) — the budget gate's coverage floor for fleet spawn.
    for lvl in l1-basic l2-structured l3-analyst l4-expert l5-autonomous; do
        skill_md="$REPO/skills/fleet/$lvl/SKILL.md"
        [ -f "$skill_md" ] || { echo "missing: $skill_md"; return 1; }
        # frontmatter-only extraction (body breaks a full-file YAML parse)
        budget="$(awk '/^---$/{c++;next} c==1' "$skill_md" \
            | grep -E '^\s*context_budget_tokens:' \
            | head -1 | sed -E 's/.*context_budget_tokens:[[:space:]]*//')"
        [ -n "$budget" ] || { echo "$lvl: no context_budget_tokens"; return 1; }
        [[ "$budget" =~ ^[0-9]+$ ]] || { echo "$lvl: budget not integer: '$budget'"; return 1; }
    done
}

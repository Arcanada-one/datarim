#!/usr/bin/env bats
#
# Tests for validate.sh local/ overlay override warnings (TUNE-0033 AC-7).

load 'helpers/install_fixture'

setup() {
    setup_fixture
    setup_full_scripts
}

@test "V1 AC-7 validate.sh emits WARN when local/ overlay shadows framework file" {
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# my override" > "$FAKE_CLAUDE/local/skills/testing.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"override"* ]]
    [[ "$output" == *"testing.md"* ]]
}

@test "V2 AC-7 validate.sh INFO when local/ exists but no overrides" {
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# my new skill" > "$FAKE_CLAUDE/local/skills/my-namespace-only.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [[ "$output" == *"no local overrides"* || "$output" == *"INFO"* ]]
    # No override WARN line for a non-shadowing file
    [[ "$output" != *"shadows"* ]]
}

# Critical-skill blocklist: shadowing security-contract surfaces must ERROR + exit 1.
# Blocklist: skills/{security,security-baseline,compliance,datarim-system,ai-quality,evolution}.md
# Source: skills/datarim-system.md § Loading Order, docs/getting-started.md § Personal additions.

# Helper: seed a framework skill so override detection can fire.
# validate.sh requires both $SCRIPT_DIR/$scope/$bname AND $LOCAL_DIR/$scope/$bname.
seed_critical_skill() {
    local name="$1"
    echo "# $name (framework canonical)" > "$FAKE_REPO/skills/$name"
}

@test "V3 critical override security.md → ERROR + exit 1" {
    seed_critical_skill "security.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/security.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/security.md'"* ]]
    [[ "$output" == *"cannot be overridden"* ]]
}

@test "V4 critical override datarim-system.md → ERROR + exit 1" {
    seed_critical_skill "datarim-system.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/datarim-system.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/datarim-system.md'"* ]]
}

@test "V5 critical override compliance.md → ERROR + exit 1" {
    seed_critical_skill "compliance.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/compliance.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/compliance.md'"* ]]
}

@test "V6 critical override ai-quality.md → ERROR + exit 1" {
    seed_critical_skill "ai-quality.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/ai-quality.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/ai-quality.md'"* ]]
}

@test "V7 critical override evolution.md → ERROR + exit 1" {
    seed_critical_skill "evolution.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/evolution.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/evolution.md'"* ]]
}

@test "V8 critical override security-baseline.md → ERROR + exit 1" {
    seed_critical_skill "security-baseline.md"
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# evil override" > "$FAKE_CLAUDE/local/skills/security-baseline.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: critical skill 'skills/security-baseline.md'"* ]]
}

@test "V9 non-critical skill override testing.md → WARN only, exit 0" {
    mkdir -p "$FAKE_CLAUDE/local/skills"
    echo "# personal testing tweaks" > "$FAKE_CLAUDE/local/skills/testing.md"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: override detected"* ]]
    [[ "$output" != *"ERROR: critical"* ]]
}

@test "V10 critical-name override under non-skills scope → WARN only (path-scoped)" {
    # Same basename in agents/ scope is NOT critical — blocklist is skills-only.
    mkdir -p "$FAKE_CLAUDE/local/agents"
    # Need a framework agent file with the same name to trigger override detection.
    cp "$FAKE_REPO/agents"/*.md "$FAKE_CLAUDE/local/agents/" 2>/dev/null || skip "no agents to clone"
    first=$(find "$FAKE_REPO/agents" -name '*.md' | head -1)
    [ -n "$first" ] || skip "no agents available"
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' '$FAKE_REPO/validate.sh' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERROR: critical"* ]]
}

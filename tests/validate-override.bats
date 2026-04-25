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

#!/usr/bin/env bats
#
# TUNE-0304 Phase 1: contract test for dev-tools/check-skill-frontmatter.sh
# under the new universal-skill schema.
#
# New contract (per PRD §6.1 and plan §6.6):
#   REQUIRED keys: name, description
#   OPTIONAL keys: model, effort, disable-model-invocation, allowed-tools
#   OPTIONAL metadata.* — model_tier (enum), current_aal, target_aal, runtime
#   `runtime:` at top level (legacy) → WARNING but PASS (migration window)
#   `model:` if present MUST be inherit|sonnet|opus|haiku or full model ID
#   `metadata.model_tier:` if present MUST be reasoning|balanced|fast|cheap
#
# Backward compat: TUNE-0114 baseline (runtime: + current_aal: + target_aal:
# as top-level) is no longer required.
#
# Companion check: AGENTS.md symlink integrity preserved from TUNE-0114 AC-7.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-skill-frontmatter.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills/alpha"
    # Pre-stage minimal AGENTS.md symlink so the companion check passes
    # in all positive test cases.
    : >"$TMPROOT/CLAUDE.md"
    ln -s CLAUDE.md "$TMPROOT/AGENTS.md"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_skill_md() {
    local path="$1"
    shift
    cat >"$path" <<EOF
$@
EOF
}

@test "script exists" {
    [ -f "$SCRIPT" ]
}

@test "PASS on minimal valid SKILL.md (name + description only)" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: minimal valid skill
---
body"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "FAIL when name: missing" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
description: missing name
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISS name"* ]] || [[ "$output" == *"name"* ]]
}

@test "FAIL when description: missing" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"description"* ]]
}

@test "PASS with model: inherit" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: with inherit
model: inherit
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "PASS with model: opus (explicit override)" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: explicit opus
model: opus
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "FAIL with model: bogus-value" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: bad model
model: !!!nonsense!!!
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"model"* ]]
}

@test "PASS with metadata.model_tier: reasoning" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: tiered
metadata:
  model_tier: reasoning
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "FAIL with metadata.model_tier: bogus" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: tiered bad
metadata:
  model_tier: turbocharged
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"model_tier"* ]]
}

@test "WARN but PASS on legacy top-level runtime: during migration window" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: legacy
runtime: [claude, codex]
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]] || [[ "$output" == *"runtime"* ]]
}

@test "scans both skills/<name>.md and skills/<name>/SKILL.md (hybrid window)" {
    # Hybrid: one flat, one nested. Validator must check both.
    rm -rf "$TMPROOT/skills/alpha"
    write_skill_md "$TMPROOT/skills/flat.md" \
"---
name: flat
description: flat-style legacy
---"
    mkdir -p "$TMPROOT/skills/nested"
    write_skill_md "$TMPROOT/skills/nested/SKILL.md" \
"---
name: nested
description: nested-style canonical
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"checked=2"* ]] || [[ "$output" == *"flat"* ]]
}

@test "skips skills/.system/ namespace (C3)" {
    mkdir -p "$TMPROOT/skills/.system/bundled"
    write_skill_md "$TMPROOT/skills/.system/bundled/SKILL.md" \
"---
not_validated: true
---"
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: ok
---"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "FAIL when AGENTS.md not a symlink (AC-7 retained)" {
    write_skill_md "$TMPROOT/skills/alpha/SKILL.md" \
"---
name: alpha
description: ok
---"
    rm "$TMPROOT/AGENTS.md"
    : >"$TMPROOT/AGENTS.md"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AGENTS.md"* ]]
}

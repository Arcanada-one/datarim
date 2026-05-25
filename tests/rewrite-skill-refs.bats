#!/usr/bin/env bats
#
# TUNE-0304 Phase 1: contract test for dev-tools/rewrite-skill-refs.sh.
#
# Contract (per plan §6.4):
#   - Rewrites `skills/<name>.md` → `skills/<name>/SKILL.md` in cross-refs
#   - Scope: .md, .sh, .yaml, .yml, CLAUDE.md, AGENTS.md
#   - Excludes documentation/archive/** (historical refs frozen)
#   - Markdown link form `(skills/<name>.md)` rewritten to `(skills/<name>/SKILL.md)`
#   - Bare reference `skills/<name>.md` rewritten to `skills/<name>/SKILL.md`
#   - Idempotent: re-run produces zero diff
#   - --dry-run reports what would change without writing
#   - Exit 0 on success, 1 on residual matches detected post-rewrite
#
# Phase 0 baseline discovery (FB-3 inline): scope widened from PRD-estimated
# 311 to actual 535 (`.md=503 + .sh=29 + .yaml=3`); test covers all three.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/rewrite-skill-refs.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills/alpha" "$TMPROOT/agents" "$TMPROOT/commands" \
             "$TMPROOT/documentation/archive/framework"
    cat >"$TMPROOT/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: x
---
EOF
}

teardown() {
    rm -rf "$TMPROOT"
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "rewrites markdown link form (parenthesised)" {
    cat >"$TMPROOT/agents/foo.md" <<'EOF'
See [details](skills/alpha.md) and also [more](skills/beta.md).
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/agents/foo.md"
    [[ "$output" == *"(skills/alpha/SKILL.md)"* ]]
    [[ "$output" == *"(skills/beta/SKILL.md)"* ]]
    [[ "$output" != *"(skills/alpha.md)"* ]]
}

@test "rewrites bare references in .md" {
    cat >"$TMPROOT/commands/bar.md" <<'EOF'
Load skills/alpha.md before executing.
Also see skills/gamma.md.
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/commands/bar.md"
    [[ "$output" == *"skills/alpha/SKILL.md"* ]]
    [[ "$output" == *"skills/gamma/SKILL.md"* ]]
}

@test "rewrites references in .sh files" {
    cat >"$TMPROOT/baz.sh" <<'EOF'
#!/bin/bash
SKILL_PATH="$HOME/.claude/skills/alpha.md"
echo "loading skills/alpha.md"
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/baz.sh"
    [[ "$output" == *"skills/alpha/SKILL.md"* ]]
    [[ "$output" != *"skills/alpha.md"* ]]
}

@test "rewrites references in .yaml files" {
    cat >"$TMPROOT/conf.yaml" <<'EOF'
loads:
  - skills/alpha.md
  - skills/beta.md
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/conf.yaml"
    [[ "$output" == *"skills/alpha/SKILL.md"* ]]
    [[ "$output" == *"skills/beta/SKILL.md"* ]]
}

@test "EXCLUDES documentation/archive/** from rewrite" {
    cat >"$TMPROOT/documentation/archive/framework/old-task.md" <<'EOF'
historical: skills/alpha.md
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/documentation/archive/framework/old-task.md"
    [[ "$output" == *"skills/alpha.md"* ]]
    [[ "$output" != *"skills/alpha/SKILL.md"* ]]
}

@test "idempotent: second run produces zero changes" {
    cat >"$TMPROOT/agents/foo.md" <<'EOF'
See skills/alpha.md.
EOF
    "$SCRIPT" --root "$TMPROOT" >/dev/null
    sha1_after_first=$(sha1sum "$TMPROOT/agents/foo.md" 2>/dev/null || shasum "$TMPROOT/agents/foo.md")
    "$SCRIPT" --root "$TMPROOT" >/dev/null
    sha1_after_second=$(sha1sum "$TMPROOT/agents/foo.md" 2>/dev/null || shasum "$TMPROOT/agents/foo.md")
    [ "$sha1_after_first" = "$sha1_after_second" ]
}

@test "--dry-run reports planned changes, writes nothing" {
    cat >"$TMPROOT/agents/foo.md" <<'EOF'
See skills/alpha.md.
EOF
    sha1_before=$(sha1sum "$TMPROOT/agents/foo.md" 2>/dev/null || shasum "$TMPROOT/agents/foo.md")
    run "$SCRIPT" --root "$TMPROOT" --dry-run
    [ "$status" -eq 0 ]
    sha1_after=$(sha1sum "$TMPROOT/agents/foo.md" 2>/dev/null || shasum "$TMPROOT/agents/foo.md")
    [ "$sha1_before" = "$sha1_after" ]
    [[ "$output" == *"would"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"foo.md"* ]]
}

@test "preserves SKILL.md self-reference (no double-rewrite)" {
    # Already-canonical refs must NOT become skills/alpha/SKILL/SKILL.md.
    cat >"$TMPROOT/agents/foo.md" <<'EOF'
See skills/alpha/SKILL.md for context.
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/agents/foo.md"
    [[ "$output" == *"skills/alpha/SKILL.md"* ]]
    [[ "$output" != *"SKILL/SKILL"* ]]
}

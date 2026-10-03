#!/usr/bin/env bats
# tune-0520-agent-enforcement.bats — TUNE-0520: enforce Stage Header, CTA
# format, and ALWAYS APPLY compliance across agent files.
#
# The TUNE-0517 audit found 58 of 65 agent-file declarations UNENFORCED.
# This file closes that gap with deterministic wiring assertions.
# Usage: bats tests/tune-0520-agent-enforcement.bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
AGENTS_DIR="$REPO_DIR/agents"
SKILLS_DIR="$REPO_DIR/skills"

# Pipeline agents — MUST carry Stage Header, CTA format, and ALWAYS APPLY.
PIPELINE_AGENTS=("architect" "compliance" "developer" "planner" "reviewer")

# All agents (pipeline + auxiliary) that carry ALWAYS APPLY.
AGENTS_WITH_ALWAYS_APPLY=(
    "architect" "compliance" "developer" "planner" "reviewer"
    "devops" "editor" "librarian" "optimizer" "researcher"
    "security" "skill-creator" "sre" "strategist" "tester" "writer"
)

# ===========================================================================
# Stage Header: pipeline agents MUST carry the Stage Header rule
# ===========================================================================

@test "A1: architect.md carries Stage Header rule" {
    run grep -c "first line.*task-scoped response.*MUST.*Stage Header" "$AGENTS_DIR/architect.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A2: compliance.md carries Stage Header rule" {
    run grep -c "first line.*task-scoped response.*MUST.*Stage Header" "$AGENTS_DIR/compliance.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A3: developer.md carries Stage Header rule" {
    run grep -c "first line.*task-scoped response.*MUST.*Stage Header" "$AGENTS_DIR/developer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A4: planner.md carries Stage Header rule" {
    run grep -c "first line.*task-scoped response.*MUST.*Stage Header" "$AGENTS_DIR/planner.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A5: reviewer.md carries Stage Header rule" {
    run grep -c "first line.*task-scoped response.*MUST.*Stage Header" "$AGENTS_DIR/reviewer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ===========================================================================
# CTA format: pipeline agents MUST reference cta-format/SKILL.md
# ===========================================================================

@test "B1: architect.md references cta-format/SKILL.md" {
    run grep -c "cta-format/SKILL.md" "$AGENTS_DIR/architect.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "B2: compliance.md references cta-format/SKILL.md" {
    run grep -c "cta-format/SKILL.md" "$AGENTS_DIR/compliance.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "B3: developer.md references cta-format/SKILL.md" {
    run grep -c "cta-format/SKILL.md" "$AGENTS_DIR/developer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "B4: planner.md references cta-format/SKILL.md" {
    run grep -c "cta-format/SKILL.md" "$AGENTS_DIR/planner.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "B5: reviewer.md references cta-format/SKILL.md" {
    run grep -c "cta-format/SKILL.md" "$AGENTS_DIR/reviewer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ===========================================================================
# CTA block: pipeline agents MUST carry CTA block rule text
# ===========================================================================

@test "C1: architect.md carries CTA block rule" {
    run grep -ciE "final paragraph.*MUST.*CTA block|after.*completing.*MUST.*CTA" "$AGENTS_DIR/architect.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "C2: compliance.md carries CTA block rule" {
    run grep -ciE "CTA block|cta-format.md" "$AGENTS_DIR/compliance.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "C3: developer.md carries CTA block rule" {
    run grep -ciE "final paragraph.*MUST.*CTA|after.*implementation.*MUST.*CTA" "$AGENTS_DIR/developer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "C4: planner.md carries CTA block rule" {
    run grep -c "final paragraph.*MUST.*CTA\|after.*completing.*MUST.*CTA" "$AGENTS_DIR/planner.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "C5: reviewer.md carries CTA block rule" {
    run grep -ciE "after.*(verdict|QA).*MUST.*CTA" "$AGENTS_DIR/reviewer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ===========================================================================
# ALWAYS APPLY: every referenced skill MUST exist in skills/
# Extracts skill paths from ALWAYS APPLY lines in agent files and verifies
# each one resolves to an actual file.
# ===========================================================================

@test "D1: all agent ALWAYS APPLY skill references resolve to existing files" {
    missing_count=0
    missing_list=""
    for agent_file in "$AGENTS_DIR"/*.md; do
        agent_name=$(basename "$agent_file" .md)
        # Extract skill paths from ALWAYS APPLY context:
        #   - `$HOME/.claude/skills/<name>/SKILL.md`
        #   - `skills/<name>/SKILL.md` (relative)
        while IFS= read -r skill_path; do
            [ -n "$skill_path" ] || continue
            # Normalise: strip leading $HOME/.claude/ prefix to get skills/<name>/SKILL.md
            skill_rel="${skill_path#\$HOME/.claude/}"
            # Resolve relative to repo
            if [ -f "$REPO_DIR/$skill_rel" ]; then
                continue
            fi
            # Try skills/<name>/SKILL.md directly (repo-relative)
            skill_name=$(echo "$skill_rel" | sed -n 's|skills/\([^/]*\)/SKILL.md|\1|p')
            if [ -n "$skill_name" ] && [ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]; then
                continue
            fi
            missing_count=$((missing_count + 1))
            missing_list="$missing_list  $agent_name references $skill_path (resolved: $skill_rel)\n"
        done < <(sed -n '/ALWAYS APPLY/,/^[[:space:]]*$/p' "$agent_file" | \
                 grep -oE '\$HOME/\.claude/skills/[A-Za-z0-9_-]+/SKILL\.md' || true)
    done
    if [ "$missing_count" -gt 0 ]; then
        printf "MISSING %d skill reference(s):\n%b" "$missing_count" "$missing_list"
    fi
    [ "$missing_count" -eq 0 ]
}

@test "D2: all agents with ALWAYS APPLY have at least one skill reference" {
    for agent_name in "${AGENTS_WITH_ALWAYS_APPLY[@]}"; do
        agent_file="$AGENTS_DIR/$agent_name.md"
        [ -f "$agent_file" ] || { echo "MISSING: $agent_name.md"; return 1; }
        count=$(sed -n '/ALWAYS APPLY/,/^[[:space:]]*$/p' "$agent_file" | \
                grep -cE 'skills/|cta-format' || true)
        if [ "$count" -eq 0 ]; then
            echo "FAIL: $agent_name.md has ALWAYS APPLY but no skill references"
            return 1
        fi
    done
}

@test "D3: ALWAYS APPLY is present in expected agent count (15-16 of 19)" {
    count=0
    for agent_file in "$AGENTS_DIR"/*.md; do
        if grep -q "ALWAYS APPLY" "$agent_file" 2>/dev/null; then
            count=$((count + 1))
        fi
    done
    echo "Agents with ALWAYS APPLY: $count of 19"
    [ "$count" -ge 15 ]
    [ "$count" -le 17 ]
}

# ===========================================================================
# Non-pipeline agents MUST NOT be missing ALWAYS APPLY when they're
# used in pipeline stages. Conversely, pipeline agents MUST have it.
# ===========================================================================

@test "E1: all 5 pipeline agents carry ALWAYS APPLY" {
    for agent_name in "${PIPELINE_AGENTS[@]}"; do
        agent_file="$AGENTS_DIR/$agent_name.md"
        if ! grep -q "ALWAYS APPLY" "$agent_file" 2>/dev/null; then
            echo "FAIL: $agent_name.md (pipeline agent) missing ALWAYS APPLY"
            return 1
        fi
    done
}

# ===========================================================================
# cta-format skill exists and has required sections
# ===========================================================================

@test "F1: cta-format/SKILL.md exists" {
    [ -f "$SKILLS_DIR/cta-format/SKILL.md" ]
}

@test "F2: cta-format/SKILL.md defines Stage Header section" {
    run grep -c "Stage Header" "$SKILLS_DIR/cta-format/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "F3: cta-format/SKILL.md defines FAIL-Routing variant" {
    run grep -c "FAIL-Routing" "$SKILLS_DIR/cta-format/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

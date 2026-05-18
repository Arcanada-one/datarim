---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
runtime: [claude, codex]
current_aal: 2
target_aal: 4
---

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note on parallelism:** This skill works well in single-session execution. If your runtime supports spawning isolated agents (subagents) for parallel or two-stage review work, prefer `subagent-driven-development` instead — quality of structured execution rises significantly when independent agents handle implementation and review separately.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically — identify any questions or concerns about the plan
3. If concerns: raise them with your human partner before starting
4. If no concerns: enumerate the plan's tasks as a working checklist (one entry per task with explicit `[ ]` / `[~]` / `[✓]` status) and proceed

### Step 2: Execute Tasks

For each task:
1. Mark as `[~]` in_progress in your checklist; surface this status in your reply so the human partner can see what you are working on
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as `[✓]` completed only after the task's verification passes; record evidence (command output, file path, test result) inline

### Step 3: Complete Development

After all tasks complete and verified:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use `finishing-a-development-branch`
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** — stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**
- **using-git-worktrees** — ensures isolated workspace (creates one or verifies existing)
- **writing-plans** — creates the plan this skill executes
- **finishing-a-development-branch** — complete development after all tasks

---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

Execute a plan by dispatching a fresh isolated agent ("subagent") per task, with two-stage review after each: spec compliance review first, then code quality review.

> **Term:** "subagent" here means any isolated agent invocation that runs with its own context window and returns a structured result to the orchestrator — runtime-specific names vary (subagent dispatch, agent thread, queued worker, isolated REPL session).

**Why isolated agents:** you delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Core principle:** fresh isolated agent per task + two-stage review (spec → quality) = high quality, fast iteration.

**Continuous execution:** do not pause to check in with your human partner between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are: BLOCKED status you cannot resolve, ambiguity that genuinely prevents progress, or all tasks complete. "Should I continue?" prompts and progress summaries waste their time — they asked you to execute the plan, so execute it.

## When to Use

```dot
digraph when_to_use {
    "Have implementation plan?" [shape=diamond];
    "Tasks mostly independent?" [shape=diamond];
    "Stay in this session?" [shape=diamond];
    "Runtime supports isolated agent dispatch?" [shape=diamond];
    "subagent-driven-development" [shape=box];
    "executing-plans" [shape=box];
    "Manual execution or brainstorm first" [shape=box];

    "Have implementation plan?" -> "Tasks mostly independent?" [label="yes"];
    "Have implementation plan?" -> "Manual execution or brainstorm first" [label="no"];
    "Tasks mostly independent?" -> "Stay in this session?" [label="yes"];
    "Tasks mostly independent?" -> "Manual execution or brainstorm first" [label="no - tightly coupled"];
    "Stay in this session?" -> "Runtime supports isolated agent dispatch?" [label="yes"];
    "Stay in this session?" -> "executing-plans" [label="no - parallel session"];
    "Runtime supports isolated agent dispatch?" -> "subagent-driven-development" [label="yes"];
    "Runtime supports isolated agent dispatch?" -> "executing-plans" [label="no - inline only"];
}
```

**vs. Executing Plans (single-session inline execution):**
- Same session (no context switch)
- Fresh isolated agent per task (no context pollution)
- Two-stage review after each task: spec compliance first, then code quality
- Faster iteration (no human-in-loop between tasks)

## The Process

```dot
digraph process {
    rankdir=TB;

    subgraph cluster_per_task {
        label="Per Task";
        "Dispatch implementer agent (./implementer-prompt.md)" [shape=box];
        "Implementer asks questions?" [shape=diamond];
        "Answer questions, provide context" [shape=box];
        "Implementer implements, tests, commits, self-reviews" [shape=box];
        "Dispatch spec-reviewer agent (./spec-reviewer-prompt.md)" [shape=box];
        "Spec reviewer confirms code matches spec?" [shape=diamond];
        "Implementer fixes spec gaps" [shape=box];
        "Dispatch code-quality-reviewer agent (./code-quality-reviewer-prompt.md)" [shape=box];
        "Code quality reviewer approves?" [shape=diamond];
        "Implementer fixes quality issues" [shape=box];
        "Mark task complete in working tracker" [shape=box];
    }

    "Read plan, extract all tasks with full text, note context, build working tracker" [shape=box];
    "More tasks remain?" [shape=diamond];
    "Dispatch final code reviewer agent for entire implementation" [shape=box];
    "Use finishing-a-development-branch" [shape=box style=filled fillcolor=lightgreen];

    "Read plan, extract all tasks with full text, note context, build working tracker" -> "Dispatch implementer agent (./implementer-prompt.md)";
    "Dispatch implementer agent (./implementer-prompt.md)" -> "Implementer asks questions?";
    "Implementer asks questions?" -> "Answer questions, provide context" [label="yes"];
    "Answer questions, provide context" -> "Dispatch implementer agent (./implementer-prompt.md)";
    "Implementer asks questions?" -> "Implementer implements, tests, commits, self-reviews" [label="no"];
    "Implementer implements, tests, commits, self-reviews" -> "Dispatch spec-reviewer agent (./spec-reviewer-prompt.md)";
    "Dispatch spec-reviewer agent (./spec-reviewer-prompt.md)" -> "Spec reviewer confirms code matches spec?";
    "Spec reviewer confirms code matches spec?" -> "Implementer fixes spec gaps" [label="no"];
    "Implementer fixes spec gaps" -> "Dispatch spec-reviewer agent (./spec-reviewer-prompt.md)" [label="re-review"];
    "Spec reviewer confirms code matches spec?" -> "Dispatch code-quality-reviewer agent (./code-quality-reviewer-prompt.md)" [label="yes"];
    "Dispatch code-quality-reviewer agent (./code-quality-reviewer-prompt.md)" -> "Code quality reviewer approves?";
    "Code quality reviewer approves?" -> "Implementer fixes quality issues" [label="no"];
    "Implementer fixes quality issues" -> "Dispatch code-quality-reviewer agent (./code-quality-reviewer-prompt.md)" [label="re-review"];
    "Code quality reviewer approves?" -> "Mark task complete in working tracker" [label="yes"];
    "Mark task complete in working tracker" -> "More tasks remain?";
    "More tasks remain?" -> "Dispatch implementer agent (./implementer-prompt.md)" [label="yes"];
    "More tasks remain?" -> "Dispatch final code reviewer agent for entire implementation" [label="no"];
    "Dispatch final code reviewer agent for entire implementation" -> "Use finishing-a-development-branch";
}
```

## Model Selection

Use the least powerful model that can handle each role to conserve cost and increase speed.

**Mechanical implementation tasks** (isolated functions, clear specs, 1-2 files): use a fast, cheap model. Most implementation tasks are mechanical when the plan is well-specified.

**Integration and judgment tasks** (multi-file coordination, pattern matching, debugging): use a standard model.

**Architecture, design, and review tasks**: use the most capable available model.

**Task complexity signals:**
- Touches 1-2 files with a complete spec → cheap model
- Touches multiple files with integration concerns → standard model
- Requires design judgment or broad codebase understanding → most capable model

## Handling Implementer Status

Implementer agents report one of four statuses. Handle each appropriately:

**DONE:** proceed to spec compliance review.

**DONE_WITH_CONCERNS:** the implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.

**NEEDS_CONTEXT:** the implementer needs information that wasn't provided. Provide the missing context and re-dispatch.

**BLOCKED:** the implementer cannot complete the task. Assess the blocker:
1. If it's a context problem, provide more context and re-dispatch with the same model.
2. If the task requires more reasoning, re-dispatch with a more capable model.
3. If the task is too large, break it into smaller pieces.
4. If the plan itself is wrong, escalate to the human.

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

## Prompt Templates

- `./implementer-prompt.md` — dispatch implementer agent
- `./spec-reviewer-prompt.md` — dispatch spec-compliance reviewer agent
- `./code-quality-reviewer-prompt.md` — dispatch code-quality reviewer agent

## Example Workflow

```
You: I'm using Subagent-Driven Development to execute this plan.

[Read plan file once: <plan-path>]
[Extract all 5 tasks with full text and context]
[Build working tracker with all tasks]

Task 1: Hook installation script

[Get Task 1 text and context (already extracted)]
[Dispatch implementer agent with full task text + context]

Implementer: "Before I begin — should the hook be installed at user or system level?"

You: "User level (per project conventions)."

Implementer: "Got it. Implementing now..."
[Later] Implementer:
  - Implemented install-hook command
  - Added tests, 5/5 passing
  - Self-review: found I missed --force flag, added it
  - Committed

[Dispatch spec-compliance reviewer agent]
Spec reviewer: ✅ Spec compliant — all requirements met, nothing extra

[Get git SHAs, dispatch code-quality reviewer agent]
Code reviewer: Strengths: good test coverage, clean. Issues: none. Approved.

[Mark Task 1 complete]

Task 2: Recovery modes

[Get Task 2 text and context (already extracted)]
[Dispatch implementer agent with full task text + context]

Implementer: [No questions, proceeds]
Implementer:
  - Added verify/repair modes
  - 8/8 tests passing
  - Self-review: all good
  - Committed

[Dispatch spec-compliance reviewer agent]
Spec reviewer: ❌ Issues:
  - Missing: progress reporting (spec says "report every 100 items")
  - Extra: added --json flag (not requested)

[Implementer fixes issues]
Implementer: removed --json flag, added progress reporting

[Spec reviewer reviews again]
Spec reviewer: ✅ Spec compliant now

[Dispatch code-quality reviewer agent]
Code reviewer: Strengths: solid. Issues (Important): magic number (100)

[Implementer fixes]
Implementer: extracted PROGRESS_INTERVAL constant

[Code reviewer reviews again]
Code reviewer: ✅ Approved

[Mark Task 2 complete]

...

[After all tasks]
[Dispatch final code-reviewer agent for whole branch]
Final reviewer: all requirements met, ready to merge

Done!
```

## Advantages

**vs. Manual execution:**
- Isolated agents follow TDD naturally
- Fresh context per task (no confusion)
- Parallel-safe (agents don't interfere)
- Agent can ask questions (before AND during work)

**vs. Executing Plans:**
- Same session (no handoff)
- Continuous progress (no waiting)
- Review checkpoints automatic

**Efficiency gains:**
- No file reading overhead (controller provides full text)
- Controller curates exactly what context is needed
- Agent gets complete information upfront
- Questions surfaced before work begins (not after)

**Quality gates:**
- Self-review catches issues before handoff
- Two-stage review: spec compliance, then code quality
- Review loops ensure fixes actually work
- Spec compliance prevents over/under-building
- Code quality ensures implementation is well-built

**Cost:**
- More agent invocations (implementer + 2 reviewers per task)
- Controller does more prep work (extracting all tasks upfront)
- Review loops add iterations
- But catches issues early (cheaper than debugging later)

## Red Flags

**Never:**
- Start implementation on main/master branch without explicit user consent
- Skip reviews (spec compliance OR code quality)
- Proceed with unfixed issues
- Dispatch multiple implementer agents in parallel (conflicts)
- Make the implementer agent re-read the plan file (provide full text instead)
- Skip scene-setting context (the agent needs to understand where the task fits)
- Ignore agent questions (answer before letting them proceed)
- Accept "close enough" on spec compliance (spec reviewer found issues = not done)
- Skip review loops (reviewer found issues = implementer fixes = review again)
- Let implementer self-review replace actual review (both are needed)
- **Start code-quality review before spec compliance is ✅** (wrong order)
- Move to next task while either review has open issues

**If the agent asks questions:**
- Answer clearly and completely
- Provide additional context if needed
- Don't rush them into implementation

**If reviewer finds issues:**
- The implementer (same agent role, dispatched again) fixes them
- Reviewer reviews again
- Repeat until approved
- Don't skip the re-review

**If the agent fails the task:**
- Dispatch a fix agent with specific instructions
- Don't try to fix manually (context pollution)

## Integration

**Required workflow skills:**
- **using-git-worktrees** — ensures isolated workspace (creates one or verifies existing)
- **writing-plans** — creates the plan this skill executes
- **requesting-code-review** — code review template for reviewer agents
- **finishing-a-development-branch** — complete development after all tasks

**Subagents should use:**
- **test-driven-development** — agents follow TDD for each task

**Alternative workflow:**
- **executing-plans** — use for inline single-thread execution when the runtime cannot spawn isolated agents

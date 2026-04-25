---
name: dr-optimize
description: Audit and optimize the Datarim framework — detect bloat, duplicates, oversized files, selective-loading candidates, and stale references.
allowed-tools: Read Write Edit Grep Glob Bash WebSearch WebFetch Agent
effort: high
---

# /dr-optimize — Framework Optimization

**Role**: Optimizer Agent
**Source**: `$HOME/.claude/agents/optimizer.md`

## When to Run

- **Periodically** — after every 5-10 completed tasks, or when `/dr-help` output feels overwhelming
- **After `/dr-addskill`** — to check if the new skill overlaps with existing ones
- **When context issues appear** — if skills stop triggering or Claude seems to forget instructions
- **On user request** — when the user asks to clean up, simplify, or reorganize
- **Auto-suggested by `/dr-archive` Step 0.5 (reflecting skill)** — when the reflection health-check detects framework inefficiencies

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/optimizer.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/evolution.md` (Evolution proposal format and approval gate)
3.  **DETERMINE SCOPE**: What to audit?
    - If user said "project" → scan project `.claude/` directory
    - If user said "global" or "user" → scan `$HOME/.claude/`
    - If user said "datarim" or "framework" → scan the Datarim source repo
    - Default: scan both project `.claude/` and `$HOME/.claude/`, report separately
4.  **FULL AUDIT**: For the target scope, build a complete inventory:

    ```
    === SKILLS (N files, M total lines) ===
    | # | Name | Lines | Description | Loaded By |
    |---|------|-------|-------------|-----------|

    === AGENTS (N files, M total lines) ===
    | # | Name | Lines | Description | Invoked By |
    |---|------|-------|-------------|------------|

    === COMMANDS (N files, M total lines) ===
    | # | Name | Lines | Description | Uses Agent |
    |---|------|-------|-------------|------------|

    === TEMPLATES (N files) ===
    | # | Name | Description |
    |---|------|-------------|
    ```

5.  **BUILD DEPENDENCY GRAPH**: Map all cross-references:
    - Commands → Agents (which command loads which agent)
    - Agents → Skills (which agent loads which skills)
    - Skills → Skills (cross-references between skills)
    - Identify orphans (unreferenced components)

6.  **DETECT ISSUES**: Check each category:

    | Check | Threshold | Action |
    |-------|-----------|--------|
    | Unused skill | No agent references it | Propose `prune-skill` |
    | Unused agent | No command invokes it | Propose `prune-agent` |
    | Oversized skill | Warn `>300`, split `>400` lines | Propose `split-skill` |
    | Oversized agent | Warn `>120`, split `>180` lines | Propose `split-agent` or `rewrite-agent` |
    | Duplicate coverage | >70% overlap or repeated instruction blocks | Propose `merge-skills` / rewrite |
    | Stale description | Description != content | Propose `fix-description` |
    | Broken reference | Referenced but missing | Propose `fix-references` |
    | Doc count mismatch | CLAUDE.md / README.md / help docs != disk | Propose `sync-docs` |
    | Description budget | Any description `>160` chars or total `>8K` chars | Propose `fix-description` |
    | Selective-loading candidate | Monolithic file with mixed subdomains | Propose split into entry + supporting files |
    | Low-value provenance comments | Task-origin or migration notes that do not affect usage/policy | Propose rewrite cleanup |

6b. **DATARIM STATE HYGIENE** (always run):
    - Read `datarim/tasks.md`: extract all task IDs in `## Active Tasks` section AND all task IDs in `## Archived Tasks` table.
    - If any task ID appears in BOTH sections → it was archived but not cleaned from Active Tasks. Propose `remove-orphaned-active-task` (auto-approve: safe, data preserved in archive).
    - Read `datarim/activeContext.md`: if any task listed in `## Active Tasks` has a matching entry in the Archived Tasks table of tasks.md → propose removal from activeContext.
    - This catches cases where archive ran before Steps 6-7 existed (e.g. pre-v1.10.0 archives).

7.  **GENERATE REPORT**: Follow the **Structured Audit Report** template from `optimizer.md` (6 sections: Health Metrics Dashboard, Top-5 Oversized, Description Budget Violations, Merge Candidates, Orphan Analysis, Actionable Recommendations). Present all 6 sections with concrete data — no placeholders, no "TBD".

8.  **APPROVAL GATE**: Follow the evolution.md approval process:
    - List all proposals with numbers
    - Ask: "Which proposals should I apply? (all / none / comma-separated numbers)"
    - Wait for explicit response
    - Apply ONLY approved changes

9.  **APPLY AND SYNC**: After applying changes:
    - Update CLAUDE.md if counts, behavior descriptions, or references became stale
    - Update README.md if install flow, counts, or structure documentation became stale
    - Update dr-help.md if command behavior or command lists changed
    - Log all changes in `datarim/docs/evolution-log.md`

10. **VERIFY**: Run final check:
    - All counts in docs match actual files
    - No broken cross-references remain
    - Entry files still point to valid supporting fragments
    - All proposed changes applied correctly

## Notes

- Do not treat repo-vs-runtime drift as a permanent universal audit mode for the shared repo. That belongs to bootstrap migration work only.
- When supporting directories exist, read the short entry file first and then only the fragments needed for the current issue.

## Output
- Full audit report with dependency graph
- Optimization proposals with risk levels
- Applied changes summary
- Updated documentation

## Next Steps (CTA)

After optimize-pass, the optimizer agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-optimize`:**

- Applied structural changes → primary `/dr-help` (verify command list renders) + reminder to curate runtime → repo
- Removed components → primary "verify no workflow broken" + alternative `/dr-status`
- Need deeper restructuring → primary `/dr-design {TASK-ID}` (consilium panel)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks.

---
name: dr-optimize
description: Audit and optimize the Datarim framework — prune unused skills, merge duplicates, fix broken references, sync documentation, and improve context efficiency. Run periodically or when the framework feels bloated.
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
- **Auto-suggested by `/dr-reflect`** — when the reflection detects framework inefficiencies

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
    | Oversized skill | >500 lines | Propose `split-skill` |
    | Duplicate coverage | >70% topic overlap | Propose `merge-skills` |
    | Stale description | Description != content | Propose `fix-description` |
    | Broken reference | Referenced but missing | Propose `fix-references` |
    | Doc count mismatch | CLAUDE.md != disk | Propose `sync-docs` |
    | Description budget | Total >8K chars | Propose `fix-description` (shorten) |

7.  **GENERATE REPORT**: Present findings:

    ```
    === OPTIMIZATION REPORT ===

    Framework Health: GOOD / NEEDS ATTENTION / BLOATED
    Total components: N agents, M skills, K commands, T templates
    Total lines: XXXX
    Description budget: YYYY / 8000 chars (ZZ%)

    Issues found: N
    - Critical: X
    - Recommended: Y
    - Optional: Z

    === PROPOSALS ===
    (listed by risk: Low → Medium → High)
    ```

8.  **APPROVAL GATE**: Follow the evolution.md approval process:
    - List all proposals with numbers
    - Ask: "Which proposals should I apply? (all / none / comma-separated numbers)"
    - Wait for explicit response
    - Apply ONLY approved changes

9.  **APPLY AND SYNC**: After applying changes:
    - Update CLAUDE.md: agent/skill/command tables and counts
    - Update README.md (repo): feature counts, agent table, skills table, commands table, directory structure counts
    - Update README.md (project): counts
    - Update dr-help.md: command list, agents list, counts
    - Log all changes in `datarim/docs/evolution-log.md`

10. **VERIFY**: Run final check:
    - All counts in docs match actual files
    - No broken cross-references remain
    - All proposed changes applied correctly

## Output
- Full audit report with dependency graph
- Optimization proposals with risk levels
- Applied changes summary
- Updated documentation

## Next Steps
- Applied structural changes? → Test with `/dr-help` to verify commands list
- Removed components? → Check that no workflow is broken
- Need deeper restructuring? → Use `/dr-design` with consilium panel

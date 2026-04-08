---
name: compliance
description: Post-QA hardening and PRD revalidation (7-step workflow, compliance report)
---

# /compliance - Compliance Mode

**Role**: Compliance Agent
**Source**: `$HOME/.claude/agents/compliance.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/compliance.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/init`. Do NOT create it — only `/init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/compliance.md` (workflow, report structure, Code Simplifier principles — self-contained in .claude).
4.  **CONTEXT**: Read project context (activeContext, tasks, PRD) when present.
4.  **ACTION**:
    - Execute steps 1-7 in order (change set & PRD alignment → simplify → references → coverage → lint/format → tests → optional hardening).
    - For step 2, apply Code Simplifier principles from the skill (optionally `$HOME/.claude/agents/code-simplifier.md`).
    - If project has `datarim/reports/`, write report file there; else output report in chat.
    - Summarize results in chat.
5.  **OUTPUT**: Compliance report (file or chat) + chat summary.

## Next Steps
- Compliance done? → `/reflect`

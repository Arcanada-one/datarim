---
name: do
description: Implement planned changes using TDD and AI quality principles
---

# /do - Implementation Mode

**Role**: Developer Agent
**Source**: `$HOME/.claude/agents/developer.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/developer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/init`. Do NOT create it — only `/init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/ai-quality.md`.
4.  **CONTEXT**: Read `datarim/tasks.md` (Implementation Plan).
4.  **ACTION**:
    - **TDD Loop**: Write test -> Fail -> Code -> Pass.
    - Implement one stub/method at a time.
    - Follow `datarim/patterns.md`.
5.  **OUTPUT**: Code changes + `progress.md` update.

## Next Steps
- Implementation done? → `/reflect`

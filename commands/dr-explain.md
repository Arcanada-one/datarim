---
name: dr-explain
description: Re-explain a task outcome or term in clear language without executing work, changing facts, or accepting the result.
---

**Language preferences:** Before output or delegation, read `${DATARIM_RUNTIME:?}/skills/datarim-system/language-preferences.md` and run its resolver for the consuming project. Apply resolved replies/artifacts independently and pass both tags to children; preserve exact machine output.

# /dr-explain - Explain the result again

Use this command when the user requests a clearer explanation. It preserves facts
and reads existing evidence; it never resumes task execution.

Load `${DATARIM_RUNTIME:?}/skills/datarim-system/SKILL.md` and
`${DATARIM_RUNTIME:?}/skills/human-outcome-reporting/SKILL.md`.
Read `${DATARIM_RUNTIME:?}/skills/human-outcome-reporting/references/re-explain.md`
and the relevant scoped terminology rules when needed.

Usage: `/dr-explain [task or report] [specific question]`.

Resolve the requested task using authorized existing project sources. With no task
argument, explain the result the user is currently asking about; do not select an
unrelated active task. Do not require workflow initialization for a simple term.

Return a standalone explanation in the resolved reply language. Lead with the observed result and material limitation. State
what was requested, what the user can now do, what was verified, what remains open,
and any necessary next action. For a narrow question, explain that aspect only.

Read-only: no code edits, tests, deployment, new subagents, commit, push, glossary
edits, scope changes, task-state changes or automatic continuation. No new check
receipt. Do not equate understanding with acceptance. Correct a false previous
conclusion explicitly using the available evidence. Separate historical and current
states. Missing context is disclosed, never invented. Keep strict machine formats
intact and do not append an execution CTA that resumes work automatically.

# Datarim for everyone

Datarim helps you turn a request into work you can check. You might ask for a
website change, a research summary or a document. Datarim helps an AI assistant
clarify the outcome, plan the work, carry it out and explain the evidence. It
works inside selected projects with Claude Code, Codex and Cursor.

**Orchestration means coordinating the work.** Different agents take roles such
as planning, writing and reviewing. Datarim passes context between them and
brings their findings back into one task. An optional plugin can also coordinate
terminal sessions. You can follow the outcome without directing every specialist
by hand.

**Use `/dr-auto` for a task that needs several stages.** Describe what you want,
and it selects the required stages, delegates work and checks the results. For
a full task, it continues through passing compliance and reflection: checking
that the requirements were met and recording lessons. Archiving is a separate
step. Permission and irreversible-action boundaries still apply.

**Use `/dr-quick` for a tiny edit or an information lookup.** For example, fix a
small wording mistake or find an existing setting. This route skips the full
planning and review cycle. Edits still need evidence that they worked and reached
the shared main branch; a larger request moves to the full workflow. Lookups
remain informational answers.

**JEV helps choose how much AI capability a task needs.** It classifies work and
advises a model tier and reasoning effort. This advice needs configured API
access and does not switch the model already running in your conversation.
JEV also has a separate safety check for dangerous commands, which works without
an API key. Advice does not prove that a result is correct.

**Human Outcome Reporting explains the result in ordinary language.** It tells
you what you can now do, what was checked and what remains open. `/dr-explain`
clarifies an existing result without repeating the work. You can also install
[reporting by itself](../how-to/install-human-outcome-reporting.md).

**Datarim 4.3.0 lets conversation and documents use different languages.**
`language.replies` and `language.artifacts` both default to English (`en`). You
could choose French replies while keeping project documents in English. Save
personal preferences or project defaults; changing them needs no reinstall.
Standalone reporting reads the same preferences. Start a fresh conversation
when an older session still carries previous settings. Native client rules and
security retain authority.

Fixed report labels use available language catalogs. Missing coverage is
explicitly disclosed as an English fallback; supplied prose, quotations, code
and machine values are preserved. See [language setup](../how-to/configure-languages.md)
for the practical steps and [the reference](../reference/language-preferences.md)
for precedence and limits. To begin using the workflow, follow the
[installation guide](../../INSTALL.md) and [first-task tutorial](../tutorials/getting-started.md).

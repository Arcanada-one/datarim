# Explanation — Understanding-Oriented Documentation

Explanation builds mental models. It is the analytical, reflective genre: it
answers "why" rather than "how". Why a component is designed this way, which
principles underpin it, how it fits the whole. Digressions, comparisons, and
historical background belong here.

## When to write here

- Architectural overviews and the rationale behind a design.
- Design decisions and their trade-offs.
- Conceptual background needed to understand the domain.
- Comparisons of alternatives and the reasoning behind the choice made.
- How and why a component evolved over time, and what was learned.

## When NOT to write here

- A first end-to-end learning experience → [`tutorials/`](../tutorials/)
- A recipe for accomplishing a task → [`how-to/`](../how-to/)
- Factual lookup — flags, schemas, catalogues → [`reference/`](../reference/)

## Naming convention

Kebab-case `.md` filenames naming the concept, for example `pipeline.md`,
`symlinks.md`.

## Contents

| File | What it explains |
|------|------------------|
| [`pipeline.md`](pipeline.md) | Each pipeline stage, what it produces, and why the ordering is what it is. |
| [`consilium.md`](consilium.md) | Why multi-agent panels exist and when a panel beats a single agent. |
| [`evolution.md`](evolution.md) | The self-evolution loop and why human approval gates it. |
| [`symlinks.md`](symlinks.md) | The symlink-default operating model, its trade-offs, and its limitations. |
| [`plugin-author-guide.md`](plugin-author-guide.md) | The plugin model — design intent, manifest semantics, authoring guidance. |
| [`spec-traceability-rollout.md`](spec-traceability-rollout.md) | Why spec traceability was introduced and how it was rolled out. |
| [`codex-slash-command-upstream-advocacy.md`](codex-slash-command-upstream-advocacy.md) | Background on the Codex CLI slash-command gap and the upstream position taken. |

## Related reserved siblings

`documentation/` also hosts directories that are deliberately **not** Diátaxis
categories and must not be folded into one: `archive/` (completed task
archives), `evolution/` (quarterly framework-evolution snapshots),
`release-audit/` (per-release audit records), and `ephemeral/` (transient
working material). See `skills/diataxis-docs/SKILL.md` § Reserved Sibling Names.

---

Category definition: `skills/diataxis-docs/SKILL.md`. See also the
[Documentation Taxonomy Mandate](../../CLAUDE.md) in `CLAUDE.md`.

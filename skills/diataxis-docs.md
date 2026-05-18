---
name: diataxis-docs
description: Diátaxis documentation taxonomy mandate four orthogonal categories tutorials how-to reference explanation for every Datarim-managed repo and product site
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Diátaxis Documentation Taxonomy Mandate

> Loaded by `/dr-init` project scaffolding, `/dr-optimize` audit, and `/dr-archive` surface verification.
> Source-of-truth for documentation taxonomy contract across the Arcanada ecosystem.

## When This Skill Activates

- During `/dr-init` project scaffolding — defines the default `docs/` directory structure with 4-category split.
- During `/dr-optimize` audit Step 6 — runs filesystem-presence check and detects repos without the mandated layout.
- During `/dr-archive` surface verification — validates that site surfaces (public-facing pages) comply with the mandate.
- When an operator or agent asks about documentation taxonomy rules — provides binding definitions and mapping.
- When evaluating a new repo or product site for inclusion in the ecosystem — determines whether mandate applies.

## Mandate Scope

- **Obligatory** for all new repos and product sites created under Datarim framework scaffolding.
- **Soft audit** for existing repos — `/dr-optimize` warns but does not block; operator may acknowledge or spawn an INFRA-* migration task.
- **Stack-agnostic** — the mandate describes taxonomy (directory layout + content-type contract), not SSG/CMS choice. Any static site generator may be used.
- **Slogan compliance required** — each updated public site must display the ecosystem slogan (see § Slogan Compliance).

## The Four Categories

### Tutorials

Learning-oriented category for beginners. Reader intent: acquire foundational knowledge through guided step-by-step experience. Typical content: getting-started guides, walkthroughs, interactive lessons, first-application tutorials. The reader does not yet know what questions to ask.

### How-to

Task-oriented category for practitioners. Reader intent: solve a specific problem or complete a concrete task. Typical content: deployment guides, testing recipes, debugging instructions, configuration steps. The reader knows what they want to do and seeks precise instructions.

### Reference

Information-oriented category for lookup. Reader intent: find exact parameters, API signatures, configuration keys, or specification details. Typical content: API documentation, command-line flags, configuration schema, glossary, data types. The reader needs accurate and complete factual information.

### Explanation

Understanding-oriented category for deep comprehension. Reader intent: understand why something works the way it does. Typical content: architectural overviews, design decisions, conceptual background, tradeoff analysis, comparisons. The reader seeks mental models and contextual understanding.

## Repo Bootstrap Layout

```
<project-root>/docs/
├── tutorials/
│   └── README.md
├── how-to/
│   ├── README.md
│   ├── testing.md           (*)
│   ├── deployment.md        (*)
│   └── gotchas.md           (*)
├── reference/
│   ├── README.md
│   └── architecture.md      (*)
├── explanation/
│   └── README.md
├── ephemeral/                (transient working material — unchanged)
│   ├── plans/
│   ├── research/
│   └── reviews/
```

(*) — legacy stubs auto-mapped from the pre-mandate flat scaffold for backwards compatibility. Idempotency rule: each file or directory is created only if it does not already exist. An optional `docs/index.md` may serve as an entry-point with links to the four categories — its presence or absence does not affect mandate compliance.

## File-Naming Convention

- All documentation files use `kebab-case.md`.
- Each category directory contains exactly one `README.md` stub file (mandatory).
- Contextual content files within a category use descriptive kebab-case names (e.g., `deployment-strategy.md`, `api-authentication.md`).
- No prefixes or numeric ordering — category membership is determined by directory placement, not naming convention.

## Mapping Table

Closed set — every documentation type maps to exactly one Diátaxis category.

| Legacy or proposed type | Diátaxis category | Rationale |
|-------------------------|-------------------|-----------|
| architecture (default) | reference | Information-oriented — describes system structure |
| architecture (why) | explanation | Understanding-oriented — design decisions, tradeoffs |
| testing | how-to | Problem-solving — how to run tests, configure CI |
| deployment | how-to | Problem-solving — how to deploy the application |
| gotchas | how-to | Problem-solving — what to do when typical errors occur |
| api | reference | Information-oriented — lookup documentation |
| cli | reference | Information-oriented — command signature and flags |
| config | reference | Information-oriented — configuration schema and keys |
| concepts | explanation | Understanding-oriented — conceptual background |
| design | explanation | Understanding-oriented — design rationale |
| tutorial | tutorials | Learning-oriented — first end-to-end experience |
| quickstart | tutorials | Learning-oriented — minimal guided setup |
| faq | how-to or explanation (split) | Procedural items → how-to; conceptual background → explanation |
| troubleshooting | how-to | Problem-solving — what to do when something breaks |
| examples | how-to or reference | Task-driven examples → how-to; catalogue examples → reference |
| glossary | reference | Information-oriented — definitions |

This is a **closed set**. No new documentation types (FAQ, glossary, troubleshooting, examples, overview, about, samples) may be introduced as separate top-level categories. Every existing or proposed content type must be mapped into one of the four canonical categories.

## Anti-Patterns

1. **FAQ as fifth category.** FAQ is a conglomerate of how-to (problem-solving) and explanation (background). Maintain a mapping decision per FAQ item rather than creating a separate FAQ directory. Mitigation: split FAQ entries into the appropriate categories with cross-links.

2. **Examples as fifth category.** Examples are either task-driven (how-to) or catalogues (reference). An isolated examples bucket masks missing decomposition. Mitigation: place each example in its semantic category with explicit context.

3. **Architecture always as reference.** Architecture content can be reference (information-oriented) or explanation (understanding-oriented). Content that describes design decisions, tradeoffs, and reasoning must live under `explanation/`. Mitigation: evaluate whether the reader looks up facts or seeks understanding — place accordingly.

4. **Index page as separate category.** `docs/index.md` is an optional entry-point, not a documentation type. It does not create a fifth category. Mitigation: index is a navigation aid, not a container for content.

5. **Troubleshooting as separate category.** Troubleshooting content is purely how-to — "when something breaks, do X". Mitigation: place under `how-to/` with clear problem-description titles.

6. **Cross-category content drift.** Over time, a tutorial may accumulate how-to content, or a how-to guide may expand into explanation territory. The category no longer reflects the dominant reader intent. Mitigation: during reviews, check each file against its category definition and split if necessary.

## Exemption List

- Research-only repos (no user-facing documentation required).
- Archive-only repos (snapshots, backups, historical records).
- Obsidian vaults using PARA structure (Inbox / Daily Notes / Templates / Areas / Resources / Origins).
- Single-file inbox notes or scratch documents (ephemeral, non-public).
- Legacy repos created before the mandate soft-approval date (existing-as-of-mandate snapshot recorded in `datarim/docs/exemptions.json`).
- Temporary scratch paths (`temp/*`, `scratch/*`, `test-scaffold/*`).

> **Operator override:** Any repo may be explicitly marked as "intentional — exemption pending review" in the exemption registry (`datarim/docs/exemptions.json`, future TUNE-*). Acknowledged repos are excluded from `/dr-optimize` drift detection until the override is revoked.

## Stack-Agnostic Boundary

This skill MUST NOT name any specific SSG or CMS (e.g., Docusaurus, Mintlify, VitePress, Hugo, Sphinx). The choice of document generator is per-project and outside the scope of the taxonomy mandate. Examples of generator-specific configuration are permitted only within `<!-- gate:example-only -->` fences in companion templates, never in this skill.

## Drift Detection

Mandate compliance is verified by `/dr-optimize` Step 6 using a filesystem-presence check (Option B: threshold 3 docs files + all 4 directories required). Detection is soft — warning only, no build-blocking. A future hard CI gate (enforceable exit code 1) is deferred to an INFRA-* backlog item, to be activated after mandate adoption on at least three live consumers.

## Cross-References

- Mandate section in `~/arcanada/CLAUDE.md` (workspace contract, after Operational Resilience Mandate).
- Scaffold templates at `templates/docs-diataxis/{tutorials,how-to,reference,explanation}/README.md`.
- Bootstrap implementation in `skills/project-init.md` Step 4.
- Drift detector in `commands/dr-optimize.md` Step 6.
- Canonical Diátaxis specification: https://diataxis.fr
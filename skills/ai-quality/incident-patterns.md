---
name: ai-quality/incident-patterns
description: Incident-driven safety patterns — narrative guards, scope decisions for untracked files, operator-first attribution. Load when reviewing safety controls or integration failures.
---

# Incident-Driven Safety Patterns

## Incident-Narrative in Safety Guards

When adding a non-obvious safety control (confirmation prompts, destructive-flag guards, permission checks, rate limits), cite in the runtime message the **incident ID + one-line effect** that motivated the control. This turns the guard into its own documentation: the operator sees *why* at the moment it triggers, without needing to open docs or git history.

### Why

A silent guard (`"Confirm? [y/N]"`) teaches nothing. Operators either learn its rationale by accident — when it fires on their own mistake — or they bypass it because they don't understand it. Either path erodes the guard over time.

A narrated guard carries the original lesson forward. Future operators, LLM agents included, learn from the incident without reproducing it.

### Pattern

```bash
echo "WARNING: --force on a live system will overwrite $CLAUDE_DIR"
echo "         TUNE-0003 incident: --force previously destroyed 9 runtime evolutions."
```

Two lines. First states the *what* (effect of proceeding). Second states the *why* (incident that exists because someone already proceeded).

### Rules

1. **One incident per guard** — cite the *founding* incident, not a list. If the guard accretes history, the most-costly incident wins.
2. **Quantify the effect** when possible (files lost, hours spent, users affected). "Destroyed 9 runtime evolutions" is clearer than "caused problems".
3. **Cite by ID, not by date** — IDs (`TUNE-0003`, `DEV-1156`) index into archives; dates rot.
4. **Keep it to ≤ 2 lines** in runtime output. Long narratives belong in docs; this is a reminder, not a lecture.
5. **Update the reference when superseded** — if a later incident replaces the original justification, rewrite both the guard and the archive cross-reference. Do not layer old and new together.

### When to skip

- Guards for completely self-evident constraints (typing `yes` to confirm destructive action). The prompt itself is the narrative.
- Compile-time or lint-level guards that never reach a human at runtime.
- Guards with no user-visible output (internal invariant checks).

### Exemplar

`install.sh:115` (TUNE-0004) — `--force` live-system warning cites TUNE-0003 by ID and quantifies the cost (9 files). The guard fires before any filesystem mutation; the operator has context before making the decision, not after.

---

## Scope Decision for Untracked Load-Bearing Files

When a task's sweep phase touches files in an untracked-but-load-bearing part of a repository (e.g. `data/*.php` cards that the website reads at runtime but that were never `git add`-ed), make the governance call **before staging**, not during:

- **(a) Promote now** — commit the untracked files as part of the current task. Document in the commit message that promotion is incidental to the task, and list which files were newly tracked. Acceptable when the files are stable and the task naturally touches them.
- **(b) Defer** — create a separate governance task to audit and commit the untracked layer. Continue the sweep on already-tracked files only.

Do not start staging without choosing (a) or (b). Mixing tracked and newly-promoted files without a conscious decision creates hidden scope creep that is hard to audit later.

Rationale: TUNE-0013 Phase 5a promoted 26 untracked `datarim.club/data/*.php` files. The decision was correct but made at staging-time, not at sweep-planning-time — resulting in scope creep that had to be explained retroactively.

---

## Operator-First Attribution

When a framework, vendor, or external service fails during integration, **default attribution is operator error** until proven otherwise.

### Rule

Before concluding "vendor bug" / "framework limitation" / "integration floor":

1. **Reproduce via minimal API** — curl the vendor endpoint directly, raw SDK call, docs example. If the minimal repro succeeds, the failure is on the operator's side (config, model choice, document format, timeout).
2. **Vendor blame requires BOTH:** (a) minimal repro confirms the failure, AND (b) reading the docs cannot flip it.
3. **Stop burning budget** — if retry loops are consuming tokens/money during the run, halt and diagnose before proceeding.

### Why

LTM-0002 first run ($20.32 wasted) blamed OpenRouter for Cognee's embedding failure, Claude Sonnet for JSON parse errors, and laptop RAM for Graphiti's absence. All three were operator errors:
- `curl` proved OpenRouter embeddings work (wrong LiteLLM prefix, not vendor protocol)
- Document pre-processing fixed JSON parse failures (not a language-level ceiling)
- arcana-dev has 62 Gi RAM (self-imposed laptop constraint)

### When to apply

Every integration failure during `/dr-do`. Before writing "framework X doesn't support Y" in a report, verify with a 5-minute minimal repro. The cost of a curl test is 5 minutes; the cost of a wrong attribution is a wrong article, a wrong vendor choice, and wasted operator budget.

### Exemplar

LTM-0002 R2: single `curl` to OpenRouter `/v1/embeddings` with `encoding_format="float"` → 1536-dim vector. Proved in 30 seconds that the vendor works. Cognee's failure was my `openai/` LiteLLM prefix routing to the wrong handler — fixed by switching to `openrouter/` prefix.
# INSIGHTS — TUNE-0054 (CLAUDE.md + shipped-doc reference linter)

**Date:** 2026-04-29
**Source:** TUNE-0050 reflection Class B Proposal B1 (N=2 phantoms)
**Outcome:** `scripts/check-doc-refs.sh` LIVE, 11/11 ACs PASS, baseline `.docrefignore` snapshot frozen.

---

## Pre-existing orphan inventory (baseline snapshot)

The linter's first run on `code/datarim/` HEAD (`--no-baseline` mode) reported **1 real orphan** after backtick-strip fix landed mid-implementation. All other historical occurrences (12 of the initial 13) turned out to be backtick-protected mentions inside code spans — fixed by extending the AWK pre-processor to strip inline backticks before bare-path extraction (not just markdown-link extraction).

### Confirmed orphan (whitelisted in `.docrefignore`)

| # | File:line | Target | Resolved | Notes |
|---|---|---|---|---|
| 1 | `skills/security-baseline.md:401` | `../templates/security-workflow.yml` | `templates/security-workflow.yml` | Listed under "Reusable Templates" but never authored. Origin: TUNE-0045 P2 security gate epic — landed `templates/security-deps-upgrade-plan.md` but `security-workflow.yml` was a planned drop-in CI snippet that was scoped out without removing the doc reference. Carry-over phantom; cleanup deferred to TUNE-0064. |

### Mid-implementation backtick-strip discovery

Initial self-dogfood run reported 13 orphans. 12 of them were false positives — the AWK pre-processor stripped inline backticks for markdown-link extraction (`[text](target)`) but not for bare-path extraction (`skills/foo.md` mentions in prose). Fix: bare-path scan now operates on the same backtick-stripped variant.

The 12 false positives all matched the pattern: code-span mentions like `` `datarim/docs/activity-log.md` `` or `` `local/skills/my-org-style.md` `` in narrative text where the prose intentionally references a path-like string but does not require it to resolve. Examples:

- `skills/dream.md:145` — `Dream appends to \`datarim/docs/activity-log.md\`:` — narrative description, not a link.
- `agents/librarian.md:20` — `Append every maintenance action to \`datarim/docs/activity-log.md\`.` — same pattern.
- `skills/datarim-system.md:58` — `(\`local/skills/my-org-style.md\`) to avoid accidental overrides...` — referring to an external concept.
- `templates/project-claude-md.md:95-98` — `\`docs/architecture.md\``, etc. — template placeholders consumers create.

This validates the design decision to treat backtick code spans as opaque (markdown convention: backtick = literal, not a link).

---

## Open question resolutions (locked at /dr-plan, validated at /dr-do)

| # | Question | Plan-time decision | /dr-do confirmation |
|---|---|---|---|
| 1 | Scan scope — `code/datarim/` only or `~/.claude/` runtime mirror? | Only `code/datarim/`. | Confirmed. Runtime mirror divergence = install-time concern, separate gate (`tests/install.bats`). |
| 2 | Pre-existing orphan baseline — block or accept? | `.docrefignore` accepted-debt + document. | 1 confirmed orphan whitelisted; cleanup deferred to TUNE-0064. |
| 3 | CI wiring — extend `security.yml` or new workflow? | Extend `security.yml`. | New `doc-refs` job added parallel to existing 12 jobs. |
| 4 | Class A or B? | Class A (internal tooling, no operator-facing contract). | No VERSION bump, no datarim.club changelog. Promotion to Class B = follow-up if linter wired as mandatory `/dr-archive` blocking gate. |

---

## Spawn-trigger log

- N=2 met at TUNE-0050 reflection (`skills/security-baseline.md` + `docs/standards-mapping.md` phantoms shipped through `/dr-archive` undetected).
- Recurrence pattern «Memory Rule → Executable Gate at Apply Step» — 7th iteration (TUNE-0044/0056/0058/0059/0060/0061/0054).

---

## Follow-ups proposed

| ID | Title | Priority | Spawn condition |
|---|---|---|---|
| **TUNE-0063** | Extend doc-ref linter to `~/.claude/` runtime mirror | low | N=2 mirror-divergence incidents (currently N=0) |
| **TUNE-0064** | Resolve `.docrefignore` baseline (delete `templates/security-workflow.yml` reference or author the file) | low | Standalone cleanup; can run any time |
| **TUNE-0065** | Promote linter to mandatory `/dr-archive` blocking gate (Class B) | low | N=2 phantom-reference incidents bypassing advisory mode |

None mandatory.

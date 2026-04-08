---
name: compliance
description: Post-QA hardening workflow (7 steps): change set vs PRD/task, code simplification, references/dead code, test coverage, linters, test run, optional hardening. Use with /compliance or any post-implementation review.
---

# Compliance Workflow Skill

> **Self-contained.** Use when running /compliance or any post-QA hardening flow. No external spec file required.

## Inputs (when present in project)

- **Current task:** From activeContext (task ID, title) if project has datarim; else from context.
- **PRD or task description:** From project prd/ or tasks if present.
- **Base branch:** Default `main` or `master`.
- **Changed files:** From Git diff (current vs base) if repo; else from task context.

## Steps (execute in order, best-effort)

1. **Change set & PRD/task alignment** — Get diff; re-check changes align with PRD/task; report drift.
2. **Code simplification** — Apply Code Simplifier principles below (and optionally `.claude/agents/code-simplifier.md`) to **recently modified code** only.
3. **References and dead code** — Check refs; flag/remove unused variables and imports; optional dead code.
4. **Test coverage** — If project requires tests: verify coverage of changed code; report gaps; suggest or add tests.
5. **Linters and formatters** — Run linters (fix or document); run formatter (e.g. Prettier); apply.
6. **Test execution** — Run test suite; report pass/fail; list failures if any.
7. **CI/CD impact analysis** — Check if changes affect CI/CD pipeline:
   - **Deleted/moved files:** If any files were deleted or moved (especially route files, pages, components), verify that no build artifacts, caches, or generated files still reference the old paths. In particular:
     - Next.js `.next/types/` caches route type validators — stale entries cause TS errors on CI where caches persist across runs.
     - Check `.gitlab-ci.yml` (or equivalent) for cache cleanup steps. If the project has `GIT_CLEAN_FLAGS: none`, stale caches WILL persist.
     - Check for references to old paths in: config files, import maps, route configs, CI scripts, nginx configs, documentation.
   - **New dependencies:** If `pnpm-lock.yaml`/`package.json` changed, verify CI installs them correctly.
   - **New env vars:** If new environment variables are used, verify they are in `turbo.json` `env` arrays and CI `variables:` blocks.
   - **Build output:** If build outputs changed (new pages, removed pages), verify deploy scripts handle them.
   - Report any CI-breaking risks found.
8. **Optional hardening** — Error handling consistency; dependency audit if lockfile changed; security scan if project has it.

## Output — Report structure

Write report with these sections:

1. PRD alignment (ok | drift)
2. Simplification applied (yes | no + summary)
3. References/unused (fixed | reported)
4. Coverage (ok | gaps)
5. Lint/format (run + fixes)
6. Tests (pass | fail)
7. CI/CD impact (ok | risks found + fixes)
8. Optional hardening (done | skipped)
9. Remaining risks/follow-ups

**Report path:** If project has `datarim/reports/`, write `datarim/reports/compliance-report-[task_id]-[date].md` (use `date +%Y-%m-%d` for date). Otherwise output report in chat only.

## Error handling

- No Git → infer changed files from task context.
- No PRD → use task description from context/tasks.
- Step failure → record in report; continue all steps; list all failures at end.

## Code Simplifier principles (for step 2)

1. **Preserve functionality** — Do not change what the code does; only how.
2. **Apply project standards** — Follow project coding standards (e.g. CLAUDE.md, style guide).
3. **Enhance clarity** — Reduce nesting; clear names; no nested ternaries (prefer switch or if/else); clarity over brevity.
4. **Maintain balance** — Avoid over-simplification; keep code debuggable and extendable.
5. **Scope** — Focus on recently modified code only unless instructed otherwise.

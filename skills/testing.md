---
name: testing
description: Testing pyramid, frameworks, mocking. Load first; then the fragment for the active gate (live smoke, silent failure, bats, legacy triage).
---

# Testing Guidelines

> **Always load this entry first.** Detailed gates live in supporting fragments to keep idle context cost low.

## Frameworks

<!-- gate:example-only -->
- **Backend**: Jest / Mocha / Vitest
- **Frontend**: Vitest / React Testing Library
- **E2E**: Playwright / Cypress
<!-- /gate:example-only -->

## Testing Pyramid

1. **Unit Tests (70%)**: Test individual functions/classes in isolation. Mock all dependencies.
2. **Integration Tests (20%)**: Test interaction between modules/database.
3. **E2E Tests (10%)**: Test critical user flows.

## Mocking Rules

- Mock external APIs (Stripe, AWS, etc.).
- Mock database calls in unit tests.
- Use dependency injection to make mocking easier.
- **Never mock the thing you're actually testing.** If the bug class you're trying to prevent lives in the
  real integration (wrong client, wrong schema, wrong dialect), a mocked test will pass and production will
  fail. See § Live Smoke-Test Gates below.

---

## Discipline

For test-first discipline (RED-GREEN-REFACTOR cycle, the Iron Law that no production code ships without a failing test first, the rationalization table that pre-answers "I'll test after / it's too simple / TDD is dogmatic"), load `skills/testing/tdd-discipline.md`. Apply when implementing any feature or bugfix in a context that warrants TDD — see the entry skill's Mocking Rules and § Live Smoke-Test Gates for what counts as a real test.

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/testing/tdd-discipline.md`
  Use whenever you would otherwise write production code without a failing test first. Mandates the RED-GREEN-REFACTOR cycle, captures the common rationalizations and the canonical responses, and lists the red-flag phrases that mean STOP and start over.

- `skills/testing/live-smoke-gates.md`
  Use for raw-SQL / cross-datasource Live Smoke-Test Gate, cross-container Docker smoke, user-switch deployment gates, and N=1 smoke validation before bulk ingest/transform. Trigger when the change touches `$queryRaw`, multi-datasource code, Docker orchestration, container health, runtime user/permissions, or any bulk run that depends on entity resolution / record linkage / normalization.

- `skills/testing/silent-failure-detection.md`
  Use for wrappers around CLIs/subprocesses that exit `0` on error and write error sentences to stdout (LLM CLIs, cloud tools). Mandates structured-output parsing, raise-inside-wrapper, and testing both exit-code scenarios.

- `skills/testing/bats-and-spec-lint.md`
  Use for shell-script testing with bats-core (isolation, fixtures, alignment tests, SUCCESS markers, sanity guards) and for spec-lint regex assertions over markdown prose contracts.

- `skills/testing/triaging-legacy-failures.md`
  Use when inheriting a test suite with pre-existing failures. Three-bucket triage: stale-delete, fixable-patch, rephrase-the-content.

## Reusable Templates

- `templates/docker-smoke-checklist.md` — 5-step reusable checklist for cross-container smoke (Compose validity → container health → endpoint smoke → end-to-end action with post-conditions → rollback). Reference this when applying the Live Docker Smoke gate.

## Quick Routing Heuristic

- Touching raw SQL, cross-datasource, Docker orchestration, or user-switch deploy? → `live-smoke-gates.md`.
- Wrapping a CLI / subprocess that exits 0 on error? → `silent-failure-detection.md`.
- Writing or maintaining bats tests, or regex-asserting markdown prose? → `bats-and-spec-lint.md`.
- Inherited a red test suite? → `triaging-legacy-failures.md`.

## Why This Skill Is Split

Testing is in the hot path for every QA / `/dr-do` / `/dr-qa` flow. A 426-line monolithic file forced every agent to load the full content even when only one gate was relevant. Split into entry + 4 supporting fragments reduces idle context cost while preserving the full contract.

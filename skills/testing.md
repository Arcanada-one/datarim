---
name: testing
description: Testing pyramid, frameworks, mocking. Load first; then the fragment for the active gate (live smoke, silent failure, bats, legacy triage).
runtime: [claude, codex]
current_aal: 1
target_aal: 2
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

## Coverage Instrumenter Blind-Spot Awareness

When code under test executes through a framework-internal pass-through — raw runtime hooks where the web framework hands the underlying runtime request/response objects to user code, bypassing the framework's own instrumentation seams — the coverage instrumenter may underreport line/branch execution even though tests pass and the code paths run. Symptoms: a controller/handler whose every behavioural test passes yet shows single-digit coverage, threshold regressions appearing immediately after introducing raw-pass code, branch-vs-main coverage delta with no behavioural delta.

**Detection (pre-flight).** Before committing the production code, write a placeholder handler with the same raw-pass pattern, run the full test suite under coverage, and compare reported vs. actual execution. If the discrepancy exceeds a 20pp relative threshold against the same code expressed without raw-pass, treat the gap as instrumenter-blind, not test-suite-incomplete.

**Remediation hierarchy.** Prefer architectural fixes over instrumentation papering:

1. **Refactor-lift (preferred).** Restructure error-handling and data-flow code to exit the pass-through into framework-instrumented layers — global exception filters, interceptors, guards, framework-native error-mapping seams. Throwing a typed exception from the handler body (instrumented) and catching it in a global filter (instrumented) is fully traced. The pass-through callback shrinks to the irreducible minimum: only the line that hands raw objects to the framework-internal API. Refactor-lift produces architectural improvement, not coverage measurement papering.
2. **Switch instrumenter.** If refactor-lift is impractical for the current code shape, change the coverage provider in the test runner config to one that traces through the raw-pass pattern. Document the choice in the test runner config with a comment citing the raw-pass reason.
3. **Ignore comments (last resort).** Apply per-line ignore directives (e.g. `/* coverage-tool ignore next */`) only at the call sites where raw pass-through is unavoidable — typically a single handler line that hands `req.raw` / `res.raw` (or equivalent runtime handles) to a framework-internal callback. Each annotated line carries an inline comment explaining why the instrumenter cannot trace it. Do not blanket-ignore whole methods or files.

**Why this order.** Refactor-lift fixes the underlying architecture and yields real coverage; switching instrumenter is a measurement change with no architectural value but preserves test-suite shape; ignore comments are defence-in-depth for irreducible cases. Reaching for the ignore directive first leaves the architectural smell (error logic interleaved with raw-pass code) in place and creates a maintenance debt — the next reader sees coverage green and assumes the raw-pass path is tested when it is merely excluded.

**Document the decision.** Whichever level of the hierarchy is chosen, record the rationale in the test file or module preamble: which raw-pass call site, which instrumenter behaviour, which remediation level, and (for ignore comments) what the test surface actually exercises. Prevents future contributors from re-litigating the trade-off blind.

---

## Reporting Test Counts in Audit Output

When QA / Compliance reports cite per-spec test counts (e.g. "added 28 tests" or "11 unit tests in `<spec>`"), derive each count via a mechanical extractor of the test-runner's case-declaration syntax — never operator memory. The contract is one line: **report = output of `<extractor> <spec-file>`, recorded verbatim in the audit doc**. The extractor is a per-language regex whose form depends on the test framework family in use; the rule itself is framework-neutral.

<!-- gate:example-only -->
Illustrative extractors (replace with whatever matches the project's test framework):

```bash
# JS/TS Jest/Mocha-style declaration syntax
grep -cE '^[[:space:]]*(it|test)\(' <spec>

# Python pytest function-style declaration
grep -cE '^def test_' <spec>

# Go testing package convention
grep -cE '^func Test' <spec>
```
<!-- /gate:example-only -->

If the audit cites a count that does not match the extractor output for the same revision, treat that as a finding (drift between operator memory and source-of-truth). Source: prior incident — a per-spec count off-by-one in a QA report was caught only by independent re-execution at Compliance.

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

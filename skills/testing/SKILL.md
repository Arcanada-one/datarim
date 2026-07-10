---
name: testing
description: Testing pyramid, frameworks, mocking. Load first; then the fragment for the active gate (live smoke, silent failure, bats, legacy triage).
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
- **Adapter-path fixture.** A mapper/adapter spec MUST drive the real DB-row → mapper → output path — feed a
  raw DB-row fixture into the actual mapper function and assert on its return value. A hand-built output
  object assembled directly in the test bypasses the mapper and masks transformation defects (wrong field
  mapping, type coercion, null handling) even though the mapper class exists and is wired.

## Driver-Side Serialization Simulation

When mocking a DB driver (`bi.execute = mock.fn()`, `pool.query = mock.fn()`, etc.) in a unit test, the test captures bind parameters **before** the driver applies its own serialization. Most drivers transform non-scalar bind values on the wire — and that transformation is part of the production write path your test claims to cover. A naive `typeof p === 'string'` assertion on captured params silently passes for an array bypass that the real driver would JSON-serialize into the column.

**Rule.** Any unit test that captures DB-driver mock params and then asserts column-shape invariants MUST first run the captured params through a `simulateDriverBind(p)` helper that reproduces the driver's serialization:

- Arrays → `JSON.stringify` (default for several SQL connectors when binding to a scalar placeholder — verify per driver).
- Plain objects → `JSON.stringify` (when the target column is text; some drivers also auto-serialize for JSON columns).
- Date / Buffer / typed-array / null / scalar → pass-through.

The simulation is **driver-specific** — declare the helper in the spec file and cite the driver doc that justifies the serialization rules. A simulator for connector X does not work for a test of connector Y; copy-pasting the wrong simulator silently accepts buggy binds.

**Why this matters.** Application-level sanitization (e.g. a `sanitizeValue` that maps arrays → scalars) lives upstream of the bind boundary. A regression that lets an array slip past that sanitizer would be invisible to a mock-based assert but would write a bracketed JSON literal into the column on production. The simulator closes the gap a pure-mock spec cannot.

**When to apply.** Mandatory for every unit test of a DB writer (`UPDATE`, `INSERT`, batch upserts) where the column receiving the bind has a documented format contract (scalar, comma-joined list, JSON, etc.). Skip only when the spec is exercising the driver's typeCast / JSON-column round-trip directly — in that case the driver IS the assertion.

---

## Coverage Instrumenter Blind-Spot Awareness

When code under test executes through a framework-internal pass-through — raw runtime hooks where the web framework hands the underlying runtime request/response objects to user code, bypassing the framework's own instrumentation seams — the coverage instrumenter may underreport line/branch execution even though tests pass and the code paths run. Symptoms: a controller/handler whose every behavioural test passes yet shows single-digit coverage, threshold regressions appearing immediately after introducing raw-pass code, branch-vs-main coverage delta with no behavioural delta.

**Detection (pre-flight).** Before committing the production code, write a placeholder handler with the same raw-pass pattern, run the full test suite under coverage, and compare reported vs. actual execution. If the discrepancy exceeds a 20pp relative threshold against the same code expressed without raw-pass, treat the gap as instrumenter-blind, not test-suite-incomplete.

**Remediation hierarchy.** Prefer architectural fixes over instrumentation papering:

1. **Refactor-lift (preferred).** Restructure error-handling and data-flow code to exit the pass-through into framework-instrumented layers — global exception filters, interceptors, guards, framework-native error-mapping seams. Throwing a typed exception from the handler body (instrumented) and catching it in a global filter (instrumented) is fully traced. The pass-through callback shrinks to the irreducible minimum: only the line that hands raw objects to the framework-internal API. Refactor-lift produces architectural improvement, not coverage measurement papering.
2. **Switch instrumenter.** If refactor-lift is impractical for the current code shape, change the coverage provider in the test runner config to one that traces through the raw-pass pattern. Document the choice in the test runner config with a comment citing the raw-pass reason.
3. **Ignore comments (last resort).** Apply per-line ignore directives (e.g. `/* coverage-tool ignore next */`) only at the call sites where raw pass-through is unavoidable — typically a single handler line that hands `req.raw` / `res.raw` (or equivalent runtime handles) to a framework-internal callback. Each annotated line carries an inline comment explaining why the instrumenter cannot trace it. Do not blanket-ignore whole methods or files.

**Why this order.** Refactor-lift fixes the underlying architecture and yields real coverage; switching instrumenter is a measurement change with no architectural value but preserves test-suite shape; ignore comments are defence-in-depth for irreducible cases. Reaching for the ignore directive first leaves the architectural smell (error logic interleaved with raw-pass code) in place and creates a maintenance debt — the next reader sees coverage green and assumes the raw-pass path is tested when it is merely excluded.

**Document the decision.** Whichever level of the hierarchy is chosen, record the rationale in the test file or module preamble: which raw-pass call site, which instrumenter behaviour, which remediation level, and (for ignore comments) what the test surface actually exercises. Prevents future contributors from re-litigating the trade-off blind.

### Variant — script-style module blind spot (test-include / coverage-exclude symmetry)

A related variant of the same blind spot surfaces when the test runner's `include` glob is extended to a new directory (e.g. one-off seed / migration / admin scripts living outside the runtime source tree) without a mirroring update to the coverage tool's `exclude` glob. The test runner correctly executes the spec files (correctness verification works); the coverage tool then measures the source files those specs imply, but cannot instrument the top-level execution path of a script-style module — the file reports zero covered lines even though internal functions are tested. Symptom: a global lines-coverage threshold that passed yesterday fails today by a small fraction (e.g. 79.66% vs 80% gate) immediately after the `include` glob change; per-file coverage on runtime modules is unchanged.

**Rule.** Whenever the test runner's `include` configuration is extended with a path glob outside the runtime source tree, audit the coverage tool's `exclude` configuration in the same change. Pick one of:

1. **Exclude the script source files from coverage measurement.** Add the same path glob to the coverage `exclude` list. Spec files keep running (correctness preserved); only the coverage stat is excluded. Document with one line citing the instrumenter blind spot.
2. **Refactor the script for instrumentable shape.** Extract the inner work into named exports the spec calls directly, leaving only an irreducible top-level invocation. The exports are instrumented normally.

Discover this gate locally by running the project's coverage command after the `include` change — never let the coverage threshold fail at the next archive gate as the first signal.

---

## Reporting Test Counts in Audit Output

When QA / Compliance reports cite per-spec test counts (e.g. "added 28 tests" or "11 unit tests in `<spec>`"), derive each count via a mechanical extractor of the test-runner's case-declaration syntax — never operator memory. The contract is one line: **report = output of `<extractor> <spec-file>`, recorded verbatim in the audit doc**. The extractor is a per-language regex whose form depends on the test framework family in use; the rule itself is framework-neutral.

<!-- gate:example-only -->
Illustrative extractors (replace with whatever matches the project's test framework):

```bash
# nosec-extract
# JS/TS Jest/Mocha-style declaration syntax
grep -cE '^[[:space:]]*(it|test)\(' <spec>

# Python pytest function-style declaration
grep -cE '^def test_' <spec>

# Go testing package convention
grep -cE '^func Test' <spec>
```
<!-- /gate:example-only -->

If the audit cites a count that does not match the extractor output for the same revision, treat that as a finding (drift between operator memory and source-of-truth). Source: prior incident — a per-spec count off-by-one in a QA report was caught only by independent re-execution at Compliance.

**Commit messages are part of the audit trail too.** When a commit-message body cites added test counts (e.g. `Tests: N new spec cases` or `Full suite: M passed (was K)`), the numbers MUST come from the same mechanical extractor, not operator memory. Commit messages persist in git history and become the durable record once the branch is pushed; rewriting them after push is destructive (force-push) and after merge is impossible. The recommended canonical form for commit-message test deltas is `tests: +N (baseline→total)`, both numbers produced by running the extractor against the pre-commit and post-commit revisions. Source: prior incident — a commit body cited «13 new spec cases (sub-totals 7+3+6)» where the sub-totals themselves summed to 16, and «Full suite: N passed (was K)» where K was off by 3; both arithmetic mistakes surfaced only at the next pipeline gate. Two-second arithmetic checks belong in the extractor pipeline, not in the operator's head.

---

## Producer-Side Smoke Verification for Verdict Gates

When a Definition-of-Done acceptance criterion is a numerical threshold computed by a verdict script over event records emitted by a producer (a daemon, soak harness, ingest pipeline, audit emitter), validate **both halves** in the same pre-archive gate:

1. **Consumer-side smoke** — feed the verdict script synthetic input that mimics the producer's expected output shape and assert it returns the correct exit codes for both pass and fail thresholds. This catches verdict-logic bugs (off-by-one in rate math, wrong field name, missing nullability handler).
2. **Producer-side smoke** — exercise the producer against a realistic input (or one representative cycle), capture an actual event record from the producer's normal output stream, and confirm the record carries every field the verdict script reads. This catches schema-emission bugs (producer dropped a field, fast-path bypass, partial event shape).

Validating only the consumer half against synthetic events is a recurring trap: the verdict script passes, the producer ships, and weeks later the verdict gate runs against real producer output and exits with «no data in window» because the schema the synthetic test used does not match what the producer actually emits in production conditions.

**Rule.** A verdict-gate acceptance criterion is incomplete until the archive doc cites one record from the producer's real output stream that the verdict script would consume successfully. A synthetic fixture is not a substitute.

**When to apply.** Any task that ships a verdict script + acceptance criterion in the same package, where the verdict script is intended to run later against a long-running producer. Skip when the producer is exercised inline in the test (verdict script is unit-tested over the producer's actual output in the same run).

---

## Stability Gate for Spawned-Process / Daemon Integration Tests

An integration test that spawns a real service process (daemon, server, worker) and connects to it over a socket has a timing surface that a whole-suite run can mask. The canonical stability-verification command is the **scoped, repeated** run, not the whole-workspace pass:

- Run the single package/module containing the daemon tests in a tight repeat loop (e.g. ×5–10), AND under the coverage-instrumented binary if the project has a coverage gate. Instrumentation slows process startup/teardown and widens timing windows that a normal build never exposes.
- A whole-workspace run passing N/N is **not** evidence of flake-freedom. The scheduler interleaving under a busy full-suite run differs from the tighter timing under a scoped or instrumented run — a busy machine can accidentally avoid the race window. A "10/10 under the full suite" claim is scheduler luck until reproduced under the scoped + instrumented gate.

**Common root cause — listen-vs-accept race.** A spawned server often prints a "listening on …" / ready line *before* its accept loop is actually polling. A client that does one cold single-shot connect immediately after reading that line can get an instant connection-refused. Widening timeouts does **not** fix this (the failure is instant, not a timeout expiry). The structural fix is either a true readiness contract (signal ready only after the accept loop is live) or a bounded client-side connect-retry on connection errors — the latter also hardens the real CLI/client UX against a just-started service.

**When to apply.** Any task that stabilises or adds a test which spawns a service process and connects to it. Skip for pure in-process unit tests with no spawned subprocess.

---

## Self-Validating UI Assertions

Existence assertions ("element renders any text", "counter is non-empty") pass even when the system under test is broken — they only catch the «nothing rendered at all» case. Prefer **self-validating** assertions that poll the *flipped* target state after the triggering interaction. Self-validation catches three failure modes in one shape:

1. Nothing happened — old state still shown.
2. Wrong thing happened — state changed to an unexpected value.
3. Right thing eventually happened — the assertion times out only on real regressions, not on transient renders.

Pattern (CDP-driven browser test runners like Playwright / Cypress / WebdriverIO):

```
await control.click()
await expect.poll(() => readActualState()).toBe(targetState)
```

`readActualState` returns the *flipped* property of the control (a checkbox's checked-ness, a toggle's aria-pressed, a select's value), not "is text non-empty". `targetState` is the known opposite of the pre-click state. The poll budget is the same number the perf-budget AC declares (commonly 500-1000 ms for a single DOM commit).

**Pitfall — native input vs ARIA attributes.** A native `<input type="checkbox">` does not set `aria-checked` (the attribute is meaningful only on `role="checkbox"` custom controls); query the native `checked` property instead. Component-library wrappers (MUI / Chakra / Mantine / etc.) vary — confirm by inspecting the rendered DOM once before authoring the spec, not after the spec flakes in CI.

**Source.** A perf-budget assertion was first authored as «counter renders any text» and passed even when the toggle was visibly broken; rewriting it as «poll `isChecked()` against the flipped target» surfaced the regression class deterministically.

**When to apply.** Any browser-driven E2E that asserts «interaction X commits state Y within budget Z». Skip for purely visual assertions (computed style audits, screenshot regression) — those are their own pattern.

---

## Defensive-Gate Path Enumeration

When a diff introduces or modifies a defensive write-gate guarding a shared target (column, field, document property, in-memory key — any sink that more than one code path can write to), the gate is not safe in isolation. Enumerate every other writer in the surrounding scope that can land a value at the same key, and add one regression test per distinct writer-pair semantic.

**Rule.** For each writer-pair (gate writer plus one other writer in scope), the regression test must seed the case where writer A produces a non-trivial value X and the gate writer B fires on the same key in the same pass. The assertion checks (a) the documented winner is written, (b) no silent clobber of the loser, (c) no false-fire on the gate's diagnostic emissions. A defensive gate accepted on single-writer coverage alone will silently overwrite the parallel writer's fresh value the first time the two paths converge in production.

**Why this matters.** A silent operator-data-loss regression of this exact shape — gate writer unconditionally assigns into a shared key, the parallel writer's value lost — is invisible to any test that only exercises the gate's intended path. Single-writer coverage proves the gate fires; it does not prove the gate respects concurrent writers. The class is structurally invisible to per-method unit tests; only writer-pair tests catch it.

**When to apply.** Any change to a write-gate, sanitizer, repair pass, or boundary-defence layer where two or more code paths in the same scope can write to the target key. Skip only when the gate's target key is provably write-once (e.g. immutable after first assignment, enforced by language or schema). Document the disjointness claim in a code comment so future readers can re-verify when the surrounding code shifts.

**Where it lives in the diff.** Plan-time: enumerate writers in the implementation note before code. Code-time: add one spec block per writer-pair. Review-time: a reviewer scanning the diff should be able to read the writer-pair list and match each pair to a spec block.

---

## Stubbing Fidelity For Defensive-Gate Tests

When writing a test for a defensive gate, identify every upstream layer (sanitizer, transform, boundary-defence pass, normaliser, validator) that would have already handled the defended-against state before the gate ran in production. Stub those layers to passthrough, not to reproduce the problematic state the gate is defending against.

**Rule.** A defensive-gate test must exercise the gate against a realistic production-failure input — the shape that actually reaches the gate when an upstream layer is failing, absent, or out of date. If the test setup seeds the problematic state upstream of the gate, the test passes through layers that would have already normalised the input in production, and the gate is never genuinely exercised against the failure mode it is designed to catch.

**Why this matters.** A test that seeds a residual literal at the top of an extraction chain and lets the production sanitizer strip it before the gate runs will pass without ever testing the gate. The gate could be removed entirely and the test would still pass. The failure mode the gate is designed to catch — residue surviving the sanitizer chain and arriving at the write boundary — only appears when the sanitizer-chain stub is passthrough, i.e. when the test reproduces the production-stuck shape, not the dev-happy-path shape.

**When to apply.** Any unit test of a defensive gate (repair pass, write-boundary defence, normalisation guard) where one or more upstream layers in the production pipeline would have already handled the defended-against state. Stub each upstream layer to passthrough and seed the problematic value directly at the gate's input boundary. Skip when the gate has no upstream layers (the gate is the first stage in the pipeline); in that case the dev-happy-path input shape coincides with the prod-stuck shape.

**How to identify the right stub layer.** Walk the call chain from request entry to the gate. List every transform that would touch the gate's input slot. Stub each transform to identity. Run the test once with the stubs in place and verify the gate's input matches the prod-stuck observation that motivated the gate's existence in the first place.

---

## Documentation Runtime-Probe Rule

When a skill, agent, command, or in-code docstring documents the behaviour of a parser, library, or runtime quirk — especially edge cases or fail-soft caveats — runtime-probe every claim before commit. A one-line CLI invocation that demonstrates each documented case takes about 30 seconds; the cost of detect-correct at iteration N during a multi-iter verification cycle is hours. The class extends beyond any single library — operator-facing precision matters even for fail-soft caveats, because an inaccurate caveat produces wrong-shaped operator mitigation.

**Rule.** For every behavioural claim in a docstring or skill paragraph that describes how a third-party parser, library, or runtime behaves on edge input (`<!-- example: empty marker `<!-->` is parsed as comment `-->`), demonstrate the claim with a runnable probe. Capture two cases minimum: one that confirms the claim, one that contrasts an adjacent shape the reader might confuse with the documented case. Document the contrast inline so the docstring tells the reader where the boundary actually lies.

**Why this matters.** A docstring whose claim was never runtime-verified at write-time will surface as a finding at the next peer-review pass — sometimes many iterations later, with the inaccurate guidance already shipped to consumers in the meantime. The remediation also costs more: by the time a reviewer flags it, the surrounding context has shifted and the author has lost the mental model of the original probe.

**When to apply.** Any new or modified docstring, skill paragraph, or command instruction whose body asserts how an external parser/library/runtime behaves. Skip only when the claim is purely procedural ("call function X with arguments Y") with no behavioural assertion about a third-party surface.

## Discipline

For test-first discipline (RED-GREEN-REFACTOR cycle, the Iron Law that no production code ships without a failing test first, the rationalization table that pre-answers "I'll test after / it's too simple / TDD is dogmatic"), load `tdd-discipline.md`. Apply when implementing any feature or bugfix in a context that warrants TDD — see the entry skill's Mocking Rules and § Live Smoke-Test Gates for what counts as a real test.

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `tdd-discipline.md`
  Use whenever you would otherwise write production code without a failing test first. Mandates the RED-GREEN-REFACTOR cycle, captures the common rationalizations and the canonical responses, and lists the red-flag phrases that mean STOP and start over.

- `live-smoke-gates.md`
  Use for raw-SQL / cross-datasource Live Smoke-Test Gate, cross-container Docker smoke, user-switch deployment gates, and N=1 smoke validation before bulk ingest/transform. Trigger when the change touches `$queryRaw`, multi-datasource code, Docker orchestration, container health, runtime user/permissions, or any bulk run that depends on entity resolution / record linkage / normalization.

- `silent-failure-detection.md`
  Use for wrappers around CLIs/subprocesses that exit `0` on error and write error sentences to stdout (LLM CLIs, cloud tools). Mandates structured-output parsing, raise-inside-wrapper, and testing both exit-code scenarios.

- `bats-and-spec-lint.md`
  Use for shell-script testing with bats-core (isolation, fixtures, alignment tests, SUCCESS markers, sanity guards) and for spec-lint regex assertions over markdown prose contracts.

- `triaging-legacy-failures.md`
  Use when inheriting a test suite with pre-existing failures. Three-bucket triage: stale-delete, fixable-patch, rephrase-the-content.

## Reusable Templates

- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/docker-smoke-checklist.md` — 5-step reusable checklist for cross-container smoke (Compose validity → container health → endpoint smoke → end-to-end action with post-conditions → rollback). Reference this when applying the Live Docker Smoke gate.

## Quick Routing Heuristic

- Touching raw SQL, cross-datasource, Docker orchestration, or user-switch deploy? → `live-smoke-gates.md`.
- Shipping an agent/daemon/cron that drives a CLI/LLM/subprocess and acts on its output? → `live-smoke-gates.md` § Gate 7 (Agentic Entrypoint Wiring + Live-Run): prove the real entrypoint reaches the declared function AND run it once live against the real tool before any "the agent does X via <tool>" wish can be marked met.
- Wrapping a CLI / subprocess that exits 0 on error? → `silent-failure-detection.md`.
- Writing or maintaining bats tests, or regex-asserting markdown prose? → `bats-and-spec-lint.md`.
- Inherited a red test suite? → `triaging-legacy-failures.md`.

## Why This Skill Is Split

Testing is in the hot path for every QA / `/dr-do` / `/dr-qa` flow. A 426-line monolithic file forced every agent to load the full content even when only one gate was relevant. Split into entry + 4 supporting fragments reduces idle context cost while preserving the full contract.

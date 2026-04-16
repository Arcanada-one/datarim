---
name: testing
description: Testing pyramid, frameworks (Jest, Vitest, Playwright), mocking rules, and the Live Smoke-Test Gate for raw SQL and cross-datasource code. Use when writing or reviewing tests.
---

# Testing Guidelines

## Frameworks
- **Backend**: Jest / Mocha / Vitest
- **Frontend**: Vitest / React Testing Library
- **E2E**: Playwright / Cypress

## Testing Pyramid
1.  **Unit Tests (70%)**: Test individual functions/classes in isolation. Mock all dependencies.
2.  **Integration Tests (20%)**: Test interaction between modules/database.
3.  **E2E Tests (10%)**: Test critical user flows.

## Mocking Rules
- Mock external APIs (Stripe, AWS, etc.).
- Mock database calls in unit tests.
- Use dependency injection to make mocking easier.
- **Never mock the thing you're actually testing.** If the bug class you're trying to prevent lives in the
  real integration (wrong client, wrong schema, wrong dialect), a mocked test will pass and production will
  fail. See § Live Smoke-Test Gate.

---

## Live Smoke-Test Gate

**Who this applies to:** any change whose correctness depends on a *real* external system behaving a specific
way — not on code logic that can be proven in isolation. The canonical trigger is raw SQL and cross-datasource
code, but the principle generalizes.

### When the gate is mandatory

The gate **must** fire (live smoke test is required, not optional) when a change touches any of:

- `$queryRaw`, `$executeRaw`, `raw()`, `sequelize.query()`, `db.exec()`, or any path that bypasses the ORM's
  type-checker and schema validation.
- Multi-datasource projects where more than one client / connection / schema exists and a specific call must
  target a specific one (e.g. reads from `stats` vs `bi_aggregate`, from `primary` vs `replica`, from tenant A
  vs tenant B).
- Migrations, DDL changes, or any code that runs against a schema the unit tests don't represent.
- Queue / message / webhook code where the "contract" is what the receiving system accepts, not what the
  sender thinks it sends.

### Why mocks don't satisfy it

A wrong-client `$queryRaw` **compiles clean** and **passes mocked tests** — because the mock doesn't know
which datasource the real call would hit. The error only appears at runtime, against real data, in a code
path the test suite cannot reach.

Reference incident: **DEV-1156** (aio-v2). A raw query intended to hit `stats` (mysql5) was injected on the
`bi_aggregate` client (mysql8). Unit tests mocked the Prisma client and passed green. Production returned
"table not found" on first request. Root cause: `PrismaService` vs `PrismaBiService` were both valid injections
for the DI container, and the type-checker could not distinguish them for a `$queryRaw` call.

### What a passing gate looks like

Before marking a change with raw SQL / cross-datasource semantics as done, the developer (or `/dr-qa` Layer 4d)
must:

1. Run the query **against the real target datasource** — dev DB, staging DB, or a disposable container
   matching the prod engine and schema. Not a generic Postgres. Not "any MySQL". The *same* engine version
   and the *same* schema as the target.
2. Record in the QA report:
   - The exact command or invocation used (`npx prisma db execute ...`, `psql -h ... -c "..."`, etc.).
   - The datasource hit (host / database / schema — no credentials).
   - The result: row count, expected-empty confirmation, or the error message.
3. In multi-datasource code, **verify the right client was used** — read the import, trace the DI container,
   confirm by output of the smoke test, not by inspection alone.

### What the gate is NOT

- Not a replacement for unit tests. It's an *additional* required step for a specific class of code.
- Not a full integration suite. One passing live call that exercises the actual datasource path is enough.
- Not a release gate for unrelated code. The gate fires only when the change meets the trigger conditions.

### Verdict

- Gate required + gate passed + recorded → **Layer 4 PASS** on this dimension.
- Gate required + gate not run → **Layer 4 FAIL**, not `PASS_WITH_NOTES`. This is the whole point.
- Gate required + gate failed (unexpected result) → stop, diagnose, do not merge.

---

## Spec-Lint Tests for Prose Contracts

Some Datarim commands define their behavior as **markdown prose** (LLM prompt), not executable code. These contracts cannot be functionally tested with bats/vitest — but they *can* be guarded against silent regression via **spec-lint**: regex assertions over the markdown file.

### When to use

When a command's critical behavior is defined in `commands/*.md` prose and you need regression safety that the contract language stays intact across future edits.

### Pattern

```bash
# archive-contract-lint.bats (exemplar — TUNE-0007)
SPEC="${BATS_TEST_DIRNAME}/../commands/dr-archive.md"

@test "branch 1/3: 'Commit now' option is documented" {
    run grep -F "Commit now" "$SPEC"
    [ "$status" -eq 0 ]
}
```

### Rules

1. **One test per contract clause** — each option, keyword, or governance phrase gets its own `@test` so failures pinpoint exactly what was removed.
2. **Use `-F` (fixed string) for exact phrases**, `-E` (regex) only when phrasing may legitimately vary.
3. **Test file lives in `tests/`** alongside functional tests — name it `{command}-contract-lint.bats`.
4. **Complement, don't replace** — if the contract has an executable component (detection script, validator), write functional tests for that *and* spec-lint for the prose wrapper.

### Exemplar

`tests/archive-contract-lint.bats` — 11 tests covering `/dr-archive` step-0 gate: section presence, `git status --porcelain` mandate, multi-repo clause, STOP keyword, 3 prompt branches (Commit/Accept/Abort), governance language, TUNE-0003 attribution. Source: TUNE-0007.

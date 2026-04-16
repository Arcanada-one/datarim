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

## Live Docker Smoke Test Before Archive

**Who this applies to:** any task that orchestrates external shell scripts, performs file I/O across container
boundaries, or makes cross-container HTTP / RPC calls (e.g. NestJS HTTP client → PHP container → bash script
→ mysql client). Mocked unit tests cannot catch this class of bug — the failure mode lives in the runtime
environment, not in the code logic.

### When the gate is mandatory

The gate **must** fire (live Docker end-to-end run is required, not optional) when a change touches any of:

- An HTTP client that calls another container's API which then `shell_exec`s a script (file permissions, exec bit,
  hardcoded hostnames inside the script will not appear in any unit test).
- Code that depends on a specific MySQL/Postgres/Redis client version inside a specific container talking to a
  specific server version (TLS/SSL defaults, auth plugins, character sets — all environmental).
- Volume-mounted config files (`.my.cnf`, `nginx.conf`, `wp-config.php`) where syntax errors are runtime-only.
- Anything that reads/writes filesystem paths inside containers — exec bits, ownership, mount points, `extra_hosts`
  DNS aliases all fail at runtime, not at compile time.

### Why mocks don't satisfy it

A mocked HTTP client returns whatever the test sets up. The real client would have to:
- resolve a hostname (which may not exist in Docker DNS),
- send a request the receiving server actually accepts (auth headers, content-type),
- trigger a script that has the right exec bit and uses the right database hostname,
- which connects to a database with the expected SSL/TLS configuration.

Each of those layers can silently break without a single unit test failing.

Reference incident: **DEV-1169 follow-up** (`reflection-DEV-1169-followup.md`). 241 unit tests passed and the
NestJS clone code merged to main. First-ever live Docker clone (during `/dr-qa` weeks later) surfaced 3
independent runtime bugs: `wp_clone_script_dev` was non-executable in git index (`100644`), SWC version of the
script used hardcoded `-hdb` hostname with no `db` service in Docker, and MySQL 8 PHP clients hit
`self-signed certificate` errors against local MySQL 8 containers. Zero of these were detectable in unit tests.

### What a passing gate looks like

Before marking a change of this class as DoD-complete, the developer (or `/dr-qa` Layer 4) must:

1. Run the actual end-to-end action **in Docker, against real containers**, with no manual hacks like
   `docker exec ... chmod +x` or `docker exec ... echo "alias" >> /etc/hosts`. If you needed those to make it
   work, they belong in the committed `Dockerfile` / `docker-compose.yml` / repository, not in the test session.
2. Record in the QA report: the exact command invoked, the containers it traversed, the post-conditions
   verified (file count delta, DB row count delta, target artifact existence — not just exit code).
3. Verify the legacy callee actually succeeded by inspecting *post-conditions*, not just the parent's
   reported success flag. Legacy Yii / PHP / bash chains often return `success:1` when the script "ran" even
   if it produced no output. Check that the expected DB exists, the expected files were copied, the expected
   row counts match.

### What the gate is NOT

- Not a replacement for unit tests. It's an *additional* required step for tasks of this class.
- Not a full E2E suite. One end-to-end action that exercises the actual cross-container path is enough.
- Not required for pure-logic tasks (helper functions, type definitions, in-process refactors).

### Verdict

- Gate required + live Docker run passed + post-conditions verified → **Layer 4 PASS** on this dimension.
- Gate required + only mocked tests run → **Layer 4 FAIL**. The whole point of the gate is that mocks lie.
- Gate required + live run revealed env hacks needed (chmod, hosts edit, .my.cnf rewrite) → fix them in the
  committed Docker config, re-run, then PASS. Hacks in a session are not a passing gate.

---

## Silent-Failure Detection (exit 0 + error in stdout)

**Who this applies to:** any wrapper around a subprocess, CLI, or external tool whose *exit code cannot be
trusted* because the tool writes error signals into stdout/stderr as normal output. The canonical pattern:
an LLM CLI, a build tool, or a shell utility that exits `0` even when it refused or failed the request.

### When the gate is mandatory

The gate **must** fire (structured-output parsing is required, not exit-code inspection) when:

- A subprocess writes human-readable error sentences to stdout/stderr but exits `0` (e.g. quota-exceeded,
  permission-denied, stale-token, content-filtered — all common in LLM / cloud CLIs).
- A CLI offers both human-text and machine-readable output formats (`--json`, `--output-format stream-json`,
  `--format=porcelain`) AND the machine format is documented. The machine format is the contract; the text
  format is for humans and can drift across versions.
- A wrapper returns the tool's stdout to a downstream consumer that treats it as valid payload (review body,
  generated content, audit record). A silent pass-through poisons downstream state.

### Why returncode-based detection fails

A subprocess returning `0` means "the process ran and did not crash" — NOT "the work was successful."
Many modern CLIs deliberately exit `0` on recoverable conditions to match shell-pipeline ergonomics
(`cmd && next` chains on success-per-intent, not success-per-attempt). If the wrapper only checks `returncode`,
the error message becomes the "result" and flows downstream unlabelled.

Reference incident: **DEV-1183** (aio-py-scripts code-review bot). `claude -p` exits `0` when the 5-hour
subscription window is exhausted and writes `"You've hit your limit · resets 5pm (UTC)"` to stdout. The old
wrapper (`--output-format text` + `returncode != 0` check) treated that as a valid code review, posted it to
GitLab as the review body, AND wrote it to `tbl_code_reviews` as a real review round — poisoning the
`previous_findings` context used by the next retry. The bug lived in production for weeks.

### What a passing gate looks like

1. **Switch the tool to its machine-readable format** if one exists (`--output-format stream-json`, `--json`,
   `--format porcelain`). Capture a live fixture during `/dr-plan` (see `commands/dr-plan.md` § Fixture
   Capture for External Output).
2. **Parse the structured output** for documented error shapes. For `claude -p --output-format stream-json
   --verbose`, the shape is `rate_limit_event.rate_limit_info.status == "rejected"` with a UNIX-epoch
   `resetsAt`. Never regex human sentences; structural fields are stable, prose drifts.
3. **Raise at the narrowest layer.** Raise the domain error *inside* the wrapper function (before returning
   to any caller). Downstream code that treats the return value as trusted never sees an invalid value.
   Raising one layer up means the intermediate side-effects (history writes, logs, cache updates) still run
   on the error branch.
4. **Subclass the legacy exception** so existing `except ParentError:` handlers continue to work unchanged.
   One new branch at the dispatcher; zero refactors elsewhere.

### What the gate is NOT

- Not a replacement for unit tests. It's an *additional* check for wrappers around tools that lie via exit
  code.
- Not required for tools with honest exit codes. `git`, `grep`, `psql` return non-zero on failure — trust them.
- Not a substitute for the Live Smoke-Test Gate. If the change also touches raw SQL or cross-container paths,
  both gates apply.

### Verdict

- Gate required + structured-output parsing + raise-inside-wrapper → **Layer 4 PASS**.
- Gate required + returncode-only detection → **Layer 4 FAIL**, even if unit tests pass with mocks that
  pre-return "valid" stdout.

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

---

## Shell Script Testing with bats-core

When the "code under test" is a bash script (installer, sync tool, deploy wrapper, migration helper), `bats-core` provides the same red-green discipline as Vitest or Jest does for JS/TS. The patterns below are proven in production tests and should be preferred over hand-rolled `assert`-style shell loops.

### When to use

- Installation / sync / deploy scripts that mutate filesystem state.
- CLI wrappers where exit codes and output format are the contract.
- Scripts whose failure modes (permission errors, missing tools, partial writes) are hard to cover with unit tests in the calling language.

### Isolation: `BATS_TEST_TMPDIR` + `HOME` redirection

Every test gets its own `$BATS_TEST_TMPDIR`. Build the entire test universe inside it — never reach outside:

```bash
setup_fixture() {
    export FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
    export FAKE_CLAUDE="$BATS_TEST_TMPDIR/fake-claude"
    export FAKE_HOME="$BATS_TEST_TMPDIR/fake-home"
    mkdir -p "$FAKE_REPO" "$FAKE_HOME"
    # Seed minimal content the script will operate on
    # Copy the real script under test into $FAKE_REPO
}

run_install() {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" "$@"
}
```

**`HOME` redirection is defense-in-depth.** If the script has a fallback to `$HOME/.claude` (or any other home-relative path) and a guard regresses, a test without `HOME` redirection could silently mutate the operator's real runtime. One-line cost, zero ongoing maintenance.

### Fixture-builder pattern

Put shared setup in `tests/helpers/<thing>_fixture.bash` and `load` it at the top of the bats file. Expose three kinds of helpers:

1. **Builders** that produce *known* starting states: `setup_fixture`, `seed_live_runtime`.
2. **Invokers** that wrap the script under test with the right env + capture: `run_install`, `run_install_with_tty_input`.
3. **Assertions over state**, if any cross-test assertion is non-trivial — but prefer plain `[ -f ... ]` and `grep -q` inline.

Each `@test` calls builders at the top, invokes, asserts. No cross-test state.

### Static-grep alignment tests

When two files must stay in lock-step (a constant in code vs a table in docs, `INSTALL_SCOPES` in one script vs `SCOPES` in another, a flag list in `parse_args` vs the `--help` output), write a one-line bats test that greps both and asserts structural equality. This is cheaper and more readable than parameterization or DRY-abstraction:

```bash
@test "scope contract: install.sh INSTALL_SCOPES matches check-drift.sh SCOPES" {
    grep -E "^INSTALL_SCOPES=\\(agents skills commands templates\\)" "$FAKE_REPO/install.sh"
    grep -E "^SCOPES=\\(agents skills commands templates\\)" "$FAKE_REPO/scripts/check-drift.sh"
}
```

A refactor that rephrases either constant without updating both files fails this test loudly. Use for any "two artefacts must agree" contract.

### TTY / non-TTY gating

`bats run` executes without a TTY by default. This is exactly the environment a CI pipeline or pipe sees, so tests that assert `[ ! -t 0 ]` guards work naturally:

```bash
@test "--force on live system, non-TTY, no --yes: exit 1" {
    seed_live_runtime
    run_install --force
    [ "$status" -eq 1 ]
}
```

For TTY-only paths (interactive `read` prompts), use `printf 'yes\n' | ...` or `script -q` (BSD) / `unbuffer` (Linux) where appropriate. Prefer designing CLI flags (`--yes`) over TTY-only paths for testability.

### SUCCESS-marker pattern for two-phase operations

For operations that must complete fully or not at all (backup + overwrite, copy + chmod, ingest + commit), write a terminal marker file *last*. Tests assert the marker's presence as proof of a complete run; operators rely on it as a restore-readiness signal:

```bash
# in the script under test:
cp -R ... "$backup_dir/"          # phase 1
echo "backup_created_at=$ts" > "$backup_dir/SUCCESS"   # phase 2 (last)

# in the bats test:
@test "--force creates backup with SUCCESS marker" {
    seed_live_runtime
    run_install --force --yes
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/force-* | head -1)"
    [ -f "$backup/SUCCESS" ]
}
```

The marker contract ("present ⇒ complete") holds as long as `set -euo pipefail` is on and the marker is written last. No transaction machinery required.

### Sanity-guard tests for destructive flags

For any flag that can do wide damage (`--force`, `--delete-all`, `--reset`), write explicit tests for refused configurations: empty target, filesystem root, `$HOME`, obviously-wrong path. These tests protect against regressions in guards that look "obviously correct" in code review:

```bash
@test "--force with TARGET=/ refused with exit 2" {
    run env TARGET="/" "$FAKE_REPO/install.sh" --force --yes
    [ "$status" -eq 2 ]
}
```

Redirect `HOME` (see above) so these tests cannot accidentally hit the operator's real filesystem even if the guard is buggy.

### Exemplar

`tests/install.bats` + `tests/check-drift.bats` (TUNE-0004): 23 tests covering content-type whitelisting, `--force` safety (live detect, sanity guards, non-TTY, backup+SUCCESS), idempotency, scope-contract alignment, and `.md`-only regression. Shared helper at `tests/helpers/install_fixture.bash`.

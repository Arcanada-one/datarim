---
name: testing/bats-and-spec-lint
description: Shell-script testing with bats-core (isolation, fixtures, alignment tests, SUCCESS markers, sanity guards) and spec-lint regex assertions for markdown prose contracts.
---

# Bats-Core and Spec-Lint

Two patterns for testing artefacts that don't fit conventional code-test runners: shell scripts and markdown prose contracts.

---

## Spec-Lint Tests for Prose Contracts

Some Datarim commands define their behavior as **markdown prose** (LLM prompt), not executable code. These contracts cannot be functionally tested with bats or a JS/TS test runner — but they *can* be guarded against silent regression via **spec-lint**: regex assertions over the markdown file.

### When to use

When a command's critical behavior is defined in `commands/*.md` prose and you need regression safety that the contract language stays intact across future edits.

### Pattern

```bash
# archive-contract-lint.bats (exemplar)
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

`tests/archive-contract-lint.bats` — 11 tests covering `/dr-archive` step-0 gate: section presence, `git status --porcelain` mandate, multi-repo clause, STOP keyword, 3 prompt branches (Commit/Accept/Abort), governance language, incident attribution. Source: prior incident.

---

## Shell Script Testing with bats-core

When the "code under test" is a bash script (installer, sync tool, deploy wrapper, migration helper), `bats-core` provides the same red-green discipline as a JS/TS test runner does for application code. The patterns below are proven in production tests and should be preferred over hand-rolled `assert`-style shell loops.

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

When two files must stay in lock-step (a constant in code vs a table in docs, a scope list in one script vs the equivalent list in another, a flag list in `parse_args` vs the `--help` output), write a one-line bats test that greps both and asserts structural equality. This is cheaper and more readable than parameterization or DRY-abstraction:

```bash
@test "scope contract: install.sh INSTALL_SCOPES matches the documented set" {
    grep -E "^INSTALL_SCOPES=\\(agents skills commands templates" "$FAKE_REPO/install.sh"
    grep -F "agents/, skills/, commands/, templates/" "$FAKE_REPO/documentation/tutorials/getting-started.md"
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
# nosec-extract
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

### Path-matched write gates: test both absolute AND relative target shapes

When the script under test is a write gate that decides whether to act by matching the target path (a backup-before-overwrite hook, a redirect interceptor, a path allowlist), the test suite MUST exercise BOTH the absolute-path and the relative (cwd-relative, bare-name) target shapes. A gate that matches only an absolute pattern silently skips a relative target — and a suite that only ever passes absolute paths cannot catch that skip. The gate could be removed for the relative case and every absolute-only test would still pass.

```bash
# absolute target — the easy case the author reaches for first
@test "redirect to ABSOLUTE critical path is intercepted" {
    run run_gate "echo x > $TMPROOT/datarim/backlog.md"
    [ "$status" -eq 0 ]; [ "$(_count_baks backlog.md)" -eq 1 ]
}
# relative target — the real incident shape (cwd already inside the guarded tree)
@test "redirect to RELATIVE critical path is intercepted (incident vector)" {
    run run_gate "echo x > backlog.md" "$TMPROOT/datarim"   # 2nd arg = payload cwd
    [ "$status" -eq 0 ]; [ "$(_count_baks backlog.md)" -eq 1 ]
}
```

Pair this with the RED-proof discipline: revert the gate's path-canonicalisation and confirm the relative-target test goes RED, proving it is load-bearing rather than vacuous. A relative target reaches the gate whenever the invoking process's cwd is already inside the guarded directory — the most common real-world shape, and the one absolute-only fixtures never produce.

### Exemplar

`tests/install.bats`: ~30 tests covering content-type whitelisting, `--force` safety (live detect, sanity guards, non-TTY, backup+SUCCESS), idempotency, scope-contract alignment, and `.md`-only regression. Shared helper at `tests/helpers/install_fixture.bash`.

### Negated grep assertions: always quiet the matcher

When asserting that a phrase is **absent** from output (or a fixture file), prefer the explicit quiet form:

```bash
# nosec-extract
# Correct: negate exit code AND silence matcher output
run some-script
[ "$status" -eq 0 ]
! echo "$output" | grep -qF "forbidden phrase"
```

Dropping `-q` (`! grep -F "..."`) leaves matched lines on stdout/stderr, which (a) pollutes test output and obscures real failures, (b) under some bats runners interacts with output capture in surprising ways. Use `-F` (fixed-string) by default; reach for `-E`/`-P` only when phrasing legitimately varies.

The same rule applies to spec-lint contracts asserting a removed clause — `! grep -qF "old wording" "$SPEC"` is the canonical shape. Pair it with a positive `grep -qF "new wording"` test on the same line range to make the replacement contract explicit.

### Multi-assertion `@test`: only the LAST command sets the verdict

A bats `@test` passes **iff its last command exits 0**. Intermediate `[ … ]` / `[[ … ]]` assertions earlier in the body are *advisory* — bats does not abort the test on their failure unless they are chained with `&&`, made the final command, or `bats_require 'bats_assert'`-style helpers are loaded. So a test that asserts several things in sequence silently ignores every assertion except the last:

```bash
# BROKEN: the mode-string assertion is dead — only the RESULT check decides the verdict
@test "post-dedup: re-exports correct" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Post-dedup mode"* ]]   # ← can be false; test still passes
    [[ "$output" == *"RESULT: OK"* ]]         # ← only THIS line sets the verdict
}
```

The failure mode is insidious: a suite reporting **"9 / 11 passing"** can hide additional broken assertions inside the *passing* 9. Any case whose false `[[ … ]]` is not the final command goes green. A reviewer trusting the pass-count — or an automated review that does not even execute bats — ships the latent defect.

**Rules:**

1. **One assertion per `@test`** wherever practical — a failure then pinpoints exactly the broken contract clause (same discipline as spec-lint § Rule 1).
2. When a test must check several conditions, **`&&`-chain them into one command** so every link is load-bearing:
   ```bash
   @test "post-dedup: re-exports correct" {
       run bash "$SCRIPT"
       [ "$status" -eq 0 ] \
         && [[ "$output" == *"Post-dedup mode"* ]] \
         && [[ "$output" == *"RESULT: OK"* ]]
   }
   ```
   (or `load 'bats-assert'` and use `assert_output --partial`, which aborts on the first failure.)
3. **Never trust a bats pass-count alone for the changed surface.** At a verdict gate, read the bodies of the bats tests touching the change and confirm each non-final `[[ … ]]` is actually reachable as a verdict — or re-run after deliberately breaking the asserted condition (RED-proof) to prove the assertion is load-bearing, not vacuous.

Source: a drift-guard suite reported 9/11; the 2 reds were real, but 3 of the "green" cases asserted an output-mode string the script never printed — false-green because the assertion was not the final command, so the latent reached QA. An automated review that did not run bats passed the merge with it.

### Injection-inertness tests: assert a canary side-effect, not just the exit code

When the script under test resolves untrusted input (compose `${VAR}` tokens, a config value, any string an attacker could shape), an injection-attempt regression test MUST assert that the dangerous *side-effect did not happen* — not merely that the script exited non-zero. A script can exit non-zero while still having executed the injected command, and it can also reject the input cleanly with exit 0; the exit code alone proves neither inertness nor rejection. The load-bearing assertion is the absence of a **canary side-effect**.

```bash
@test "injection token does not execute the embedded command" {
    rm -f "$BATS_TEST_TMPDIR/canary"
    # payload embeds: $(touch $BATS_TEST_TMPDIR/canary)
    run run_under_test "$F/inject-fixture"
    [ ! -f "$BATS_TEST_TMPDIR/canary" ]      # PRIMARY: command did not run
    [ "$status" -ne 0 ]                       # SECONDARY: input was rejected
}
```

Pair the canary check with a **battery of distinct injection vectors** — command substitution `$(…)`, backticks, statement chaining `;`, pipes `|`, redirection `>`/`<`, backgrounding `&` — because a guard that blocks one metacharacter often misses another. One `@test` (or a `for`-loop inside one) per vector, each re-arming and re-checking the canary.

Source: a first-draft injection test asserted only `status -ne 0`; the script was already inert but happened to exit 0 with a warning, so the exit-code assertion was simultaneously wrong AND weaker than the real security property. The canary-absence assertion is what actually proves the command never ran.

### Portable latency measurement

`date +%s%N` is not portable — BSD `date` (macOS, and any Bats run on a Mac dev box) does not support the `%N` nanosecond directive and returns the literal string `N` instead of digits, silently corrupting any duration arithmetic built on it.

Prefer a Python one-liner, which is portable across GNU and BSD environments:

```bash
start=$(python3 -c 'import time; print(time.perf_counter())')
# ... operation under test ...
end=$(python3 -c 'import time; print(time.perf_counter())')
elapsed=$(python3 -c "print(${end} - ${start})")
```

Use this in any bats test that asserts a duration bound (timeout regression, performance-floor check) instead of `date +%s%N` subtraction.

Source: deferred from TUNE-0202 Step 0.5 (Class A2).

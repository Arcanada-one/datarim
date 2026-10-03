# Datarim Framework Tests

Framework-internal tests for Datarim components. Runs with [`bats-core`](https://github.com/bats-core/bats-core).

## Current coverage

| Test file | What it verifies | Source task |
|-----------|------------------|-------------|
| `pre-archive-check.bats` | Detection half of the `/dr-archive` clean-git gate: exit codes, multi-repo support, dirty/clean classification, usage errors. 12 tests. | TUNE-0007 (AC-2.1, 2.2, 2.3) |
| `archive-contract-lint.bats` | Spec-regression against `commands/dr-archive.md` — ensures the 3-way prompt (Commit / Accept / Abort) and governance language stay intact. 11 tests. | TUNE-0007 (AC-2.4) |

The two layers are complementary: functional tests prove the **detection script** behaves correctly; spec-lint tests prove the **prose contract** (which Claude Code executes during `/dr-archive`) still carries the required language.

## Install bats-core

```bash
# macOS
brew install bats-core

# Debian / Ubuntu
sudo apt-get install bats

# npm (cross-platform)
npm install -g bats
```

Tested with `Bats 1.13.0`.

## Run tests

From the framework root (`Projects/Datarim/code/datarim/`):

```bash
# all tests
bats tests/

# single file
bats tests/pre-archive-check.bats

# TAP output (useful in CI)
bats --formatter tap tests/
```

## Tmpdir isolation

Every functional test creates its own throwaway git repos inside `BATS_TEST_TMPDIR` (auto-cleaned by bats). No real repo is touched.

## CI integration (optional)

Minimal GitHub Actions workflow:

```yaml
# .github/workflows/tests.yml
name: tests
on: [push, pull_request]
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y bats
      - run: bats tests/
        working-directory: ./
```

Tests are hermetic — no network, no secrets, no external services. Safe for any CI.

## Adding new tests

1. Create `tests/<feature>.bats` with the [bats syntax](https://bats-core.readthedocs.io/).
2. Keep each test under ~20 lines; one assertion cluster per test.
3. Use `BATS_TEST_TMPDIR` for any filesystem state — never touch real paths.
4. Reference the source task ID and acceptance criterion in the test docblock.
5. Run locally before committing: `bats tests/`.

# Contributing

Thanks for your interest in improving this framework.

## Quick Start

```bash
git clone https://github.com/Arcanada-one/datarim.git
cd datarim
./install.sh
```

For a development checkout:

```bash
git clone https://github.com/Arcanada-one/datarim.git
cd datarim
pip install pre-commit
pre-commit install
```

## Workflow

1. **File an issue first** for non-trivial changes. Drive-by patches
   for typos or one-line fixes are welcome without prior issue.
2. **Fork** the repository and create a feature branch.
3. **Run the local security gate** before opening a PR (see below).
4. **Open a PR** against `main` with a clear description and link to
   the issue (if any).
5. **Wait for CI** — all required status checks must pass before
   merge. A code-owner review is required.

## Local Security Gate

Before pushing, run:

```bash
pre-commit run --all-files
bats tests/security/
```

This mirrors the CI baseline. If `pre-commit` is not installed, run
the individual tools:

```bash
shellcheck -S warning $(find . -name '*.sh' -not -path './node_modules/*')
bandit -r . -ll -ii -x ./node_modules
gitleaks detect --redact --no-banner
actionlint
```

## Suppression Discipline

Inline suppressions are allowed but must include a reason of at least
10 characters explaining *why* the rule is suppressed. Without a
reason, the CI suppression-count gate will fail.

Acceptable forms:

```bash
# shellcheck disable=SC2034 # reason: variable read by external sourcing
foo=bar
```

```python
# nosec B608 # reason: query string is a literal constant
db.execute("SELECT 1")
```

Suppressions are reviewed quarterly. Sprawl triggers a security-agent
audit. Do not stockpile suppressions.

## Pull Request Checklist

Before requesting review, confirm:

- [ ] All new code has at least one regression test.
- [ ] `bats tests/` passes locally.
- [ ] `pre-commit run --all-files` passes locally.
- [ ] If the change touches shipped artifacts (`skills/`, `agents/`,
      `commands/`, `templates/`), the corresponding `docs/*.md` index
      and `data/*.php` site entries are updated (see project docs on
      public-surface sync).
- [ ] If the change introduces a new shipped artifact, the
      `dev-tools/doc-fanout-lint.sh` check is green.
- [ ] No internal task IDs, private repo paths, or organization-only
      taxonomy in user-visible files (see public-surface hygiene
      rule).
- [ ] No `StrictHostKeyChecking=no`, `curl | bash`, world-readable
      credentials, or hardcoded secrets in any new code.
- [ ] If the change touches a security-relevant file, a regression
      test in `tests/security/` exists.

## Reporting Security Issues

Do **not** file public GitHub issues for security findings. See
[`SECURITY.md`](SECURITY.md) for the private disclosure channel.

## Code of Conduct

By participating, you agree to abide by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

Contributions are licensed under the [MIT License](LICENSE) — same as
the repository.

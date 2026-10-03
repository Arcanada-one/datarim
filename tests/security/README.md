# Security regression tests

One `.bats` file per closed finding. Each test file:

1. References the original finding (severity, source file, audit date)
2. Reproduces the attack vector (or asserts the unsafe pattern is absent)
3. Asserts the fix prevents exploitation / re-introduction

## Running

    bats tests/security/

Or via runner: `bash tests/security/run-all.sh` (CI-friendly exit codes).

## Adding a new finding test

When a new security finding lands, add `tests/security/finding-N-<slug>.bats` and
re-run the full suite. See `CLAUDE.md` § Security Mandate (rule cluster S9 —
drift, evolution, incident response).

## Counter-example fences

Markdown skills sometimes need to teach an unsafe pattern in order to warn against it.
Wrap such examples in:

    <!-- security:counter-example -->
    # UNSAFE — pedagogical
    ...
    <!-- /security:counter-example -->

Regression tests strip these blocks before scanning, so an explicit, fenced
counter-example is allowed; an unfenced one is not.

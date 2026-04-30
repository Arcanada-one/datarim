---
name: testing/silent-failure-detection
description: Wrappers around CLIs/subprocesses that exit 0 on error and write error sentences to stdout. Parse structured output, raise inside wrapper, test both exit codes.
---

# Silent-Failure Detection (exit 0 + error in stdout)

**Who this applies to:** any wrapper around a subprocess, CLI, or external tool whose *exit code cannot be trusted* because the tool writes error signals into stdout/stderr as normal output. The canonical pattern: an LLM CLI, a build tool, or a shell utility that exits `0` even when it refused or failed the request.

## When the gate is mandatory

The gate **must** fire (structured-output parsing is required, not exit-code inspection) when:

- A subprocess writes human-readable error sentences to stdout/stderr but exits `0` (e.g. quota-exceeded, permission-denied, stale-token, content-filtered — all common in LLM / cloud CLIs).
- A CLI offers both human-text and machine-readable output formats (`--json`, `--output-format stream-json`, `--format=porcelain`) AND the machine format is documented. The machine format is the contract; the text format is for humans and can drift across versions.
- A wrapper returns the tool's stdout to a downstream consumer that treats it as valid payload (review body, generated content, audit record). A silent pass-through poisons downstream state.

## Why returncode-based detection fails

A subprocess returning `0` means "the process ran and did not crash" — NOT "the work was successful." Many modern CLIs deliberately exit `0` on recoverable conditions to match shell-pipeline ergonomics (`cmd && next` chains on success-per-intent, not success-per-attempt). If the wrapper only checks `returncode`, the error message becomes the "result" and flows downstream unlabelled.

Reference incident: a code-review bot where `claude -p` exits `0` when the 5-hour subscription window is exhausted and writes `"You've hit your limit · resets 5pm (UTC)"` to stdout. The old wrapper (`--output-format text` + `returncode != 0` check) treated that as a valid code review, posted it to GitLab as the review body, AND wrote it to `tbl_code_reviews` as a real review round — poisoning the `previous_findings` context used by the next retry. The bug lived in production for weeks.

## What a passing gate looks like

1. **Switch the tool to its machine-readable format** if one exists (`--output-format stream-json`, `--json`, `--format porcelain`). Capture a live fixture during `/dr-plan` (see `commands/dr-plan.md` § Fixture Capture for External Output).
2. **Parse the structured output BEFORE checking the exit code.** A non-zero exit with a structured error event (e.g. `rate_limit_event`) should raise the specific domain error, not a generic "CLI failed" error. Ordering matters: an early `if returncode != 0: raise GenericError` skips the structured parsing entirely. The original wrapper for the reference incident checked exit code first, missing the rate-limit event when the CLI changed from exit 0 to non-zero on limit-hit.
3. **Parse the structured output** for documented error shapes. For `claude -p --output-format stream-json --verbose`, the shape is `rate_limit_event.rate_limit_info.status == "rejected"` with a UNIX-epoch `resetsAt`. Never regex human sentences; structural fields are stable, prose drifts.
4. **Raise at the narrowest layer.** Raise the domain error *inside* the wrapper function (before returning to any caller). Downstream code that treats the return value as trusted never sees an invalid value. Raising one layer up means the intermediate side-effects (history writes, logs, cache updates) still run on the error branch.
5. **Subclass the legacy exception** so existing `except ParentError:` handlers continue to work unchanged. One new branch at the dispatcher; zero refactors elsewhere.
6. **Test both exit-code scenarios** (returncode 0 AND non-zero) with identical structured stdout. Ordering bugs only surface when the non-zero path is exercised. This is a 1-line mock difference but catches an entire class of regressions. The original tests in the reference incident only used `returncode=0`.

## What the gate is NOT

- Not a replacement for unit tests. It's an *additional* check for wrappers around tools that lie via exit code.
- Not required for tools with honest exit codes. `git`, `grep`, `psql` return non-zero on failure — trust them.
- Not a substitute for the Live Smoke-Test Gate. If the change also touches raw SQL or cross-container paths, both gates apply.

## Verdict

- Gate required + structured-output parsing + raise-inside-wrapper → **Layer 4 PASS**.
- Gate required + returncode-only detection → **Layer 4 FAIL**, even if unit tests pass with mocks that pre-return "valid" stdout.

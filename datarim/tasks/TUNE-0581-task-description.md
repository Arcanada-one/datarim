---
id: TUNE-0581
title: Prevent provision-release-env Bats hang on open stdin
status: completed
priority: P1
complexity: L1
type: bugfix
project: Datarim
started: 2026-08-15
parent: null
related: []
prd: null
plan: null
---

## Overview

`tests/provision-release-env.bats` mocks `gh` such that the mock reads stdin whenever stdin is non-TTY, even for read-only GH policy GET calls that pass no request body. When Bats inherits an open non-TTY stdin, the mock blocks waiting for input, and full discovery hits the 600-second per-suite ceiling.

The required fix is test-fixture-only: the mock must read stdin only for calls carrying `--input -`. Production `provision-release-env.sh` behavior must remain unchanged.

## Acceptance Criteria

- [x] AC-1: A deterministic RED test using an open stdin reproduces the blocking behavior in the current fixture before the fix.
- [x] AC-2: After the fix, the `gh` mock reads stdin only when the invocation includes `--input -`.
- [x] AC-3: Read-only GH policy GET calls, which pass no request body, complete without reading stdin and without hanging.
- [x] AC-4: Production `provision-release-env.sh` behavior is preserved.
- [x] AC-5: Verification includes focused Bats, full discovery or shard, bash syntax/shellcheck as applicable, CI, independent review, PR, and merge.

## Constraints

- The fix is limited to test fixtures used by `tests/provision-release-env.bats`.
- No production `provision-release-env.sh` changes are introduced.
- The mock `gh` behavior for invocations with `--input -` remains compatible with existing tests.

## Out of Scope

- Modifying production `provision-release-env.sh`.
- Changing GH API policy or request behavior.
- General non-TTY stdin handling outside the relevant Bats fixture.
- Unrelated discovery or performance changes beyond preventing the hang.

## Related

- Parent incident: none; discovered during the post-merge full-discovery run for PR #379.

## Implementation Notes

- Locate the stdin read path in the `gh` mock and guard it so it runs only when `--input -` is present.
- Ensure mock calls without `--input -` do not read stdin and return immediately.
- Use the deterministic open-stdin RED case first, then apply the fixture-only change and confirm green.
- Validate with focused Bats tests, then full discovery or shard, syntax/shellcheck checks as applicable, CI, independent review, PR, and merge.
- Delivered by PR #380, squash merge `f71490f283c067a796874a27fc5bd307e1ef4003`.
- Evidence: RED regression failed at the bounded timeout; focused Bats 14/14; local discovery shard 7/8 passed 48/48 with zero timeouts; GitHub CI passed all eight shards and all required checks.
- Exact blob verification: merged test blob `fdab7ac0bbd9380b9c29124595a87aad44995490`; production script blob remained `9152319daf670683b5dc8b885a436e67d7b334bb`.

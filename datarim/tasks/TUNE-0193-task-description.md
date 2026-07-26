---
id: TUNE-0193
title: "Fix install.sh symlink idempotency and dry-run guards"
status: in_progress
priority: P3
complexity: L2
type: fix
project: Datarim
started: 2026-07-26
parent: null
related: []
---

## Overview
link_scope_tree function in install.sh:
1. Dangling symlink → still treated as "already linked" → relink silently skipped
2. No DRY_RUN guard → --dry-run flag actually mutates filesystem

## Acceptance Criteria
- [x] Dangling symlink → relinked (not skipped)
- [x] DRY_RUN=true skips all FS mutations
- [x] bats tests: dangling → relinked, real-dir → refuse, dry-run → no mutation

## Implementation Notes

### Root cause
`link_scope_tree` used `cd -P "$dst_dir" && pwd` to resolve the symlink target
for comparison.  For a dangling symlink the `cd -P` can fail in ways that leave
the existing-target check unreliable; using `readlink` (which reads the literal
symlink text without requiring the target to exist) plus an explicit `[ -e
"$dst_dir" ]` dangling guard is more robust.  The function also lacked any
`DRY_RUN` guard, so `--dry-run` would still call `mkdir -p` / `rm` / `ln -s`.

### Changes
- **install.sh `link_scope_tree`** (lines 475–522): replaced `cd -P` + `pwd`
  resolution with `readlink`; added `[ -e "$dst_dir" ]` guard so a dangling
  symlink is always treated as "needs relink"; added `DRY_RUN` pre-check that
  reports planned actions without mutating the filesystem.
- **tests/install.bats** (TUNE-0193-01 through TUNE-0193-04): 4 new bats tests:
  dangling → relinked, real-dir → refuse, dry-run → no mutation, idempotent
  re-run → LINK (already).

### Verification
- All 33 tests in `tests/install.bats` pass (zero regressions).
- `shellcheck -s bash install.sh` — clean on changed lines (only pre-existing
  INFO on unrelated lines).
- Layer 1 floor (`dr-verify-floor.sh`): 0 findings.
- Layer 2 peer review (`agents/peer-reviewer.md`): 6 findings, all triaged:
  - Finding 1 (MEDIUM, consistency): DRY_RUN error return code 0→1 — **fixed**.
  - Finding 2 (MEDIUM, correctness): readlink absolute-path contract comment — **fixed** (added contract documentation).
  - Finding 3 (LOW, test robustness): awk→sed in test helper — **fixed**.
  - Finding 4 (LOW, test coverage): pre-existing, outside TUNE-0193 scope — **deferred**.
  - Finding 5 (INFO, consistency): DRY_RUN error missing >&2 — **fixed**.
  - Finding 6 (INFO, S1 security): clean — no action needed.

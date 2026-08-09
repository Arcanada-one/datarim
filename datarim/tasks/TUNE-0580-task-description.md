---
id: TUNE-0580
title: Return the shared site-repo working tree to a clean state
status: pending
priority: P3
complexity: L1
type: maintenance
project: Datarim
started: 2026-08-09
parent: null
related: [TUNE-0578]
---

## Overview

The shared Mac clone of the site repository (Projects/Websites/datarim.club) carries 15 modified files in its working tree. These files were verified byte-identical to the branch mac-handoff/2026-07-20, so the work is already committed to that branch and nothing is at risk.

Once TUNE-0578 resolves that branch, the Mac working tree should be returned to a clean state by its owner. This task confirms the byte-identity still holds at that time, then has the tree cleaned, leaving git status empty.

## Acceptance Criteria

- [ ] Confirm the 15 working-tree modifications are still byte-identical to mac-handoff/2026-07-20 once TUNE-0578 resolves the branch.
- [ ] Have the owner reset the shared working tree; do not run `git checkout --` or `git stash` on paths you did not modify.
- [ ] `git status` on Projects/Websites/datarim.club is empty.

## Implementation Notes

- This is a shared multi-agent workspace. Never use `git checkout --` or `git stash` on paths you did not modify; the owner resets the tree.
- Coordinate with TUNE-0578; the byte-identity check happens once that task resolves mac-handoff/2026-07-20.
- The work is already committed to mac-handoff/2026-07-20, so no content is at risk; the only remaining action is returning the working tree to a clean state.
- If TUNE-0578 is already resolved when this task starts, the check and cleanup can proceed immediately.
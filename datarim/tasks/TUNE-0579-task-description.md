---
id: TUNE-0579
title: Unblock the two stale-base PRs on the datarim-club-site repo
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

Two pull requests on Arcanada-one/datarim-club-site are MERGEABLE but show site: FAILURE. The failure comes from a stale base, not from their content: their CI ran `npm audit --audit-level=high` against an old lockfile carrying nanoid and postcss high-severity advisories. Current origin/main audits clean (0 vulnerabilities on a clean origin/main worktree), so a rebase should turn both green.

- PR #6 (fix/infra-0368-retarget-dead-runner-label) retargets CI jobs off a dead runner label; contains 1 unlanded line in `.github/workflows/verify.yml`; is 12 commits behind main.
- PR #12 (sec-0034/dependabot-config) adds `.github/dependabot.yml`; contains 9 unlanded lines of 11; is 2 commits behind main.

Both PRs belong to other sessions (SEC-0034 and INFRA-0368), so this task coordinates with them: rebase and re-run CI, merge only what is unambiguously correct, and leave a comment on anything that needs its owner's judgement.

TUNE-0578 also covers these two branches. If TUNE-0578 runs first and resolves them, close this task as already-done rather than duplicating the work.

## Acceptance Criteria

- [ ] PR #6 (fix/infra-0368-retarget-dead-runner-label) is rebased onto current origin/main.
- [ ] PR #6 CI re-runs on the rebased branch and reports success (no site: FAILURE).
- [ ] PR #12 (sec-0034/dependabot-config) is rebased onto current origin/main.
- [ ] PR #12 CI re-runs on the rebased branch and reports success (no site: FAILURE).
- [ ] Only changes that are unambiguously correct are merged; anything needing the owner's judgement has a comment left on the PR.
- [ ] Coordination with the SEC-0034 and INFRA-0368 sessions is reflected in the PR conversation.
- [ ] If TUNE-0578 resolved the branches first, this task is closed as already-done without duplicated work.

## Implementation Notes

- Root cause of the CI failure is the stale base: the PR branches' CI ran `npm audit --audit-level=high` against an old lockfile with nanoid and postcss high-severity advisories; the current origin/main worktree audits clean (0 vulnerabilities).
- Rebase each PR onto current origin/main and re-run CI; a rebase should turn both green.
- PR #6 is 12 commits behind main and carries 1 unlanded line in `.github/workflows/verify.yml`.
- PR #12 is 2 commits behind main and carries 9 unlanded lines of 11, adding `.github/dependabot.yml`.
- Coordinate with the owning sessions (SEC-0034 for PR #12, INFRA-0368 for PR #6) before merging; merge only what is unambiguously correct and leave a comment on anything requiring the owner's judgement.
- Check TUNE-0578 status first: it also covers these two branches. If it has already resolved them, close this task as already-done.
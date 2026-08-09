---
id: TUNE-0578
title: Retire every remaining branch on the datarim-club-site repo
status: pending
priority: P2
complexity: L3
type: maintenance
project: Datarim
started: 2026-08-09
parent: null
related: [TUNE-0574, TUNE-0575, TUNE-0576, TUNE-0577]
---

## Overview

Retire every remaining branch on the site repo `Arcanada-one/datarim-club-site` so it ends with exactly one branch (`main`), zero open pull requests, and a clean working tree — with no work lost and no regression merged. `main` is currently healthy: 26 pages (13 × EN/RU) all HTTP 200, counters 19/28/69 matching the shipped catalogues, zero task IDs rendered, `npm audit` clean (0 vulnerabilities) on a clean `origin/main` worktree, and the deploy workflow green.

Six branches remain. Each must be resolved by the decision rule below, working autonomously: decide every fork, record the reasoning in the task artefacts, and do not ask questions. One archive document must record, per branch, the outcome and the evidence.

## Measured state

State measured 2026-08-09; re-verify before acting. Per branch, `base = git merge-base origin/main origin/<branch>`, then each added line is checked with `git grep -Fq "$line" origin/main` to determine how many added lines are unlanded vs. already on main.

| Branch | unlanded/total added lines | behind main | files |
|---|---|---|---|
| `fix/infra-0368-retarget-dead-runner-label` | 1/1 | 12 | `.github/workflows/verify.yml` |
| `sec-0034/dependabot-config` (PR #12) | 9/11 | 2 | `.github/dependabot.yml` |
| `sec-0034-dependabot-config` (no PR) | 28/30 | 2 | `.github/dependabot.yml` |
| `sweep/TUNE-0352-about-localization` | 51/51 | 21 | `content/en.php`, `content/ru.php`, `pages/about.php` |
| `tune-r5-site` | 8/73 | 5 | `config.php`, `content/{en,ru}.php`, `data/agents/optimizer.php`, `data/commands/dr-optimize.php`, `data/skills/context-window-self-clearing.php`, `pages/about.php`, `pages/changelog.php` |
| `mac-handoff/2026-07-20` | 116/249 | 14 | 15 files incl. `.gitignore`, `config.php`, `content/{en,ru}.php`, several `data/**`, `pages/{about,changelog,features,docs/index}.php` |

Two open PRs remain: **#12** (`sec-0034/dependabot-config`) and **#6** (`fix/infra-0368-retarget-dead-runner-label`). Both are `MERGEABLE` but report `site: FAILURE`. The failure is a stale base, not their content: their CI ran `npm audit --audit-level=high` against an old lockfile that still had `nanoid`/`postcss` high-severity advisories, while current `origin/main` audits clean. Rebase (or the `@dependabot rebase`-equivalent: push a rebased branch) should turn them green. Verify this claim before relying on it.

The shared Mac clone has 15 modified files, verified byte-identical to `mac-handoff/2026-07-20`; that work is already committed to the branch and nothing is at risk. The Mac clone must not be touched — all work happens on the execution host from a fresh clone.

## Acceptance Criteria

- [ ] `git branch -r` on the site repo shows only `origin/main`.
- [ ] Zero open PRs; anything deliberately not merged has a closed PR with a written reason.
- [ ] Live site verified green after the final merge:
  - [ ] all 26 routes (13 × EN/RU) return HTTP 200 with non-thin bodies, fetched with a real browser User-Agent (a default-UA request can return empty and read as a broken site);
  - [ ] counters 19/28/69 still match the shipped catalogues;
  - [ ] no task IDs render in page text.
- [ ] `npm ci && npm test` (runs `tests/site-contract.sh`) green on each PR.
- [ ] `npm audit --audit-level=high` clean.
- [ ] `php -l` clean on every changed `.php`.
- [ ] One archive document records, per branch, the outcome and the evidence.
- [ ] No work lost and no regression merged.

## Implementation Notes

Decision rule per branch, applied to the evidence (the table above may be stale by the time of execution):

1. **0 unlanded lines** → the work is already on main under a squash commit; delete the branch.
2. **Unlanded lines that are real improvements** → rebase onto current `main`, run the tests and gates, open a PR, merge, then delete the branch.
3. **Unlanded lines that would REGRESS main** → do not merge; delete the branch and record in the archive exactly what it would have removed. Precedent: `fix/content-0061-telegram-contract` was deleted because merging it would have stripped Telegram recipes main still carries (786 → 743 lines).
4. **Genuinely ambiguous / operator-judgement content** → land what is safe and leave a precise follow-up backlog entry for the rest, rather than guessing.

Branch-specific notes:

- **Dependabot configs.** `sec-0034/dependabot-config` (11 lines, PR #12) and `sec-0034-dependabot-config` (30 lines, no PR) both write `.github/dependabot.yml`; they differ by 4 insertions / 23 deletions. Pick ONE on the merits (broader ecosystem coverage, correct schedule/labels, matches how the framework repo's own dependabot config is written), land it, delete the other. Do not land both — the second would overwrite the first.
- **`mac-handoff/2026-07-20`.** 116 unlanded lines, 14 behind `main`; a July WIP snapshot, parts of which have since landed by other routes. Land only what is still a genuine improvement over current `main`, file-by-file. Two hazards: (a) it modifies `.gitignore` in a way that REMOVES `node_modules/` and `vendor/` exclusions — a regression, do not take it; (b) its framework-repo twin leaked an operator name into a public artefact — run the personal-data gate on anything you land.
- **`sweep/TUNE-0352-about-localization`.** 51/51 unlanded, 21 behind; RU localisation of `pages/about.php`. Check whether `main`'s `about.php` has since been rewritten; if so, port the localisation rather than merging a stale page.
- **`tune-r5-site`.** Only 8/73 unlanded; most already landed. Identify the 8 and decide.

Process constraints:

- Clone fresh on the execution host; do not use the shared Mac clone (it is a shared workspace with foreign uncommitted changes) and do not touch it.
- Branch + PR workflow; rebase on `origin/main` immediately before every merge; never force-push or rebase shared `main`.
- Push the branch — a local commit is not durability.
- Deploy is push → main → CI only; never edit files on the server.
- Commit as `Arcanada <dev@veritasarcana.ai>`, never under a personal identity.
- The repo is public: no operator names, home paths, hostnames, IPs, or credentials in any artefact.
- Beware gates that print usage and exit 0 (false PASS) and `RC=$?` after a pipe (captures the last pipeline element); confirm each gate with a positive control.
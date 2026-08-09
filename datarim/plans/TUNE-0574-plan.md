# TUNE-0574 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `subagent-driven-development` or `executing-plans` to implement this plan.

## Goal

Make Critical Rule #8 mechanically true across the public framework, public documentation, public site, release, and three installed runtimes. Preserve illustrative task-ID examples only inside narrow, structurally valid hatches, and keep all task provenance in the evolution log, archive, and Git history.

## Architecture

Keep `scripts/task-id-gate.sh` as a one-target Bash CLI. Replace its blind hatch stripping with one embedded POSIX-awk state machine so line numbering, malformed-marker reporting, portable task-ID boundaries, and provenance-label rejection share one scan. Directory mode walks only the contract's five text extensions with NUL-delimited paths. Exact canonical repository-relative comparisons implement the two default exemptions. CI explicitly invokes each governed root. The site maintains a separate no-hatch, prefix-agnostic rule.

## Tech Stack

Bash 3.2-compatible shell, POSIX awk, Bats, Git/GitHub CLI, the existing release workflow, the site shell contract suite, and the existing fleet sync procedure documented in `documentation/how-to/fleet-hook-sync.md`.

## Autonomous decisions

- Use an embedded awk program instead of a second parser file. The policy is small enough to review in one place and the existing gate already owns scan-stream construction and reporting.
- Use `missing read targets fail closed` as the permanent hook probe. It describes the invariant rather than its historical origin.
- Keep the brief's exact five directory extensions. The task is a contract repair, not an unbounded binary/text classifier. Regression tests cover every listed extension and every governed caller.
- Make malformed hatch syntax fail independently of whether an ID is present. Otherwise an unmatched opener can suppress all later violations.
- Check provenance labels before suppressing valid hatch content, including Markdown decoration, case variants, and a label whose ID is on the next nonblank line.
- Compare exemptions by exact canonical repository-relative path. Suffix matching would let an attacker create a spoofed path.
- Validate `--diff-only` base refs once and scan untracked directory files in full-file mode. Git errors must return 2; they must never become a clean result.
- Preserve both existing dirty root workspaces. Framework work stays in `/home/dev/tune-0574`; site work stays in `/home/dev/.worktrees/datarim-club-site/tune-0574`.
- Bump to `2.65.0`: broadening a public enforcement contract is a backward-compatible feature, so a minor release is appropriate.

## Task 1: Extend the regression suite and capture RED

**Files**

- Modify: `tests/task-id-gate.bats`
- Modify/add only narrowly needed files under `tests/fixtures/task-id-gate/`

**RED tests**

1. Allow `GATE` to be overridden by `TASK_ID_GATE_OVERRIDE`.
2. Add independent cases for `.md`, `.template`, `.sh`, `.yaml`, and `.yml` directory discovery.
3. Add a balanced unlabeled illustrative hatch PASS.
4. Add FAIL cases for same-line open+close, opener with payload, closer with payload, unmatched opener, unmatched closer, nested markers, and a real ID after an unmatched opener. Replace the current vacuous same-line test.
5. Add FAIL cases for `Source`, `Source task`, `Reference`, `Created`, and `Parent epic` in plain/YAML/Markdown/case-varied forms, including label and ID split across lines.
6. Add portable boundary controls: ordinary IDs fail; adjacent letters, digits, or underscore do not create a false match.
7. Add exact-whitelist and suffix-spoof tests.
8. Add directory-mode tests for invalid diff base (2), untracked contaminating file (1), and exclusions anchored only to the intended repo-relative fixture, dependency, and Git metadata roots.
9. Add clean-scope tests for all ten CI targets and a wiring assertion against `.github/workflows/security.yml`.

Run the new suite before production changes:

```bash
bats tests/task-id-gate.bats
```

Expected: nonzero with failures proving the current gate and CI wiring do not satisfy the new contract. Record the exact output in the task evidence.

Then copy the old gate into a temporary isolated fixture and rerun the behavior-only cases:

```bash
old_gate_dir="$(mktemp -d)"
git show origin/main:scripts/task-id-gate.sh > "$old_gate_dir/task-id-gate.sh"
chmod +x "$old_gate_dir/task-id-gate.sh"
TASK_ID_GATE_OVERRIDE="$old_gate_dir/task-id-gate.sh" bats tests/task-id-gate.bats
```

Expected: exit 1. Do not stash, reset, or touch either foreign dirty workspace.

**Verifies:** V-AC-1, V-AC-3, V-AC-4, V-AC-7.

## Task 2: Implement the fail-closed gate

**Files**

- Modify: `scripts/task-id-gate.sh`

Implement:

1. Portable task-ID extraction without `grep -E '\b'` or GNU-only `grep -P`.
2. Marker-only, balanced hatch state with explicit malformed records for nesting, stray close, marker payload, and EOF while open.
3. Provenance-label recognition after case/Markdown-prefix normalization, with same-line and next-nonblank-line binding.
4. NUL-delimited directory traversal for exactly `.md`, `.template`, `.sh`, `.yaml`, `.yml`.
5. Exact canonical repo-relative default exemptions for `skills/evolution/history-agnostic-gate.md` and `documentation/how-to/evolution-log.md`.
6. Fail-closed input handling: reject unreadable/special governed inputs; validate the diff base; distinguish untracked files from Git errors; scan untracked directory files in full.
7. Preserve the one-target CLI and exit contract 0 clean, 1 policy finding, 2 invocation/scanner error.

Run:

```bash
bats tests/task-id-gate.bats
shellcheck --severity=warning scripts/task-id-gate.sh
```

Expected: behavior tests green except clean-scope tests that are still RED because corpus cleanup and CI wiring have not landed.

**Verifies:** V-AC-1, V-AC-2, V-AC-3, V-AC-4.

## Task 3: Expand CI callers and align the contract

**Files**

- Modify: `.github/workflows/security.yml`
- Modify: `skills/evolution/history-agnostic-gate.md`
- Modify: `CLAUDE.md`

Change the CI job to call the one-target CLI once for each of:

```text
skills
agents
commands
templates
documentation/how-to
documentation/reference
documentation/explanation
documentation/tutorials
CLAUDE.md
README.md
```

Align Rule #8 and the gate contract with the five extensions, exact exclusions, exact exemptions, fail-closed hatch grammar, provenance-label ban, and directory diff behavior. Remove historical IDs from explanatory prose.

Run the wiring tests. Add one temporary novel-ID file under a governed documentation root, prove the CI-equivalent loop fails, remove it, and continue.

**Verifies:** V-AC-1, V-AC-6, V-AC-7.

## Task 4: Classify and clean the full governed corpus

**Files**

- Modify every classified real-provenance file found by the raw inventory in the ten governed targets.
- Modify: `documentation/how-to/evolution-log.md`
- Modify: `dev-tools/coworker-hook-guard.sh`
- Modify: `documentation/how-to/fleet-hook-sync.md`

For every raw task-ID-shaped hit:

- Preserve an actual rendered example only inside the narrow valid hatch.
- Remove real task provenance while retaining the load-bearing rule, date, version, or rationale.
- Remove dead links to gitignored task descriptions and replace them with stable shipped references where useful.
- Record displaced historical provenance once in the evolution log, including this task and the eventual framework PR.
- Replace the hook's historical comment and the fleet functional probe with `missing read targets fail closed`.

Run a raw inventory over exactly the governed scopes and manually classify every survivor. Then run the gate loop; all ten targets must return 0.

**Verifies:** V-AC-2, V-AC-4, V-AC-5, V-AC-6.

## Task 5: Harden the separate public-site contract

**Worktree**

- `/home/dev/.worktrees/datarim-club-site/tune-0574`

**Files**

- Modify: `tests/site-contract.sh`

Add a self-contained control that proves a novel prefix such as `NOVEL-1234` is rejected and adjacent non-ID shapes are accepted. Replace the closed prefix alternation with the same portable generic two-to-ten-uppercase-letter/four-digit boundary semantics. The site has no hatch.

Run before the regex change to capture RED, then after the change:

```bash
bash tests/site-contract.sh
```

Expected after implementation: exit 0 on the clean site, with the embedded contaminating control demonstrating rejection. Commit and push the site branch, open a protected PR, wait for exact-head green CI, merge, then wait for the push-to-main deployment workflow and verify its resulting-main SHA.

**Verifies:** V-AC-8.

## Task 6: Version and local verification

**Files**

- Modify: `VERSION`
- Modify: `CHANGELOG.md`

Set `VERSION` to `2.65.0`. Add a dated changelog entry for widened scope, hatch hardening, provenance cleanup, semantic fleet probe, site parity, and regression tests.

Run positive controls first for each gate, restoring temporary changes immediately, then the clean commands:

```bash
bats tests/ dev-tools/tests/
scripts/task-id-gate.sh skills
scripts/task-id-gate.sh agents
scripts/task-id-gate.sh commands
scripts/task-id-gate.sh templates
scripts/task-id-gate.sh documentation/how-to
scripts/task-id-gate.sh documentation/reference
scripts/task-id-gate.sh documentation/explanation
scripts/task-id-gate.sh documentation/tutorials
scripts/task-id-gate.sh CLAUDE.md
scripts/task-id-gate.sh README.md
dev-tools/check-body-english.sh --scope skills
scripts/check-doc-refs.sh
scripts/stack-agnostic-gate.sh
```

Also run the repo's existing release preflight and any tests named by changed callers. Capture command, exit code, and output artifact for each proof.

**Verifies:** V-AC-1, V-AC-2, V-AC-8, V-AC-9.

## Task 7: Independent QA and compliance

Run the Datarim QA and compliance checklists from a clean-context reviewer. Because this task changes framework policy, the independent compliance check is mandatory. Resolve all high/medium findings, rerun affected tests, and produce the task QA/compliance/reflection artefacts. Verify the operator expectations checklist item by item; do not convert missing live proof to PASS.

**Verifies:** all V-ACs before delivery.

## Task 8: Protected framework delivery and exact-main proof

Fetch `origin/main`, rebase the branch, rerun proportionate tests on the rebased exact SHA, push, open the framework PR, and wait for terminal-success required checks for that SHA. Do not self-approve or bypass protection. Merge only after gates allow it. Fetch resulting `origin/main` and prove the owned blobs, `VERSION`, and release state landed even if unrelated concurrent commits also landed.

**Verifies:** V-AC-7, V-AC-8, V-AC-9.

## Task 9: Publish release `v2.65.0`

Create the release tag from the verified resulting-main commit using the repository's established release workflow, push it, wait for exact-tag CI, and publish the GitHub Release. Verify tag target, release URL, assets/checksums/signatures/attestations required by the existing workflow, and the public version readback.

**Verifies:** V-AC-9.

## Task 10: Sync and verify the three-machine fleet

After release, follow the current commands in `documentation/how-to/fleet-hook-sync.md`; do not invent a sync command. Update `/opt/datarim` and each per-user runtime on arcana-devs, dev-ai, and aether. Never touch `/home/aether/code/aether/local-env/datarim`.

On every machine capture:

- canonical checkout/ref and exact release/main SHA;
- per-user runtime drift/readback from the documented fleet procedure;
- the widened task-ID gate result where the installed layout supports it;
- `grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard`;
- exact exit codes and output, with private host details redacted from public artefacts.

All three machines must prove the same released content. Any mismatch remains BLOCKED until repaired and re-read.

**Verifies:** V-AC-5.

## Task 11: Archive only after every proof layer is complete

Append final evidence and autonomous fork rationales to the init-task log. Write reflection, QA/compliance reports, and the public archive without private paths, hostnames, IPs, names, or secrets. Reconcile `datarim/tasks.md`, `datarim/activeContext.md`, and the backlog. Archive only when framework merge, site merge/deploy, release, and all fleet readbacks are independently proven.

**Verifies:** Definition of Done.

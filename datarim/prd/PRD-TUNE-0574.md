---
id: PRD-TUNE-0574
title: Close task-ID provenance leaks – PRD
status: approved
version: 1.0
created: 2026-08-09
author: Arcanada <dev@veritasarcana.ai>
---

# PRD-TUNE-0574 — Task-ID provenance leak: close the mechanism gaps (repo + site + fleet)

## Context

Datarim Critical Rule #8 forbids task‑IDs in shipped instruction artefacts (`skills/`, `agents/`, `commands/`, `templates/`).
Provenance belongs in `documentation/how-to/evolution-log.md`, `documentation/archive/`, and Git history.

The current enforcement gate (`scripts/task-id-gate.sh`) reports a clean pass on its four directory callers, yet the trees contain 90 task‑ID‑shaped occurrences. Some are legitimate illustrative placeholders; the rest are real provenance stamps that breach the rule.
Three independent mechanism gaps allow these stamps to escape:

1. **Escape hatch abuse** – `<!-- gate:history-allowed --> … <!-- /gate:history-allowed -->` markers wrap genuine `Source:`, `Reference:`, `Created:` lines that name real past tasks.
2. **File‑type coverage** – the gate walks only `.md` files, missing `.sh`, `.template`, `.yaml`/`.yml` files.
3. **Scope gap** – `documentation/{how-to,reference,explanation,tutorials}` and root `CLAUDE.md` / `README.md` are not scanned, leaving dead provenance links that point to non‑shipped (gitignored) task descriptions.

Additionally, the installed runtime and the public website (`datarim.club`) must stay consistent with the repo after the changes.

## Problem

The documented rule says “no task‑IDs in shipped artefacts”, but the enforcement machinery silently excludes an entire class of violations. Agents reading the instructions encounter ephemeral identifiers that distract, may leak into AI output, and couple runtime rules to historical task numbers. The inconsistency between the rule and the gate erodes trust and makes it impossible to verify compliance automatically.

## Goals

- Close the three mechanism gaps so the gate reports violations accurately.
- Remove every real provenance stamp while preserving legitimate illustrative IDs.
- Strengthen the escape hatch discipline so it cannot launder real provenance.
- Align the gate contract document, `CLAUDE.md` Rule #8, and the actual enforcement.
- Provide tests with negative controls (pre‑fix RED) that prove the fixes work.
- Maintain full CI suite green, site contract, and fleet consistency.
- Release the change with proper versioning.

## Non-Goals

- Changing historical records in `documentation/archive/` or test fixtures. `CHANGELOG.md` and the evolution log change only for the release entry and this task's designated provenance record.
- Touching Aether’s gated fork, dependabot PRs, or unrelated salvage directories.
- Rewriting the gate in a different language; the design stays a shell‑based gate with POSIX utilities.

## Solution Approaches

### Approach A — Extend the existing gate with a hatch‑aware POSIX‑awk state machine (selected)

- Keep the single‑target CLI interface (`./scripts/task-id-gate.sh <path>`) and the existing per‑file reporting.
- Extend the directory walk to include `.sh`, `.template`, `.yaml`, `.yml` files.
- Replace the current blind hatch stripping with a balanced POSIX‑awk state machine that:
  - Accepts hatch markers only on their own lines (no same‑line content).
  - Rejects nested, stray, or unclosed markers.
  - Detects task‑IDs with portable lexical-boundary logic (not `\b`) and suppresses them only inside a structurally valid illustrative hatch.
  - Rejects lines inside a hatch that bind the provenance labels `Source`, `Source task`, `Reference`, `Created`, or `Parent epic` to an ID, including a label followed by an ID on a continuation line.
- Expand CI callers to explicitly scan `skills`, `agents`, `commands`, `templates`, `documentation/how-to`, `documentation/reference`, `documentation/explanation`, `documentation/tutorials`, root `CLAUDE.md` and `README.md`.
- Exact exemptions: the gate contract file itself and `documentation/how-to/evolution-log.md`; `archive/`, `changelog`, `tests/`, `.datarim/` remain outside the callers.
- Replace the historical task‑ID used as a functional grep in `fleet-hook-sync.md` and the deployed hook with the stable semantic marker `missing read targets fail closed`.
- Demand negative‑control tests that fail against the pre‑fix state, then pass after the fix.

**Trade‑offs**:
- + Incremental, leverages existing shell infrastructure; CI pipeline changes are minimal.
- + POSIX‑awk state machine is deterministic, no external dependencies.
- - More complex than a simple grep‑based check; careful review required to avoid false positives.
- - Whichever semantic marker we choose must be coordinated across the hook and the doc; a deployment‑time verification is mandatory.

### Approach B — Replace the gate with a Python linter

- Write a custom Python tool that walks the tree, understands Markdown comment syntax, and has robust ID detection.
- Advantages: easier to express complex hatch rules, built‑in Unicode support.
- Disadvantages: introduces a Python dependency into the CI toolchain, increases maintenance surface, and requires rewriting all existing gate logic and tests; the project already has a strong bats/shell‑based dev‑tool environment.

### Approach C — Manual audit only (no gate change)

- Rely on a one‑off sweep by an operator, without changing the gate.
- Disadvantages: repeats the same cycle of drift; human‑only enforcement cannot scale across a fleet or automated PR checks. Not acceptable for a public repository with high change velocity.

## Selected Architecture

**Approach A** with the following concrete design choices (derived from the task brief and decisions record):

- **One‑target CLI** unchanged.
- **Directory scan file types**: exactly `.md`, `.template`, `.sh`, `.yaml`, `.yml`.
- **CI invocation** explicitly enumerates `skills agents commands templates documentation/how-to documentation/reference documentation/explanation documentation/tutorials CLAUDE.md README.md`.
- **Exact gate exemptions**: the gate contract file (`skills/evolution/history-agnostic-gate.md`) and `documentation/how-to/evolution-log.md`; `documentation/archive/`, `CHANGELOG.md`, `tests/`, `.datarim/` are outside the scanned set.
- **Hatch parser**: POSIX‑awk state machine enforcing marker‑only lines, balanced open/close, no nesting.
- **ID detection inside hatch**: uses POSIX lexical-boundary checks around `[A-Z]{2,10}-[0-9]{4}` (no `\b` reliance). A valid hatch is a syntactic exemption for a reviewed illustrative block; the gate does not pretend it can infer whether an arbitrary token is historically real.
- **Provenance label rejection**: a line within an open hatch that binds `Source`, `Source task`, `Reference`, `Created`, or `Parent epic` to an ID on the same or continuation line causes the file to fail. Markdown decoration and label case do not bypass the check.
- **Fleet functional marker**: the grep command in `fleet-hook-sync.md` and the marker string embedded in the deployed hook are changed to `missing read targets fail closed`; the documented grep must match exactly.
- **Pre‑fix RED controls**: new or modified bats tests are executed in an isolated fixture against the gate and caller wiring read from `origin/main` and must return `rc=1`; post‑fix they return `rc=0`. No stash or foreign-worktree mutation is permitted. The failing output is recorded in the PR.
- **Release process**: VERSION bump, CHANGELOG entry, git tag, GitHub Release.
- **Fleet readback**: after merge, the installed runtime on arcana‑devs, dev‑ai, and aether is synchronised and drift gates re‑run, producing identical SHA or content verification; exact‑main proof (no divergent changes on `origin/main` at merge time).

## Requirements

#### D-REQ-01: Gate walk and CI callers match the enforced scope

The gate must accept the following directory/file arguments and exit 0 when all are clean:

```bash
for target in skills agents commands templates \
  documentation/how-to documentation/reference documentation/explanation documentation/tutorials \
  CLAUDE.md README.md; do
  scripts/task-id-gate.sh "$target"
done
```

The directory walk inside the gate must inspect files ending with `.md`, `.sh`, `.template`, `.yaml`, `.yml`.
`documentation/archive/`, `CHANGELOG.md`, `tests/`, `.datarim/` are not passed to the gate and are not expected to pass.

#### D-REQ-02: Balanced hatch state machine

The hatch parser is implemented as a POSIX‑awk state machine (inside `scripts/task-id-gate.sh` or a sourced library). It enforces:

- Start marker `<!-- gate:history-allowed -->` must appear on a line by itself (no non‑whitespace content before or after).
- End marker `<!-- /gate:history-allowed -->` likewise, and must be the matching close for the currently open hatch.
- Nesting of start/end markers is rejected.
- Stray end marker or unclosed hatch at EOF is rejected.

Any violation of these rules is independently reportable and causes the gate to exit 1, even when no task ID occurs on the malformed marker line.

#### D-REQ-03: Provenance label rejection inside a valid hatch

While the hatch is open, the parser must look for lines that match the pattern:

```
^\s*(Source|Source task|Reference|Created|Parent epic)\b
```

If such a line binds on the same or next continuation line to a token matching `[A-Z]{2,10}-[0-9]{4}`, the file fails. The check must handle common Markdown decoration and label case variants.

#### D-REQ-04: Illustrative ID preservation and exact path exemptions

Task-ID tokens inside a structurally valid hatch are ignored only after the hatch passes the provenance-label rule. Existing reviewed rendered examples remain byte-stable except where their markers must be normalized onto marker-only lines.

Path exemptions use exact canonical repository-relative equality. A path that merely ends with an exempt path is not exempt. The contract file and evolution log are the only default exemptions.

#### D-REQ-05: Semantic fleet marker replacement

The functional grep in `documentation/how-to/fleet-hook-sync.md` is changed from a historical task‑ID to the stable semantic string `missing read targets fail closed`. The corresponding marker in the canonical and installed coworker hook guard on all three machines is updated to the same string. The documented grep command must succeed against the installed hook on each machine after deployment.

The exact fleet probe is `grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard`, executed as part of fleet readback.

#### D-REQ-06: Contract documentation alignment

- `skills/evolution/history-agnostic-gate.md` (the gate’s contract) is updated to reflect:
  - The exact set of file types scanned.
  - The hatch rules (marker‑only lines, rejection of provenance labels, and narrow illustrative blocks).
  - The scope of CI callers and explicit exemptions.
- `CLAUDE.md` Rule #8 is amended so that the prose describes the enforced scope identically to what the gate enforces (no contradiction).

#### D-REQ-07: Pre-fix negative control tests

For every new or changed gate behaviour, a bats test exists that:

1. When executed in an isolated fixture against gate/caller content read from `origin/main`, exits with `rc=1`.
2. After the fix is applied, exits with `rc=0`.

The output of the failing run (the RED state) is captured and pasted into the PR body.

#### D-REQ-08: Full CI suite green

The following gates pass with `rc=0`, each verified with a positive control before acceptance:

- `scripts/task-id-gate.sh` on all expanded scopes.
- `dev-tools/check-body-english.sh --scope skills`
- `scripts/check-doc-refs.sh`
- `scripts/stack-agnostic-gate.sh`

Additionally, `bats tests/` and `dev-tools/tests/` return `0`.

#### D-REQ-09: Site contract and protection

- `tests/site-contract.sh` must pass (no new failures attributable to this task).
- If any site page renders content derived from files changed in this task, that page is updated accordingly. The site-side rule is made prefix-agnostic rather than relying on a closed list of known prefixes. The site has no hatch contract: task-ID-shaped tokens are forbidden outright. A novel-prefix contaminating control must fail and an adjacent non-ID shape must pass.
- Deployment is push→main→CI only.

#### D-REQ-10: Release artefacts

- `VERSION` is bumped from `2.64.0` to `2.65.0` because the release broadens an enforced public contract.
- `CHANGELOG.md` gets an entry describing the gate expansion, hatch hardening, and semantic marker change.
- Git tag `v2.65.0` is created and pushed.
- A GitHub Release is published with release notes summarising the changes.

#### D-REQ-11: Fleet readback with exact-main proof

After the PR is merged and the release cut, on each of the three machines (arcana‑devs, dev‑ai, aether):

1. The canonical checkout at `/opt/datarim` and the per-user installed runtime are updated through the existing fleet sync procedure, preserving local configuration outside the repo.
2. Drift gates are re‑run, confirming that the repo content and the installed files are byte‑identical for all shipped artefacts.
3. The semantic marker probe (`grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard`) succeeds, demonstrating the marker switch is consistent.
4. The operator reports the exact command output for each machine, not a claim.

After merge, fetch `origin/main` and prove the resulting main tree carries the owned blobs plus the release/version state. Concurrent unrelated main commits do not invalidate this proof; stale pre-rebase or PR-head evidence does.

## Security and Failure Modes

- **False positives due to hatch edge cases**: the awk state machine must be robust against files that contain HTML comments used for other reasons. Mitigation: test against real corpus.
- **Semantic ambiguity inside hatches**: syntax cannot distinguish a real historical ID from a plausible placeholder. The mechanical label ban is defense in depth; reviewers must still classify every newly hatched ID as illustrative.
- **Marker spoofing**: an attacker could craft a line that looks like a hatch marker but with extra whitespace. The gate enforces strict marker‑only lines – any deviation fails the file.
- **Shell escaping**: file paths with spaces or special characters are not normally present in Datarim; the gate uses `find -print0` and `xargs -0` where feasible.

## Release / Site / Fleet Requirements

- Version bump, changelog, tag, GitHub Release (see D-REQ-10).
- Site content update if affected (D-REQ-9).
- Fleet synchronisation with drift gate verification (D-REQ-11).
- All three machines must show identical gate results and marker checks.

## V-AC success criteria

### V-AC-1 — Gate passes expanded scopes with new file types

Covers: D-REQ-01, D-REQ-08

**What to verify**
Run the D-REQ-1 loop so each canonical target is passed to the one-target CLI separately, and confirm every invocation exits 0.

**How to verify (success criterion)**
- The command returns 0.
- The output reports `PASS` with no violations; illustrative IDs remain suppressed only by valid narrow hatches.
- The gate walked `.sh`, `.template`, `.yaml`, `.yml` files, proven by examining verbose output or a separate test.

### V-AC-2 — Zero real provenance stamps

Covers: D-REQ-02, D-REQ-03, D-REQ-04

**What to verify**
Post‑fix, no file in the scanned set contains a real task‑ID unless inside an allowed illustrative context.

**How to verify**
- A raw inventory over exactly the canonical scopes is classified: every remaining ID is inside a narrow illustrative hatch, while the gate reports no violation. The inventory excludes the evolution log and archive history.
- The gate’s negative test demonstrates that a file with a real provenance stamp inside a hatch is rejected.

### V-AC-3 — Hatch discipline rejects provenance labels

Covers: D-REQ-03

**What to verify**
The gate rejects a line like `Source: TUNE-0280` (or multi‑line forms) even when wrapped in a valid hatch.

**How to verify**
- A bats test inserts such a line into a temporary file with balanced hatch markers; the gate must return non‑zero.
- A separate balanced hatch containing an unlabeled illustrative ID is allowed; a provenance-labelled ID is rejected regardless of whether the token looks like a placeholder.

### V-AC-4 — Illustrative IDs survive

Covers: D-REQ-04

**What to verify**
Files that currently use legitimate illustrative placeholders (`TASK-0001`, `ARCA-0001`, etc.) continue to pass the gate.

**How to verify**
- Compare the list of files that previously passed the gate (with hatch) before the fix; after the fix they still pass.
- Path exemptions are exact, and a suffix-spoofed path does not inherit either exemption.

### V-AC-5 — Semantic fleet marker works on all machines

Covers: D-REQ-05, D-REQ-11

**What to verify**
On each machine, `grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard` returns the expected line, and the documented grep in `fleet-hook-sync.md` is byte-for-byte the same command.

**How to verify**
- Execute the exact grep from the updated doc on arcana‑devs, dev‑ai, aether; all return a line containing the marker.
- The pre‑fix state would fail to find that marker.

### V-AC-6 — Contract docs match enforcement

Covers: D-REQ-06

**What to verify**
`skills/evolution/history-agnostic-gate.md` and `CLAUDE.md` describe the enforced scopes, file types, and hatch rules without contradiction.

**How to verify**
- Manual review: the doc lists the same directories and file extensions as the CI caller script.
- The hatch rule described in the doc (marker‑only lines, provenance label rejection) matches the awk state machine’s logic.

### V-AC-7 — Pre-fix negative controls produce RED

Covers: D-REQ-07

**What to verify**
Each new or changed bats test fails when run against the pre‑fix codebase.

**How to verify**
- In the PR, paste the output of the bats run against the isolated `origin/main` gate fixture, showing exit code 1 with a meaningful error.
- After applying the fix, the same tests pass (exit 0).

### V-AC-8 — Site contract remains green; if any page changed, it is deployed

Covers: D-REQ-09

**What to verify**
`tests/site-contract.sh` exits 0. No new task‑IDs appear in the site’s content.

**How to verify**
- Run the site contract test in the isolated local site worktree and again through the deployment workflow.
- If any documentation page was altered (e.g., wording removal), confirm the site renders correctly and the corresponding source was updated in the site repo.

### V-AC-9 — Release artefacts published

Covers: D-REQ-10

**What to verify**
`VERSION` is incremented, `CHANGELOG.md` has an entry, a Git tag exists, and a GitHub Release is present.

**How to verify**
- Check `cat VERSION` shows the new version.
- `git tag -l 'v2.*'` includes the new tag.
- The GitHub Release page includes the tag and release notes.

---
id: TUNE-0574
title: Close task-ID provenance leaks across repo site and fleet
status: in_progress
priority: P1
complexity: L4
type: framework
project: Datarim
started: 2026-08-09
parent: null
related: []
prd: prd/PRD-TUNE-0574.md
plan: plans/TUNE-0574-plan.md
---

# TUNE-0574 — Task-ID provenance leak: close the mechanism gaps, repo + site + fleet

## Overview

Critical Rule #8 (`CLAUDE.md`) forbids task IDs in shipped instruction artefacts, yet the enforcement gate (`scripts/task-id-gate.sh`) reports a clean pass on its four current directory callers despite 90 task-ID-shaped hits across those trees. Some are legitimate examples; three mechanism defects allow the real provenance stamps to escape review:

1. **Escape hatch abuse** – `gate:history-allowed` markers wrap genuine provenance stamps (e.g., `Source: TUNE-0280`, `Reference: ARCA-0009`) instead of only illustrative placeholders.
2. **File‑type coverage** – the gate walks only `.md` files, missing `.sh`, `.template`, `.yaml` files that contain task‑ID occurrences.
3. **Scope gap** – `documentation/{how-to,reference,explanation,tutorials}` (and root `CLAUDE.md`/`README.md`) are not scanned, leaving dead provenance links that point to gitignored task descriptions.

This task fixes the mechanisms first, then cleans every real violation, brings the site (`datarim.club`) and the installed runtime on all three machines into parity, and releases the change. The supplied brief pre‑authorises autonomous decisions for all judgement calls (classification, hatch handling, marker replacement); production and release actions still pass normal project gates.

## Acceptance Criteria

1. **Gate passes widened scopes**
   `scripts/task-id-gate.sh` exits 0 for `skills`, `agents`, `commands`, `templates`, `documentation/{how-to,reference,explanation,tutorials}`, `CLAUDE.md`, `README.md`. The gate walks `.md`, `.sh`, `.template`, `.yaml`/`.yml` (shipped text‑types).

2. **Zero real provenance stamps**
   All `Source:`, `Reference:`, `Created:`, `Parent epic:`, `Source task:` lines that name a real past task ID are removed from the above scopes. Illustrative/placeholder IDs (e.g. `TASK-0001`, `ARCA-0001`) remain, protected by the hatch.

3. **Contract documentation matches enforcement**
   - `skills/evolution/history-agnostic-gate.md` (gate contract) reflects the exact scopes and file‑types checked.
   - Rule #8 in `CLAUDE.md` describes the enforced scope without contradiction.
   - The hatch rule is explicit: only illustrative/placeholder IDs; malformed markers and provenance labels are rejected mechanically.

4. **Tests demonstrated with negative controls**
   Each new or changed gate behaviour has a bats test that fails against an isolated `origin/main` gate fixture and passes after the fix. Output of the failing run is recorded in the PR.

5. **All suites green**
   `bats tests/` and `dev-tools/tests/` pass. Every existing gate (`task-id-gate.sh`, `check-body-english.sh`, `check-doc-refs.sh`, `stack-agnostic-gate.sh`) passes its positive control before acceptance.

6. **Site parity**
   `tests/site-contract.sh` passes with a prefix-agnostic, no-hatch rule, a novel-prefix contaminating control, and an adjacent non-ID control. The `datarim.club` repo is updated. Deploy happens via push→main→CI only.

7. **Fleet consistency**
   After merge, `/opt/datarim` (and per‑user installs) on arcana‑devs, dev‑ai, aether are synchronised. Drift gates re‑run and all three machines show repo == installed runtime.

8. **Release**
   VERSION bumped, CHANGELOG entry, git tag, GitHub Release published.

9. **Provenance of THIS task**
   Only `documentation/how-to/evolution-log.md` records `TUNE-0574`. No task ID from this task is stamped into any shipped artefact.

## Constraints (non‑negotiable)

- Repository is PUBLIC – no operator names, absolute home paths, hostnames, IPs, credentials.
- English only in `commands/`, `skills/`, `agents/`, `CLAUDE.md`, `README.md`.
- Commit as `Arcanada <dev@veritasarcana.ai>`. Never as PavelValentov.
- Branch + PR; rebase on `origin/main` immediately before merge. Never rebase or force‑push shared main.
- Do NOT touch `/home/aether/code/aether/local-env/datarim` (Aether’s gated fork).
- Do NOT merge dependabot PRs #333 / #256.
- Do NOT delete `/home/dev/datarim-orphan-salvage-20260730/` or `/home/dev/w9-salvage`.
- Never `git checkout --` / stash / revert foreign hunks in a shared workspace.
- Credentials: never probe for liveness, never paste values, never rotate.
- Push your branch – local commit is not durability.

## Out of Scope

- `documentation/archive/` and `CHANGELOG.md` – legitimate provenance homes, left unchanged except for the required release entry in `CHANGELOG.md`.
- Historical entries already present in `documentation/how-to/evolution-log.md`; this task may add its own provenance record and any missing provenance displaced from shipped surfaces.
- `tests/fixtures/` – excluded from the gate by design.
- Dependabot PRs #333 and #256.
- Aether’s gated fork.
- Any change not required by the gate widening or instance clean‑up.

## Related

- PRD: `prd/PRD-TUNE-0574.md`
- Plan: `plans/TUNE-0574-plan.md`
- Evolution log: `documentation/how-to/evolution-log.md`

## Decisions

1. **Autonomous decisions authorised** – The task brief explicitly permits the orchestrator to make all judgement calls (classification of provenance stamps, hatch handling, marker replacement in `fleet-hook-sync.md`, etc.) without further approval. Production and release steps still pass normal project gates.

2. **Classification rule for hatch content** – Per the brief: illustrative/placeholder IDs (e.g. `TASK-0001`, `ARCA-0001`) are legitimate and may stay behind the hatch. Real provenance stamps that name a past task must be replaced with the rule/rationale and the provenance line moved to `evolution-log.md`. The hatch may be removed where no longer needed.

3. **Handling `fleet-hook-sync.md` functional grep** – Replace the historical task ID used as a deployed-hook marker with a stable semantic phrase describing the fail-closed missing-target rule. Update both the hook source and the documented grep, then verify that exact command against every installed hook. A semantic marker survives provenance cleanup and communicates the behavior being checked.

4. **Mechanical hatch enforcement** – The gate rejects malformed marker structure and provenance labels inside a hatch, including Markdown/case variants and a label whose ID occurs on the next nonblank line. A syntactically valid unlabeled illustrative block remains reviewable and allowed.

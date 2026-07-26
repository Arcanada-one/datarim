---
id: TUNE-0517
title: "Vendor-default model and latest CLI-agent policy"
status: completed
priority: P2
complexity: L2
type: framework
project: Datarim
started: 2026-07-26
parent: null
related: []
prd: null
plan: plans/TUNE-0517-plan.md
---

## Overview

Datarim must follow each supported CLI agent's current vendor-default model
and reasoning effort instead of silently preserving stale model pins. It also
needs a permission-aware preference for current stable CLI versions and an
optional, non-blocking version hint in fleet selection. This Class A change
adds generic policy, de-pins tier configuration to vendor-default semantics,
and preserves all routing and exit-code behavior.

## Acceptance Criteria

- [x] AC-1: `skills/datarim-system/model-assignment.md` defines the canonical
  vendor-default model and effort policy and differentiates it from the
  project-dependency rule in `skills/tech-stack/SKILL.md`.
- [x] AC-2: The framework documents a permission-aware preference for the
  newest stable CLI-agent versions, with upgrades only where permitted and a
  non-blocking recommendation where installs are restricted.
- [x] AC-3: Fleet backend selection can surface an optional version hint, but
  version detection is fail-open and never changes backend selection or exit
  codes.
- [x] AC-4: Autonomous mode pre-resolves model and effort selection to the
  vendor default and does not ask the operator.
- [x] AC-5: `config/model-tiers.yaml` uses vendor-default semantics instead of
  stale concrete model IDs, keeps `runtime_default: inherit`, and points to
  the canonical shipped policy.
- [x] AC-6: `CLAUDE.md` points to the canonical model-assignment policy and
  tier configuration without duplicating the rule.
- [x] AC-7: Presence-assertion bats tests cover the new Class A policy.
- [x] AC-8: Focused and full validation gates pass; changed shipped files are
  ASCII-only and contain no prohibited operator-specific literals; signed
  commits and every status flip are pushed; the task is archived.

## Constraints

- Advisory Class A only: no hard gate, routing change, or exit-code change.
- Version awareness must remain optional, cheap, non-blocking, and fail-open.
- Do not invent model IDs; prefer vendor-default semantics when current IDs
  cannot be established authoritatively.
- Shipped changes must be English-only and contain no operator-specific
  names, infrastructure labels, hostnames, or IP addresses.
- Work only in the isolated TUNE-0517 branch and push each status flip.

## Out of Scope

- Project dependency selection already governed by the tech-stack skill.
- Production deployment, public release, secret rotation, or forced upgrade.
- Changing fleet backend ordering, availability criteria, or failure codes.

## Related

- Parent PRD: none
- Sibling tasks: none
- Prior reflection: none

## Implementation Notes

- 2026-07-26: The mandated coworker draft calls returned no usable plan or
  task-description artifact, so native drafting was used under the documented
  fallback.
- 2026-07-26: Context7 was unavailable; concrete model IDs were not guessed.
  All four tiers now declare `vendor-default` selection with explicit
  omit-the-model-override adapter behavior.
- 2026-07-26: Added an opt-in CLI version hint that runs only after binary
  presence succeeds, ignores every probe failure, and cannot alter selection.
- Evidence: V-AC-1 - `tests/tune-0517-vendor-default-policy.bats` policy case.
- Evidence: V-AC-2 - permission-aware CLI policy presence case.
- Evidence: V-AC-3 - focused fleet selector and version-hint behavior cases.
- Evidence: V-AC-4 - autonomous pre-resolution presence case.
- Evidence: V-AC-5 - model-tier semantic mapping case and YAML parse.
- Evidence: V-AC-6 - CLAUDE and orchestration cross-link case.
- Evidence: V-AC-7 - focused bats red phase 1/7 pass, then green phase 19/19 pass.
- Evidence: V-AC-8 - full validation and hygiene gates run in QA/compliance.

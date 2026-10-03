---
id: {TASK-ID}
title: {short title, ≤80 chars}
status: in_progress
priority: P2
complexity: L2
type: {framework|infra|content|bugfix|...}
project: {project name}
started: {YYYY-MM-DD}
parent: null
related: []
prd: null
plan: null
---

<!--
Thin-index schema (v1.19.0+).

This is the canonical task description file. Path:
  datarim/tasks/{TASK-ID}-task-description.md

Frontmatter is a CLOSED 12-key schema. Do not add custom keys. Project-specific
extensions go in the body, not the frontmatter.

Body sections (markdown, ≤ 250 lines total):
  - ## Overview                — 2–5 sentences, problem + outcome
  - ## Acceptance Criteria     — checkbox list
  - ## Constraints             — immutable boundaries (security, perf, compat)
  - ## Out of Scope            — explicit non-goals
  - ## Related                 — parent PRD, sibling tasks, prior reflection
  - ## Implementation Notes    — optional, scratch log during /dr-do
  - ## Decisions               — optional, design choices and rationale

If the body grows beyond ~250 lines → split into a PRD (datarim/prd/) or design
doc (datarim/creative/).

Schema reference: skills/datarim-system/SKILL.md § Description File Contract.
-->

## Overview

(Brief description, problem statement, expected outcome.)

## Acceptance Criteria

<!-- Before implementation, bind every criterion to cases in
datarim/tasks/{TASK-ID}-acceptance.json and capture a preflight receipt in
datarim/qa/{TASK-ID}-evidence.json. Follow skills/immutability/SKILL.md
§ Acceptance and Evidence Loop: expected result/exit, required stage,
evidence type/environment, scope, and current hashed evidence per case.
Set workflow.complexity and workflow.task_type from this frontmatter, and pin
workflow.route before work. L1/L2 keep valid lightweight routes; content uses
write/edit/publish preparation stages, with mandatory QA/compliance at L3/L4.
Missing or stale evidence is pending/blocked, never a checked acceptance box. -->

- [ ] AC-1:
- [ ] AC-2:

<!--
Spec-traceability (L3+): when this task carries addressable requirements
(`#### D-REQ-NN: ...` in the PRD), bind each V-AC to the D-REQ id(s) it verifies
with a `Covers:` line, e.g.:

  - [ ] V-AC-1: <criterion>
        Covers: D-REQ-01, D-REQ-02

Plan steps declare graph edges explicitly:

  Verifies: V-AC-1, V-AC-2

Implementation and verification records declare evidence explicitly:

  Evidence: V-AC-1 — bats tests/example.bats

The pipeline resolves the path wish_id -> D-REQ -> V-AC -> plan-step ->
evidence automatically through `spec-graph-gate.sh`. Referenced ids must
resolve to a declared D-REQ. See documentation/reference/validator-contract.md and
documentation/explanation/spec-traceability-rollout.md.
-->


## Constraints

- (Security, performance, compatibility, regulatory, etc.)
- For classified sensitive sources, retain the metadata-only sanitized binding: approved sanitized path, original source pin, sanitized digest and omission/redaction constraints. Follow `${DATARIM_RUNTIME:?}/skills/security/SKILL.md` § Sensitive source context boundary; never copy original values into this record.

## Out of Scope

- (Explicit non-goals — what this task does NOT deliver.)

## Related

- Parent PRD: (path or none)
- Sibling tasks: (IDs or none)
- Prior reflection: (path or none)

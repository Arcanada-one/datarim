---
id: {TASK-ID}
title: {short title, ≤80 chars}
status: in_progress
priority: P2
complexity: L2
type: {framework|infra|content|bugfix|...}
project: {Datarim|Arcanada|...}
started: {YYYY-MM-DD}
parent: null
related: []
prd: null
plan: null
---

<!--
TUNE-0071 thin-index schema (v1.19.0+).

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

Schema reference: skills/datarim-system.md § Description File Contract.
-->

## Overview

(Brief description, problem statement, expected outcome.)

## Acceptance Criteria

- [ ] AC-1:
- [ ] AC-2:

## Constraints

- (Security, performance, compatibility, regulatory, etc.)

## Out of Scope

- (Explicit non-goals — what this task does NOT deliver.)

## Related

- Parent PRD: (path or none)
- Sibling tasks: (IDs or none)
- Prior reflection: (path or none)

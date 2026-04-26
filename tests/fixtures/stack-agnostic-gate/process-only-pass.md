---
name: fixture/process-only-pass
description: Golden PASS fixture — process-only Class A proposal (dogfooding clause for task-template). Gate MUST exit 0.
---

# Golden PASS fixture — process-only Class A

This proposal is purely about workflow process and contains no stack-specific
keywords. The gate MUST allow it through (exit 0).

## Proposed addition to task-template

Add a "Dogfooding Checkpoint" section to `templates/task-template.md`:

> Before promoting any framework-internal task to /dr-archive, run the same
> command from a fresh clone of the framework against a throwaway project
> directory. Capture the output, paste into the reflection document, and
> confirm the user-visible behaviour matches the plan's Acceptance Criteria.

Rationale: process hardening only. No tooling, no runtime, no language
ecosystem implied. Future projects in any stack benefit equally.

## Approval path

Class A (content-only addition to existing template). Reflection approval
sufficient. No PRD update required.

---
name: visual-maps
description: Visual index for Datarim maps. Load this entry first, then only the diagram fragment needed for routing, stage flow, or dependency orientation.
model: sonnet
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Visual Maps — Workflow Diagrams

> **When to load:** When an agent needs visual orientation in the Datarim pipeline or framework structure. Do not load the full map set for simple tasks with an obvious next step.

## Fragment Routing

Load only the fragment relevant to the question:

- `skills/visual-maps/pipeline-routing.md`
  Use for complexity-based routing across `init → archive` and the artefact flow (`init-task`, `expectations`, `playwright-run` nodes since v2.8.0).
- `skills/visual-maps/stage-process-flows.md`
  Use for stage-specific flows from `/dr-init` through `/dr-archive`, including Layer 3b expectations verification and Layer 4f `playwright-run` in `/dr-qa`.
- `skills/visual-maps/content-and-management-flows.md`
  Use for `/dr-write`, `/dr-edit`, `/factcheck`, `/humanize`, `/dr-addskill`, `/dr-optimize`, and `/dr-dream`.
- `skills/visual-maps/utility-and-dependencies.md`
  Use for utility command flows, command-agent relationships, and agent-skill dependencies (includes `init-task-persistence`, `expectations-checklist`, `playwright-qa`, `human-summary` nodes since v2.8.0).
- `skills/visual-maps/panels-and-quality.md`
  Use for Consilium panel layouts and stage-to-quality rule mapping.

## Quick Selection Guide

- Need to decide which pipeline a task should follow? Load `pipeline-routing.md`.
- Need to understand one pipeline stage in detail? Load `stage-process-flows.md`.
- Need content, optimization, or knowledge-management flows? Load `content-and-management-flows.md`.
- Need relationship graphs between commands, agents, and skills? Load `utility-and-dependencies.md`.
- Need Consilium structure or quality-rule mapping? Load `panels-and-quality.md`.

## Why This Skill Is Split

This skill is used for orientation, not for every task. Keeping a short index entry avoids loading unrelated diagrams into context while preserving the full map library in directly addressable fragments.

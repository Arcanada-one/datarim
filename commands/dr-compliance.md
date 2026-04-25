---
name: dr-compliance
description: Adaptive post-QA hardening. Detects task type and applies matching verification checklist. Final quality gate before archiving.
---

# /dr-compliance — Adaptive Post-QA Hardening

**Role**: Compliance Agent
**Source**: `$HOME/.claude/agents/compliance.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/compliance.md` and adopt that persona.
2.  **RESOLVE PATH**: Find `datarim/` using standard path resolution.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/compliance.md` (Adaptive checklists)
5.  **DETECT TASK TYPE**: Read `datarim/tasks.md` (for the resolved task) and `datarim/activeContext.md`. Determine: code, documentation, research, legal, content, infrastructure, or mixed.
6.  **APPLY CHECKLIST**: Execute the appropriate checklist(s) from the compliance skill:
    - **Code** → 7-step software checklist (lint, tests, coverage, CI/CD)
    - **Documentation** → completeness, accuracy, consistency, cross-references, audience
    - **Research** → methodology, citations, argument coherence, scope
    - **Legal** → jurisdiction, definitions, structure, rights/obligations
    - **Content** → factcheck, humanize, platform requirements, editorial standards
    - **Infrastructure** → configuration, rollback plan, monitoring, security
    - **Mixed** → apply relevant sections from each matching type
7.  **REPORT**: Output compliance report with per-step results and overall verdict.

## Output
- `datarim/reports/compliance-report-{task_id}.md` (if directory exists)
- Otherwise: report in chat

## Verdicts
- **COMPLIANT** — all checks pass
- **COMPLIANT_WITH_NOTES** — passes with minor observations
- **NON-COMPLIANT** — critical issues found, fix before archiving

## Next Steps (CTA)

After verdict, the compliance agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. NON-COMPLIANT verdicts use the FAIL-Routing variant (see § FAIL-Routing in cta-format).

**Routing logic for `/dr-compliance`:**

- COMPLIANT or COMPLIANT_WITH_NOTES → primary `/dr-archive {TASK-ID}` (final archive with reflection Step 0.5)
- NON-COMPLIANT, PRD/task alignment gap → primary `/dr-prd {TASK-ID}` (FAIL-Routing Layer 1; update requirements, resume forward)
- NON-COMPLIANT, code/test/lint/CI issues → primary `/dr-do {TASK-ID}` (FAIL-Routing Layer 4; fix, re-run `/dr-compliance` — new report gets `-v2` suffix)
- NON-COMPLIANT, source unclear → primary `/dr-do {TASK-ID}` (default)
- Loop guard: 3 same-layer fails → escalate to user

The CTA block MUST follow canonical FAIL-Routing format when NON-COMPLIANT (header changes to `**Compliance NON-COMPLIANT для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`). Variant B menu when >1 active tasks.

---
name: dr-write
description: Create written content — articles, blog posts, docs, research papers, social media posts. Uses writer agent with writing workflow.
argument-hint: [topic or file path]
---

# /dr-write — Create Content

**Acceptance before authoring:** apply `skills/immutability/SKILL.md`
§ Acceptance and Evidence Loop before Step 5, including consilium drafts.
For a task-bound content request, pin the selected content route, define cases,
capture `check-live-evidence.sh --root <repo-root> --contract <acceptance.json>
--evidence <evidence.json> --stage preflight` before work, and retain its receipt.
Before handing off the draft, append write-stage evidence and run the same
strict command with `--stage write`. A discrepancy returns to writing and
fresh checks; later reviews are invalidated. An existing baseline is preserved.
For standalone work without a Datarim/Git task, define the acceptance checklist
before drafting, cite actual per-case evidence, and state **UNCERTIFIED** for
the structured gate; never claim task-pipeline PASS. Draft completion is not
editorial approval, publication, or operator acceptance.

**Role**: Writer Agent
**Source**: `${DATARIM_RUNTIME:?}/agents/writer.md`

## Instructions


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `${DATARIM_RUNTIME:?}/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `${DATARIM_RUNTIME:?}/agents/writer.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `${DATARIM_RUNTIME:?}/skills/datarim-system/SKILL.md` (Always)
    - `${DATARIM_RUNTIME:?}/skills/writing/SKILL.md` (Writing workflow and quality checklist)
    - `${DATARIM_RUNTIME:?}/skills/artifact-context/SKILL.md` (Artifact format and exact contract quotations)
    - `${DATARIM_RUNTIME:?}/skills/humanize/SKILL.md` (Reference for avoiding AI patterns from the start)
    - **Voice-bearing content:** the assigned model performs writing, editing, translation, and factual review directly. Preserve the operator's authorship and publication constraints.
3.  **RESOLVE PATH**: Find `datarim/` directory using standard path resolution. If not found, content work can proceed without it — not all writing requires a Datarim project context.
4.  **UNDERSTAND THE REQUEST**:
    - What type of content? (article, blog post, docs, research, social media, legal, report)
    - Who is the audience?
    - What is the target register? (formal, conversational, academic, casual)
    - What is the target length and platform?
    - Are there existing materials to build on? (`$ARGUMENTS` may be a file path)
5.  **EXECUTE Writing Pipeline**:
    - **Research and plan**: Gather sources, create outline, identify claims to verify.
    - **Draft**: Write from the outline, one section at a time. Write naturally.
    - **Self-review**: Check structure, flow, claims, and naturalness.
    - **Mark for editorial review**: Flag sections that need fact-checking or style review.
6.  **OUTPUT**: Draft content with editorial notes. Suggest `/dr-edit` for fact-checking and AI pattern review.

## Multi-Vendor Consilium Mode

When `--consilium` is passed as an argument (or `DATARIM_CONSILIUM=1` is set),
`/dr-write` activates the multi-vendor draft path instead of the standard single-agent pipeline.

**Activation:** `dr-write --consilium [brief-file]`

**What changes:**
1. Steps 4-5 above are skipped for the initial draft phase.
2. The `dr-orchestrate` plugin fan-out script (`content_consilium_fanout.sh`)
   is invoked with the brief and the stage label `"write"`.
3. Three vendor CLIs each produce an independent draft in parallel tmux sessions.
4. The judge script (`content_consilium_judge.sh`) scores all drafts and
   selects the best one using the write-stage scoring criteria.
5. The selected draft is placed at the standard output path; the judge decision
   and run-log are written to `datarim/pub-consilium/{RUN-ID}/`.
6. Execution resumes at Step 6 (OUTPUT) with the selected draft.

**Degradation:** if fewer than 3 vendors complete, 2-of-3 proceeds; fewer than 2
exits non-zero and falls back to the standard single-agent path with a warning.

See `${DATARIM_RUNTIME:?}/skills/consilium/SKILL.md` § Real Multi-Vendor Mode for the full protocol.

## Next Steps (CTA)

After draft, the writer agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `${DATARIM_RUNTIME:?}/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-write`:**

- Draft ready, needs editorial pass → primary `/dr-edit {TASK-ID}` (fact-check + style + AI patterns)
- Draft approved, ready to ship → primary `/dr-publish {TASK-ID}` (multi-platform formatting)
- Standalone piece, only targeted check needed → alternative `/factcheck` or `/humanize`
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format defined in `skills/cta-format/SKILL.md` (numbered options, exactly one primary marker, `---` HR). Variant B menu when >1 active tasks.

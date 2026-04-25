---
name: dr-write
description: Create written content — articles, blog posts, docs, research papers, social media posts. Uses writer agent with writing workflow.
argument-hint: [topic or file path]
---

# /dr-write — Create Content

**Role**: Writer Agent
**Source**: `$HOME/.claude/agents/writer.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/writer.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/writing.md` (Writing workflow and quality checklist)
    - `$HOME/.claude/skills/humanize.md` (Reference for avoiding AI patterns from the start)
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

## Next Steps (CTA)

After draft, the writer agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-write`:**

- Draft ready, needs editorial pass → primary `/dr-edit {TASK-ID}` (fact-check + style + AI patterns)
- Draft approved, ready to ship → primary `/dr-publish {TASK-ID}` (multi-platform formatting)
- Standalone piece, only targeted check needed → alternative `/factcheck` or `/humanize`
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks.

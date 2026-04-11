---
name: dr-write
description: Create written content — articles, blog posts, documentation, research papers, social media posts, or any structured text. Uses the writer agent with writing workflow skill.
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

## Next Steps
- Content needs fact-checking or polish? → `/dr-edit`
- Content is part of a Datarim task? → `/dr-qa` (for pipeline integration)
- Content is a standalone piece? → `/factcheck` or `/humanize` for targeted review

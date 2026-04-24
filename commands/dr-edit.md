---
name: dr-edit
description: Editorial review — fact verification, AI pattern removal, style consistency. Uses editor agent with factcheck and humanize skills.
argument-hint: [file path to review]
allowed-tools: Read Write Edit Grep Glob Bash WebSearch WebFetch Agent
effort: high
---

# /dr-edit — Editorial Review

**Role**: Editor Agent
**Source**: `$HOME/.claude/agents/editor.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/editor.md` and adopt that persona.
2.  **LOAD SKILLS** (all mandatory for editorial work):
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/factcheck.md` (Fact verification methodology)
    - `$HOME/.claude/skills/humanize.md` (AI pattern detection and removal)
    - `$HOME/.claude/skills/writing.md` (Quality checklist and editorial standards)
3.  **READ THE CONTENT**: Read the file at the path provided in `$ARGUMENTS`. If no path given, ask the user.
4.  **SETUP**:
    - Detect the primary language (English, Russian, or mixed).
    - Identify the content type and target register.
    - Create a backup next to the original: `{name}.backup-{timestamp}.{ext}`
5.  **EDITORIAL REVIEW** (3 phases):

    ### Phase 1: Fact Verification
    - Extract all verifiable factual claims.
    - Verify each claim against authoritative sources using WebSearch and WebFetch.
    - Assign verdicts: ACCURATE, INACCURATE, OUTDATED, MISLEADING, UNVERIFIABLE, NEEDS_CONTEXT.
    - For critical claims, cross-reference with 2+ independent sources.

    ### Phase 2: AI Pattern Removal
    - Scan for AI writing patterns: banned vocabulary, structural tells, formatting artifacts.
    - Check communication tells (chatbot artifacts, sycophantic tone, knowledge cutoff disclaimers).
    - Check linguistic patterns (copula avoidance, synonym cycling, significance inflation).
    - For Russian text: check textbook tone, restated ideas, generic phrases, absurd metaphors.
    - Apply fixes in 3 passes: vocabulary/formatting → structure/rhythm → anti-AI audit.

    ### Phase 3: Editorial Polish
    - Style consistency: terminology, tone, formatting across the entire document.
    - Structural review: argument flow, section balance, logical coherence, transitions.
    - Citation and reference audit: verify links, check source authority.
    - Final naturalness check: does every paragraph sound like a human wrote it?

6.  **REPORT**: Present a summary of all changes by category:
    - Factual corrections (with sources)
    - AI pattern fixes (with counts by category)
    - Structural improvements
    - Items that need the author's attention (meaning-altering changes)
7.  **APPLY**: After user approval, apply changes to the original file. Confirm backup location.

## Output
- Editorial report with change summary
- Corrected document (after approval)
- Backup of the original

## Next Steps
- Content needs more writing or rework? → `/dr-write`
- Content approved and ready to publish? → `/dr-publish`
- Part of a Datarim pipeline task (non-content)? → `/dr-qa` or `/dr-archive`
- Quick targeted check only? → `/factcheck` or `/humanize`

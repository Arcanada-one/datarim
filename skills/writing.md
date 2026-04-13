---
name: writing
description: Content creation and editorial workflow — research, outlining, drafting, editing, fact-checking, and publication preparation. Loaded by writer and editor agents for structured content work.
model: sonnet
---

# Writing Workflow

Rules and patterns for structured content creation and editorial review.

## Content Types and Registers

| Type | Register | Structure | Typical Length |
|------|----------|-----------|---------------|
| Technical docs | Formal, precise | Sections with headings, code examples | Variable |
| Blog post | Conversational, engaging | Hook → body → takeaway | 1000-3000 words |
| Research paper | Academic, rigorous | Abstract → methodology → findings → discussion | 3000-10000 words |
| Social media | Casual, direct | Hook → value → CTA | 100-500 words |
| Legal document | Formal, precise | Numbered sections, defined terms | Variable |
| Project report | Professional, structured | Executive summary → details → recommendations | 1000-5000 words |

## Writing Pipeline

### Phase 1: Research and Planning
1. Define audience, purpose, and key messages.
2. Research: gather sources, data, examples. Use WebSearch for current information.
3. Create an outline with section-level detail.
4. Identify claims that will need fact-checking.

### Phase 2: Drafting
1. Write from the outline. One section at a time.
2. Lead with the most important information (inverted pyramid for articles).
3. Use concrete examples and specific data over abstract statements.
4. Write naturally — avoid the AI patterns listed in the humanize skill from the start.
5. Mark claims that need verification with `<!-- verify: claim -->` comments.

### Phase 3: Self-Review (before editor)
1. Read aloud (mentally). Does it sound like a person wrote it?
2. Check: does every paragraph advance the argument?
3. Check: is the structure logical? Can a reader skim headings and get the gist?
4. Check: are all claims supported? Are sources cited?

### Phase 4: Editorial Review (editor agent)
1. Fact verification — extract and verify all claims.
2. AI pattern scan — detect and remove vocabulary, structural, and formatting artifacts.
3. Style consistency — terminology, tone, formatting.
4. Structural review — argument flow, section balance, transitions.

### Phase 5: Publication Preparation
1. Final proofread.
2. Format for target platform (Markdown, HTML, social media format).
3. Prepare multi-language versions if needed.
4. Create backups of the final version.

## Quality Checklist

Before any content is considered complete:

- [ ] Audience and purpose are defined
- [ ] All factual claims are verified (use factcheck skill for high-stakes content)
- [ ] No AI writing patterns remain (use humanize skill if uncertain)
- [ ] Structure is clear and scannable
- [ ] Tone matches the target register
- [ ] All links and references are valid
- [ ] Spelling and grammar are correct in all languages used
- [ ] Content reads naturally — not "too clean" or "too balanced"
- [ ] Target audience claims verified with the author (who it's for / not for — these contain subjective judgments that factcheck can't catch from sources alone)

## Anti-Patterns to Avoid

1. **Writing without an outline** — leads to meandering structure.
2. **Starting with "In this article..."** — just start with the content.
3. **Symmetrical arguments** — "On one hand... on the other hand..." without taking a position.
4. **Filler conclusions** — "The future looks bright" or "Only time will tell." Be specific or end without a conclusion.
5. **Excessive hedging** — "It could potentially perhaps..." Commit to a position.
6. **Citation-free claims** — every non-obvious claim needs a source.
7. **Writing for AI detectors** — write for humans. Natural writing passes any detector.

## Multi-Language Content

When creating content in multiple languages:
- Write the primary version first (usually the author's strongest language).
- Translate with cultural adaptation, not literal translation.
- Each language version is independent — it may have different structure, examples, or emphasis.
- Russian tech content uses English technical terms with Russian explanation where needed.
- Social media posts: create RU long, RU short, EN long, EN LinkedIn, EN Twitter variants as needed.

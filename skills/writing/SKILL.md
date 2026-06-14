---
name: writing
description: Content creation + go-to-market — research, drafting, editing, publication, SEO, analytics, launch. Loaded by writer and editor agents.
model: inherit
current_aal: 1
target_aal: 2
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
6. **Numbers check:** every number must come from the primary source (spec sheet, benchmark JSON, invoice), not from memory or context summaries. `free -h` shows 62Gi; the spec is 64 GB. Use the spec.
7. **Comparative metrics:** if you write "37x faster" or "45% higher", state what you're comparing against in the same sentence. The reader hasn't seen your internal requirements doc.
8. **CTA platform check:** before writing "tell us in the comments", verify the target platform has comments. Website without comments → "write to us" or omit.
9. **Link verification:** before publishing any content with URLs, verify every link is accessible (curl, gh api, WebFetch). Local file paths do not guarantee GitHub/web availability. A local `benchmark/` folder ≠ `github.com/repo/tree/main/benchmark`.
10. **Pricing/subscription claims:** always verify via WebSearch — pricing models change frequently. Cursor switched from request-based to credit-based billing mid-2025; Gemini CLI auth changed from AI Studio to Code Assist license. Never write pricing from memory.
11. **Every action gets a subject.** Do not write events as if they happened by themselves: "the SSH probes swept across the servers", "the price-drop will not be a one-off". A reader hears a robot. Name who did it — the agents, the product, the person — or rewrite naturally: "on June 3 the agents ran a full investigation: connected over API keys and SSH to every server and took measurements"; "the letter is not a one-off — more increases will follow". This is the inverse of the phantom-`we` rule (don't invent a `we`); here, don't strip the subject out entirely until the sentence reads as machine output.
12. **Scale the language to the event.** A routine operation gets routine words. `docker prune` freeing disk is not a survived catastrophe — do not write "not one of the 23 running containers was harmed, no downtime occurred". Write "ran `docker prune`, freed up the disk, nothing in production was affected". Reserve dramatic phrasing (casualties, survival, zero-downtime heroics) for events that were genuinely at risk.
13. **Don't publish internal numbers that serve no reader.** Exact disk capacities, raw DB sizes, container counts, server counts — include a number only when it carries meaning for the reader (an effect, a comparison, a decision). "Disk was full of build cache, freed it" beats "271 GB of which Postgres was 47 MB, ClickHouse 3.3 GB…". When in doubt, cut the figure; keep the point.
14. **Causal sanity check.** Before writing a cause, test it against what the system actually does. Production databases do not "balloon on their own" if the services on that host don't generate that data — the real cause is something else (build cache, logs, snapshots). A plausible-sounding cause that contradicts the architecture is a factual error, not a stylistic one.
15. **Never announce or meta-comment a heading.** Headings like "Philosophical finale", "An important conclusion", "The big takeaway" tell the reader how to feel instead of saying the thing. Name the actual content: "From infrastructure-as-code to infrastructure as an agent's service". Same rule inside prose — don't label your own point as profound, just make it.
16. **No moralizing, no hollow verdicts.** Cut sentences whose only job is to pronounce a lesson or a boundary: "but the line remains", "the extra cost buys peace of mind later", "this is the new level". State the concrete fact instead: "the human controls the final action — the purchase — and pays with their own card". If a sentence can be deleted without losing a fact, it was a moral, not content.
17. **Translate jargon to human language.** Words like "machine-readable", "feed", "live JSON" are writer-facing, not reader-facing. Say what they mean to the reader: "the data has everything needed — processors, memory, disks, ECC, location, current price". Keep a proper noun (a file name, a protocol) only when it's load-bearing.

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
8. **Subjectless action prose** — "the probes swept", "it will not be a one-off". Give every action a subject (see Drafting rule 11).
9. **Dramatizing routine ops** — survival/zero-downtime language for a `prune` or a restart (see Drafting rule 12).
10. **Announcing the heading** — "Philosophical finale", "An important conclusion" (see Drafting rule 15).
11. **Moralizing verdicts** — "but the line remains", "buys peace of mind" (see Drafting rule 16).

## Multi-Language Content

When creating content in multiple languages:
- Write the primary version first (usually the author's strongest language).
- Translate with cultural adaptation, not literal translation.
- Each language version is independent — it may have different structure, examples, or emphasis.
- Russian tech content uses English technical terms with Russian explanation where needed.
- Social media posts: create RU long, RU short, EN long, EN LinkedIn, EN Twitter variants as needed.
- **Social posts must be self-contained** — min ~200 words for FB/TG/LI. A picture does not replace text. Platform limits are generous (FB: 63K chars, TG: 4096, LI: 3000) — use them. A 130-word summary is a teaser, not a post.
- **Articles end on a CTA.** A long-form article should close with a call to action inviting the reader to respond — comments, the discussion channel, "tell me if you'd use this". Make it specific to the piece, not a generic "follow us".
- **CTA language follows the version's language.** In an EN article the CTA, the channel name, and the invitation are written in English ("join the discussion on Telegram"), never half-translated. In a RU article they're in Russian. The destination (e.g. a Telegram channel) is the same; only the wording matches the reader's language.

---

## Go-to-Market & Launch

### Technical SEO Checklist
- `robots.txt` allows indexing; XML sitemap submitted to Search Console
- Canonical tags correct; no duplicate content (www vs non-www, http vs https)
- Unique `<title>` (50-60 chars) and `<meta description>` (120-160 chars) per page
- One `<h1>` per page; heading hierarchy logical (h1>h2>h3)
- JSON-LD schema markup (Article, Product, FAQ, Organization)
- Core Web Vitals: LCP<2.5s, INP<200ms, CLS<0.1

### Analytics Setup
- GA4: data stream, enhanced measurement, custom events, conversions, 14-month retention
- Search Console: property verified, sitemap submitted, no critical coverage errors
- Ad tracking: conversion tags installed, UTM parameters on all ad URLs

### Website Pre-Launch
- SSL valid, HTTPS everywhere, HSTS enabled, www/non-www redirect
- OG tags (og:title, og:description, og:image 1200x630px), Twitter Card tags
- 404 page customized, forms tested, favicon installed (16/32/180/192/512)
- Privacy Policy, Terms of Service, cookie consent banner
- PageSpeed mobile >80, no broken links, cross-browser tested

### Landing Page Optimization
- Above fold: headline matching ad promise, one primary CTA, social proof
- Below fold: feature/benefit blocks with specifics, FAQ, secondary CTA
- Mobile-responsive, minimal form fields, inline validation

### Campaign Budget Framework
- 70% proven channels, 20% testing, 10% experimental
- Key metrics: CPA < target, ROAS > 3x, CTR > 2% search, CVR > 2% landing page

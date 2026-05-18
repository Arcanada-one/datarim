---
name: frontend-ui
description: Frontend UI checklist — CSS specificity, dark/light themes, visual testing, mobile responsiveness, i18n parity. Apply when editing HTML/CSS.
model: sonnet
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Frontend UI — Checklist for Web Interface Tasks

Use when task modifies HTML, CSS, templates, or visual components. Catches recurring UI bugs missed by HTTP/syntax checks.

---

## 1. CSS Dark/Light Mode Specificity

**Rule:** Light mode = default. `.dark` class = override. Never use `:not(.dark)` selectors.

### Anti-Pattern (BREAKS dark mode)

```css
.dark .component { background: #0f172a; }
:not(.dark) .component { background: #ffffff; }  /* ← matches <body>, <section>, <div> */
```

`:not(.dark)` matches any ancestor without the class, including `<body>` / `<section>` / `<div>`. Since these are also ancestors of `.component`, the selector ALWAYS matches, overriding `.dark` rules due to cascade order. Result: light colors leak into dark mode.

### Correct Pattern

```css
.component { background: #ffffff; }            /* default = light */
.dark .component { background: #0f172a; }      /* override = dark */
```

Checklist:
- [ ] Tailwind config sets `darkMode: 'class'`
- [ ] `<html class="dark">` initial state from localStorage
- [ ] No `:not(.dark)` selectors in any CSS file
- [ ] Light styles have no class prefix (they ARE the default)
- [ ] Dark overrides use `.dark .component` pattern

---

## 2. Visual Verification

HTTP 200 + valid HTML is insufficient for UI tasks. A page can render with broken visual state and still return 200.

Required checks before marking UI task complete:

- [ ] Screenshot of dark mode (all sections visible, no light leaks)
- [ ] Screenshot of light mode (all sections visible, no dark leaks)
- [ ] Mobile viewport (320px, 375px) — no horizontal scroll, readable text
- [ ] Tablet viewport (768px) — layout adapts
- [ ] Desktop viewport (1280px+) — max-width containers work
- [ ] Theme toggle switches instantly (no flash of wrong theme)

If unable to capture screenshots, explicitly ask the user to verify visually before closing.

---

## 3. i18n UI Parity (if applicable)

For bilingual/multilingual sites:

- [ ] All supported language files have identical keys (diff check)
- [ ] Language switcher works from every page
- [ ] URL prefix `/en/`, `/ru/` respected on all internal links (`lang_url()` helper)
- [ ] Cookie persists language choice across requests
- [ ] Date formatting respects current language
- [ ] Text length difference (RU ~20-30% longer than EN) doesn't break layouts
- [ ] Hardcoded strings audit: `grep` in templates for English/Russian leaks on wrong-language pages

---

## 4. Mobile Responsiveness

- [ ] Navigation collapses to hamburger at lg breakpoint
- [ ] Tap targets ≥ 44×44px
- [ ] No content overflows viewport width
- [ ] Images scale down (`max-width: 100%`)
- [ ] Text doesn't get smaller than 14px base

---

## 5. Accessibility Baseline

- [ ] Color contrast ≥ WCAG AA for body text
- [ ] `<button>` has accessible label (`aria-label` if icon-only)
- [ ] Theme toggle has `aria-label` that reflects current state
- [ ] Skip-to-content link (for long navigation)
- [ ] Focus states visible (don't remove outline without replacement)
- [ ] `prefers-reduced-motion` respected for animations

---

## 6. Performance Hygiene

- [ ] No unbounded CSS (`* { animation: ... }`)
- [ ] Images have `loading="lazy"` where below fold
- [ ] Fonts loaded with `font-display: swap`
- [ ] No blocking scripts in `<head>` (use `defer` or `async`)

---

## 7. SEO & Social Preview

- [ ] Unique `<title>` per page
- [ ] `<meta description>` present and relevant
- [ ] Open Graph tags: `og:title`, `og:description`, `og:image`, `og:url`, `og:type`
- [ ] Twitter Card meta
- [ ] `og:image` file actually exists (not just referenced)
- [ ] Canonical URL
- [ ] `hreflang` in sitemap.xml for multilingual sites

---

## When to Apply

- Any `/dr-do` that modifies `.html`, `.php` templates, `.css`, `.vue`, `.tsx` files touching UI
- Any task with type "Website Development" or "Frontend"
- Before closing UI tasks with `/dr-compliance`

## 8. Source of Truth for Component Counts

Before generating lists of framework components (agents, skills, commands, use cases) for content, documentation, or marketing:

1. **Query the filesystem** — never rely on cached numbers from previous sessions:
   ```bash
   ls $HOME/.claude/agents/*.md | wc -l    # actual agent count
   ls $HOME/.claude/commands/*.md | wc -l  # actual command count
   ls $HOME/.claude/skills/*.md | wc -l    # actual skill count
   ```
2. **Check source docs** for use cases, features, capabilities:
   - `docs/use-cases.md` in the Datarim repo for the canonical use case list
   - Agent/skill `.md` files for accurate capability descriptions
3. **Never hardcode counts** — they drift as the framework evolves (e.g., 15→16 agents, 18→22 skills during v1.5→v1.6)

**Why:** A prior incident showed stale counts on the site ("15 agents / 18 skills" while actuals were 16/22, and 6 use cases instead of 13). Both errors came from relying on stale session data instead of querying the source.

---

## 9. Browser-Based Verification at `/dr-qa`

When the task changes any file under § 1–4 above, `/dr-qa` runs an
automated Playwright pass against the local dev surface or a static
fixture. Contract: `$HOME/.claude/skills/playwright-qa.md` (resolution
chain CLI → MCP → env-browser, three headed states, per-task flock,
`datarim/qa/playwright-{ID}/run-<ts>/` artifact layout). Missing tooling
is a finding, not a block; `--headed-strict` without a display fails the
QA pass.

Two operator-facing knobs:

- CLI: `/dr-qa --headed` (lenient) or `/dr-qa --headed-strict` (fail-fast)
- Init-task frontmatter: `qa_browser_mode: headed | headed-strict | skip`

Inspect `datarim/qa/playwright-{ID}/latest/summary.md` for the most
recent pass. Visual review (does the screenshot match intent?) remains an
operator step — the automated pass captures evidence, it does not
adjudicate aesthetic correctness.

---

## Integration

- `tester` agent: include this checklist in Web UI testing mode
- `developer` agent: consult before completing frontend tasks
- `reviewer` agent: verify compliance during `/dr-qa`
- `playwright-qa.md`: detailed contract for the automated browser pass
  invoked at `/dr-qa` Step 4f

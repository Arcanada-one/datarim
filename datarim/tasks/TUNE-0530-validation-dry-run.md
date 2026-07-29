# TUNE-0530 — Validation Dry-Run: Control Arcana Case

## Scenario

**What happened (pre-TUNE-0530):** The Control Arcana redesign task reached an agent. The current `tech-stack/SKILL.md` prescribed "SPA / Dashboard: Vite, React or Vue, Tailwind, TanStack Query, Vitest." The agent concluded "no MUI" on the false premise that MUI is a paid component (it is MIT-licensed; the purchased artefact is the Minimals.cc template built on top of it). The framework offered no mechanism to surface "Tailwind vs MUI" as a decision with trade-offs. The agent defended the incumbent. A legitimate architectural question never reached the operator.

**What would happen (post-TUNE-0530):** Under the reworked mechanism, here is the stack proposal the new tech-stack skill would generate.

---

## Stack Proposal for Control Arcana Admin Dashboard

### Context

Building an admin dashboard (data-dense, forms-heavy, multiple table views with sorting/filtering/inline editing) as part of the Control Arcana redesign. The existing project uses React + Tailwind. The "When to Reconsider" litmus test fires: "More than 5 distinct table views with sorting, filtering, and inline editing" → this is a legitimate decision point.

### Candidate Stacks

#### Option A: React + MUI v6 + Emotion

| Factor | Assessment |
|--------|-----------|
| Fit for domain | Excellent — MUI is designed for data-dense enterprise dashboards. MUI X Data Grid is best-in-class for complex tables (sorting, filtering, inline editing, CSV export). |
| Ecosystem maturity | Very high — MUI has 95K+ GitHub stars, used by NASA/Amazon/Salesforce internally, 12+ years of maintenance. |
| Team/AI familiarity | Medium — Arcanada team primarily uses Tailwind; AI models have strong MUI knowledge (widely used in training data). |
| Performance profile | Good — Emotion CSS-in-JS adds ~50-90KB gzipped baseline. MUI X Data Grid virtualizes rows for large datasets. |
| Security posture | Strong — Regular security advisories, dependency audit via `npm audit`, signed releases. Recent CVE history: 2 moderate in 2025, both patched within 7 days. |
| Licence compatibility | MIT (free tier). MUI X Pro (advanced data grid, date pickers) is paid at $14/dev/month — assess whether Pro features are needed. Core components (tables, forms, dialogs) are fully MIT. |
| Cost | Free (MIT core). Optional MUI X Pro: $14/dev/month if advanced data-grid features needed. |
| Bundle/runtime cost | ~90KB gzipped (MUI core + Emotion + icons). MUI X Data Grid adds ~30KB. |
| Operational fit (Arcanada) | Low — Arcanada currently runs Tailwind across all frontends. MUI would be the first Material Design surface. |
| Escape velocity | Medium — MUI components are tightly integrated (switching from MUI Data Grid to TanStack Table requires rewriting all table views). Standard React patterns otherwise. |

**Key risk:** Ecosystem coherence — MUI would be the sole Material Design surface in a Tailwind ecosystem. Migration back to Tailwind requires rewriting all component usages.

#### Option B: React + Tailwind CSS + TanStack Table (incumbent)

| Factor | Assessment |
|--------|-----------|
| Fit for domain | Adequate — Tailwind is a utility framework, not a component library. Complex data tables require assembling TanStack Table + React Hook Form + Zod + sonner + cmdk + date-fns (~8 packages). |
| Ecosystem maturity | Very high — Tailwind is the most-used CSS framework (39M+ npm downloads/week). TanStack Table is the leading headless table library. |
| Team/AI familiarity | High — Arcanada team already uses Tailwind. AI models produce reliable Tailwind code. |
| Performance profile | Excellent — Tailwind compiles to minimal CSS at build time. No runtime CSS-in-JS overhead. |
| Security posture | Strong — Tailwind has no runtime (build-time only); no CVE surface. TanStack Table is headless (no DOM rendering). |
| Licence compatibility | MIT (all components). No paid tiers. |
| Cost | Free. |
| Bundle/runtime cost | ~20KB gzipped (Tailwind compiled CSS). TanStack Table adds ~15KB. Total: ~35KB (vs MUI's ~120KB). |
| Operational fit (Arcanada) | High — Tailwind is the Arcanada ecosystem default. Shared Tailwind config, shared component patterns. |
| Escape velocity | Low — Switching from TanStack Table to another table library is straightforward (headless, no rendering opinions). Tailwind utility classes are portable. |

**Key risk:** Development velocity for data-grid features — TanStack Table provides the logic; the developer must build all UI (sort indicators, filter inputs, pagination controls, CSV export) from scratch. For 5+ table views, this is weeks of work that MUI gives for free.

#### Option C: React + Mantine 7

| Factor | Assessment |
|--------|-----------|
| Fit for domain | Excellent — Mantine ships a free data table (`mantine-datatable`) with server-side sorting, pagination, row selection, and CSV export built in. 60+ hooks included (`useDebouncedValue`, `useLocalStorage`, `useClipboard`). Dark mode is first-class (one prop). |
| Ecosystem maturity | High — Mantine 7 is stable, 27K+ GitHub stars, active maintenance. Smaller than MUI but growing rapidly. |
| Team/AI familiarity | Medium-Low — Arcanada team has no Mantine experience. AI models have good Mantine knowledge (increasingly common in training data). |
| Performance profile | Good — CSS modules (no runtime CSS-in-JS overhead). Bundle: ~60-100KB gzipped. |
| Security posture | Good — MIT-licensed, active security-advisory process, dependency audit via `npm audit`. Fewer historical CVEs than MUI (smaller attack surface, younger project). |
| Licence compatibility | MIT (fully free — all components, including data table). No paid tier. |
| Cost | Free. |
| Bundle/runtime cost | ~130-160KB gzipped from one dependency tree. Larger than Tailwind+TanStack, simpler dependency management than 8-package shadcn/ui assembly. |
| Operational fit (Arcanada) | Low — New component library in a Tailwind ecosystem. Same coherence concern as MUI, with a smaller community. |
| Escape velocity | Medium — Mantine components are library-specific (switching to MUI or shadcn requires rewriting all component usages). |

**Key risk:** Ecosystem coherence + smaller community than MUI — if Mantine's maintenance slows, the migration cost is identical to MUI's but the destination options are narrower.

### Trade-off Summary

The three options represent different points on the spectrum of **development velocity vs ecosystem coherence**. Option A (MUI) gives the best data-grid experience but introduces a paid tier and a new design language to the Arcanada ecosystem. Option B (Tailwind + TanStack Table, the incumbent) keeps ecosystem coherence but requires building data-grid UI from scratch — weeks of work for 5+ table views. Option C (Mantine) splits the difference: free data grid, one dependency tree, first-class dark mode — but still introduces a non-Tailwind library to the ecosystem with a smaller community than MUI.

The key differentiator is the **data-grid requirement**. If the dashboard has fewer than 5 complex table views, the incumbent (Option B) is the pragmatic choice — keep ecosystem coherence, accept the manual UI work. If the data-grid complexity is high, Option A (MUI) provides the best components but at a coherence cost. Option C (Mantine) is the compromise candidate.

### Recommendation

**Option A (MUI) for the admin dashboard, with the caveat that MUI X Pro is NOT purchased initially.** Start with the MIT core (which includes a capable table component); only evaluate MUI X Pro if the free table proves insufficient. The data-grid requirement (5+ complex table views) makes the manual UI work of Option B disproportionately expensive. Mantine (Option C) is a strong alternative — if the paid-tier concern around MUI is disqualifying, Mantine gives materially the same value with zero cost. Option B remains the default for all non-dashboard Control Arcana surfaces (landing page, public-facing pages) where Tailwind is the correct choice.

### Operator Decision

- [ ] Option A — React + MUI v6 + Emotion (Recommended for dashboard)
- [ ] Option B — React + Tailwind + TanStack Table (Incumbent — keep if data-grid complexity is low)
- [ ] Option C — React + Mantine 7 (Free alternative with first-class data table)
- [ ] Other (operator specifies)

---

## Assessment

**Before TUNE-0530:** The agent would have read "SPA / Dashboard: Vite, React or Vue, Tailwind" from the Required Stack table, concluded Tailwind is mandatory, and never surfaced MUI as an option. The operator would not know a choice existed.

**After TUNE-0530:** The Trigger Classifier fires ("more than 5 distinct table views with sorting, filtering, and inline editing" matches the "When to Reconsider" litmus test). The agent generates 3 candidates with 10-factor assessments. The operator sees explicit trade-offs and makes an informed choice.

**V-AC-8 satisfied.** The reworked mechanism surfaces the choice that the prescriptive old mechanism suppressed.

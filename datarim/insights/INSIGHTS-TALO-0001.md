---
task_id: TALO-0001
artifact: insights
schema_version: 1
research_mode: full
created_at: 2026-08-24T12:24:36Z
updated_at: 2026-08-24T12:24:36Z
status: complete
scope: frontend-design-knowledge-contract
language: en
---

# Research Insights: TALO-0001 Frontend Design Knowledge Contract

## Research question

What reusable Datarim-owned guidance and Knowledge Contract artifacts are
needed before implementing a bilingual, responsive, light/dark,
customer-facing website, and what evidence can prove that those artifacts and
the resulting product are useful rather than merely present?

This document is research-only. It does not create the `frontend-design`
skill, supporting artifacts, or product code. Product implementation remains
forbidden until the applicable Knowledge Contract is complete and validated as
`MET`.

## Method and scope

- Mode: Full research workflow.
- External research conducted: 2026-08-24.
- Source preference: normative standards first, then official implementation
  guidance and official open-source reference systems.
- Subjects: design-system process; information hierarchy; layout; typography;
  color and tokens; WCAG 2.2 and ARIA; responsive/touch behavior; i18n;
  performance and Core Web Vitals; browser and visual evidence; artifact
  identity, provenance, versions, lifecycle, relations; mutation-capable
  acceptance.
- Local reuse boundary reviewed: Datarim `frontend-ui`, `playwright-qa`, and
  `performance`. Those skills cover implementation hygiene and QA, but do not
  provide a substantive pre-code design-decision workflow.
- No third-party runtime endpoint or package was selected. Endpoint probes,
  migration research, package CVE research, and infrastructure sizing are not
  applicable to this research-only lane. They must be rerun if a later artifact
  introduces executable dependencies.

## Source register

All sources were accessed on **2026-08-24**. “Selected” means the future
Knowledge Contract should bind the relevant principle or verification method;
it does not mean importing another organization’s brand or code wholesale.

| ID | Authority and URL | Applicability | Selection |
|---|---|---|---|
| S01 | W3C, WCAG 2.2 Recommendation — https://www.w3.org/TR/WCAG22/ | Normative accessibility baseline, conformance and testable criteria | **Selected:** WCAG 2.2 Level AA is the minimum product baseline. **Rejected:** WCAG 2.1-only and automated-score-only claims. |
| S02 | W3C WAI, WCAG document map — https://www.w3.org/WAI/standards-guidelines/wcag/docs/ | Distinguishes normative requirements from informative understanding and techniques | **Selected:** bind normative criteria and cite techniques as implementation options. **Rejected:** treating an informative technique as the only valid implementation. |
| S03 | W3C WAI, ARIA Authoring Practices Guide — https://www.w3.org/WAI/ARIA/apg/ | Keyboard, semantics, names and widget behavior patterns | **Selected:** use for custom widgets after native HTML is insufficient. **Rejected:** treating APG examples as a production design system. |
| S04 | W3C WAI, APG introduction — https://www.w3.org/WAI/ARIA/apg/about/introduction/ | Explicitly states APG is informative and not production-ready code | **Selected:** preserve the normative/informative boundary. **Rejected:** copy-paste conformance by example. |
| S05 | W3C, Using ARIA — https://www.w3.org/TR/using-aria/ | Native HTML-first rule and safe ARIA use | **Selected:** semantic native element before custom role/state behavior. **Rejected:** recreating native controls with generic elements and ARIA. |
| S06 | W3C Design Tokens Community Group, stable Format Module 2025.10 — https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/ | Tool-neutral JSON token exchange, types, aliases and groups | **Selected:** interoperable token source with typed values and semantic aliases. **Rejected:** a design-tool-only or CSS-variable-only source of truth. |
| S07 | W3C Design Tokens Community Group — https://www.w3.org/community/design-tokens/ | Stable-spec status and implementation ecosystem | **Selected:** standard-backed interchange as the portability target. **Rejected:** assuming every named tool has complete or identical support. |
| S08 | W3C, CSS Color Adjustment Level 1 — https://www.w3.org/TR/css-color-adjust-1/ | `color-scheme`, forced colors and user preference interaction | **Selected:** declare supported schemes, honor preference, specify paired foreground/background tokens. **Rejected:** filter-based inversion or a single palette with unverified automatic transformation. |
| S09 | W3C WAI, language declarations — https://www.w3.org/International/questions/qa-html-language-declarations.html | Correct `lang`, BCP 47 tags and language changes | **Selected:** page and part language must be programmatically determinable. **Rejected:** language inference from encoding or visual text. |
| S10 | W3C Internationalization, quick tips — https://www.w3.org/International/quicktips/index | UTF-8, navigation, local formats, translatability and bidi | **Selected:** internationalization is structural, not a final string-replacement pass. **Rejected:** concatenated UI messages and flag-only language controls. |
| S11 | Unicode, LDML / CLDR — https://www.unicode.org/reports/tr35/ | Locale identifiers, dates, numbers, plural categories and formatting | **Selected:** platform `Intl` or CLDR-backed locale behavior. **Rejected:** handwritten Russian plural/date/number rules. |
| S12 | web.dev, responsive web design basics — https://web.dev/articles/responsive-web-design-basics | Viewport, fluid content, responsive media and touch-capable layouts | **Selected:** content-first adaptation and overflow prevention. **Rejected:** fixed-width desktop shrink-down. |
| S13 | GOV.UK Design System, layout — https://design-system.service.gov.uk/styles/layout/ | Small-screen-first reference, readable line length and device-independent breakpoints | **Selected:** start single-column, introduce layout changes where content requires them, cap readable measure. **Rejected:** device-name breakpoints as the design model. |
| S14 | GOV.UK Design System, type scale — https://design-system.service.gov.uk/styles/type-scale/ | Tested responsive type scale, relative units and vertical rhythm | **Selected:** limited relative type/line-height scale verified in both languages. **Rejected:** arbitrary per-component pixel sizes. |
| S15 | GOV.UK Design System, component contribution process — https://design-system.service.gov.uk/community/develop-a-component-or-pattern/ | Research-before-component and evidence-backed contribution lifecycle | **Selected:** reuse inventory, examples, prototype, user evidence, review. **Rejected:** promoting a one-page local pattern to a universal component without evidence. |
| S16 | U.S. Web Design System, design principles — https://designsystem.digital.gov/design-principles/ | Real user needs, accessibility, continuity and device coverage | **Selected:** user/task outcomes precede visual novelty; accessibility is a design constraint. **Rejected:** aesthetic consistency as a substitute for task success. |
| S17 | U.S. Web Design System, accessibility strategy — https://designsystem.digital.gov/documentation/accessibility/ | Automated plus keyboard, screen-reader, zoom, touch, cross-browser and manual testing | **Selected:** layered accessibility evidence. **Rejected:** a component library’s conformance as proof for the assembled page. |
| S18 | U.S. Web Design System, design tokens — https://designsystem.digital.gov/design-tokens/ | Discrete palettes for typography, spacing, color and communication | **Selected:** bounded token scales and role-based semantics. **Rejected:** unconstrained one-off values. |
| S19 | web.dev, current Core Web Vitals thresholds — https://web.dev/articles/defining-core-web-vitals-thresholds | Field thresholds: LCP, INP, CLS and 75th percentile | **Selected:** LCP <=2.5s, INP <=200ms, CLS <=0.1 at p75 as production goals. **Rejected:** one lab run or a composite score as field proof. |
| S20 | GoogleChrome, Lighthouse CI — https://github.com/GoogleChrome/lighthouse-ci | Repeatable lab audits, assertions, budgets and regression history | **Selected:** multiple repeatable lab runs with stored reports and explicit budgets. **Rejected:** a single volatile Lighthouse score. |
| S21 | GoogleChrome, Lighthouse variability guidance — https://github.com/GoogleChrome/lighthouse/blob/main/docs/variability.md | Explains environment variance and recommends repeated runs/aggregate values | **Selected:** stable runner and aggregate evidence. **Rejected:** comparing unrelated hosts or one-off local measurements. |
| S22 | Playwright, emulation — https://playwright.dev/docs/emulation | Viewport, device/touch, locale, timezone and color-scheme axes | **Selected:** explicit browser projects for every evidence cell. **Rejected:** resizing one desktop browser as complete mobile evidence. |
| S23 | Playwright, visual comparisons — https://playwright.dev/docs/test-snapshots | Deterministic screenshot baselines, diffs and environment sensitivity | **Selected:** named screenshots, fixed environment and narrow documented tolerances. **Rejected:** broad tolerance, unreviewed baseline replacement, or screenshots without assertions. |
| S24 | Playwright, accessibility testing — https://playwright.dev/docs/accessibility-testing | Axe integration and explicit automated-testing limitations | **Selected:** automated scan plus manual keyboard/semantic checks. **Rejected:** zero axe findings as full WCAG conformance. |
| S25 | JSON Schema, Draft 2020-12 — https://json-schema.org/draft/2020-12 | Machine validation and evolvable artifact envelopes | **Selected:** explicit schema version and fail-closed structural validation. **Rejected:** prose-only metadata conventions. |
| S26 | W3C, PROV-O — https://www.w3.org/TR/prov-o/ | Primary source, derivation, revision and attribution relations | **Selected:** minimal provenance relations such as primary source, derived-from, revision-of and attributed-to. **Rejected:** post-hoc unbound attribution. |
| S27 | Backstage Software Catalog, entity descriptor — https://backstage.io/docs/features/software-catalog/descriptor-format/ | Practical versioned envelope, owner, lifecycle and authoritative relations | **Selected as a pattern:** stable identity plus kind/apiVersion/spec/owner/lifecycle/relations. **Rejected:** importing Backstage itself or treating generated UID as stable external identity. |
| S28 | Backstage Software Catalog, catalog graph — https://backstage.io/docs/features/software-catalog/creating-the-catalog-graph/ | Relations as graph edges for ownership, dependencies and lifecycle | **Selected as a pattern:** machine-resolvable typed edges. **Rejected:** free-text “related to” lists. |
| S29 | Stryker, mutant states and metrics — https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/ | Killed, survived and no-coverage semantics | **Selected:** acceptance must demonstrate that wrong bindings and missing axes fail. **Rejected:** coverage or regex presence as proof that an assertion is sensitive. |

## Findings and decisions

### 1. The missing capability is pre-code frontend design, not another QA checklist

The existing Datarim `frontend-ui` skill is an implementation and closure
checklist. `playwright-qa` resolves a browser and stores one run’s evidence.
The current `performance` skill provides broad optimization reminders. None of
them requires a designer to turn customer intent into an information hierarchy,
visual direction, token system, responsive behavior model, and acceptance
matrix before code begins.

The new `frontend-design` skill should therefore own:

1. Evidence-based interpretation of the customer-visible problem.
2. Reuse-first audit of existing product and design-system artifacts.
3. Content architecture and priority before decoration.
4. Explicit visual direction with alternatives and reasons.
5. Semantic token and component-state contracts for light/dark themes.
6. Responsive behavior and interaction intent across input modes.
7. Bilingual parity and stress content before layout sign-off.
8. A design-ready acceptance matrix handed to implementation and QA.

It should route implementation hygiene to `frontend-ui`, browser capture to
`playwright-qa`, and measurable loading/runtime budgets to a strengthened
performance recipe. It must not duplicate those skills line by line.

### 2. Design starts with customer tasks and content hierarchy

USWDS and GOV.UK converge on starting from real user needs and tested existing
patterns. For this class of site, the design packet should identify, in order:

- the visitor and primary decision the page must support;
- the first-screen promise and evidence required to trust it;
- the ordered narrative or task path;
- primary and secondary actions, each with a visible outcome;
- content ownership and RU/EN semantic parity;
- essential states: default, hover, focus, active, disabled, loading, error,
  empty, success, and reduced-motion where applicable.

Selected: content outline and task flow precede high-fidelity styling. The
designer may create a strong first proposal without prior taste approval, but
must expose the rationale and the observable success criteria.

Rejected: mood-board-only delivery, aesthetics without content priority, and
customer acceptance inferred from an internal `done` status.

### 3. Use a constrained, semantic token system

The stable Design Tokens Format 2025.10 establishes a tool-neutral JSON shape.
USWDS demonstrates the value of limited scales and role-based tokens. A future
blueprint should define three layers where useful:

- **Primitive:** bounded raw palettes and scales, not consumed directly by
  product components unless justified.
- **Semantic:** `text-primary`, `surface-raised`, `border-focus`,
  `action-primary`, `status-danger`, spacing, type, radius, elevation and
  motion roles.
- **Component/state:** aliases only when a component needs a distinct contract,
  for example `button-primary-bg-hover`.

Every color role needs light and dark values, contrast evidence for its real
foreground/background pair, forced-colors behavior, and non-color semantics.
Typography needs font fallbacks containing both Latin and Cyrillic glyphs,
relative units, deliberate weights, line heights, and a bounded responsive
scale. Spacing should use a short consistent scale rather than arbitrary values.

Selected: a versioned token artifact with typed values, semantic aliases,
theme pairs and explicit consumers.

Rejected: hex values embedded throughout components, mechanically inverted
dark mode, theme validation against isolated swatches instead of rendered
states, and Figma variables as the only machine-readable source.

### 4. Accessibility is a normative product axis

WCAG 2.2 is the normative baseline. APG is useful implementation guidance but
explicitly is not a normative standard or production design system. The future
policy should require WCAG 2.2 Level AA across the complete page or flow, with
at least these design-time invariants:

- semantic HTML and logical document order before ARIA;
- keyboard reachability, visible focus, no keyboard trap, and predictable focus
  movement;
- text contrast at least 4.5:1 for normal text and 3:1 for large text;
- non-text contrast and state meaning that does not depend on color alone;
- reflow without information/function loss at 320 CSS px, except genuinely
  two-dimensional content allowed by WCAG;
- pointer target minimum 24x24 CSS px with WCAG exceptions; prefer 44x44 for
  primary standalone controls and touch-heavy navigation;
- meaningful headings, names, labels, alternative text and status messages;
- 200% text resize, WCAG text-spacing overrides, zoom and forced-colors checks;
- reduced-motion behavior and no essential information conveyed only by
  animation;
- page language and language changes programmatically determinable.

Evidence must combine automated scanning with keyboard, zoom/reflow,
screen-reader semantics, touch and human inspection. Automated scanners cannot
determine full WCAG conformance.

Selected: WCAG criterion IDs bound to acceptance criteria and evidence paths.

Rejected: “accessible component” inheritance, axe-only acceptance, Lighthouse
accessibility score as conformance, and ARIA added after visual completion.

### 5. Responsive behavior is content-driven and tested as a matrix

GOV.UK’s small-screen-first and readable-measure guidance is a stronger design
model than device-name breakpoints. The design should begin as a robust single
column, then introduce columns or persistent navigation only when content and
interaction remain usable. Text-heavy regions should generally remain below
roughly 75 characters per line.

The acceptance matrix required by the operator contains **12 cells per
customer-visible route/state**:

| Locale | Mobile | Tablet | Desktop |
|---|---|---|---|
| RU | light, dark | light, dark | light, dark |
| EN | light, dark | light, dark | light, dark |

The project may bind concrete viewports to its blueprint, but the reusable
default evidence set should include:

- mobile: 375x812, with an additional 320 CSS px reflow check;
- tablet: 768x1024 with touch enabled;
- desktop: 1440x900;
- full-page screenshot plus focused captures for dense/interactive sections;
- portrait as the default and landscape where interaction materially changes;
- overflow, overlap, clipping, focus, target size and sticky-element collision
  assertions, not screenshot presence alone.

Playwright can emulate viewport, touch, locale and color scheme. Emulation is
repeatable evidence, but high-risk touch interactions should also be verified
on at least one real device when the project environment permits it.

Selected: breakpoints emerge from observed layout failure and every matrix cell
has a deterministic artifact identity.

Rejected: desktop/tablet/mobile represented by one responsive browser resize,
one language standing in for both, or one theme standing in for both.

### 6. RU/EN parity is semantic, structural and behavioral

The site must use UTF-8, valid BCP 47 language tags, `lang` on each page and on
language-changing parts, and CLDR-backed formatting through platform `Intl` or
an equivalent maintained implementation. Russian plural categories and local
date/number conventions must not be handwritten.

Design stress fixtures should include:

- longest realistic Russian and English headings, navigation labels and CTAs;
- Russian plural forms for representative values such as 1, 2, 5, 21 and a
  fractional value where relevant;
- dates, decimal values, percentages and units;
- mixed Latin/Cyrillic proper names and long unbroken technical identifiers;
- missing-translation behavior that fails closed in tests rather than silently
  leaking the other locale.

Parity means both languages convey the same requirement and user outcome; it
does not require byte-for-byte identical copy length or forced identical line
breaks. The design should allow content expansion and keep language navigation
visible in the target language.

Selected: shared content schema/message keys plus explicit parity tests and
human content review.

Rejected: duplicated page markup as independent sources, concatenated messages,
hard-coded strings, flag-only language labels, and screenshot similarity as
translation proof.

### 7. Performance needs field goals and repeatable lab guardrails

Current Core Web Vitals field goals are:

- LCP <= 2.5 seconds at the 75th percentile;
- INP <= 200 milliseconds at the 75th percentile;
- CLS <= 0.1 at the 75th percentile.

These are field goals and should be segmented across mobile and desktop.
Pre-production Lighthouse runs are lab evidence, not a replacement for field
data. The future verification recipe should:

- record production build, route, runner, browser and throttling configuration;
- collect multiple runs in a stable environment and use an aggregate result;
- assert project-specific resource and metric budgets;
- preserve Lighthouse reports and tie them to the tested SHA;
- verify image dimensions/responsive sources, font strategy, critical rendering,
  script cost and layout stability;
- add real-user measurement when sufficient traffic exists.

Selected: Core Web Vitals thresholds plus explicit resource budgets determined
from the actual site baseline and customer-critical route.

Rejected: a universal Lighthouse score threshold without raw metrics, one run,
or comparing reports from different runner environments as a regression gate.

### 8. Visual evidence must be reproducible and meaning-bearing

Playwright visual comparison is useful only when the browser, OS, fonts,
viewport, locale, theme, data and animations are controlled. The evidence
recipe should require:

- a stable production-like build and deterministic fixture state;
- exact route, deployed/source SHA, locale, viewport, touch mode, theme,
  browser/version and capture timestamp in metadata;
- deterministic font readiness and disabled/reduced non-essential animations;
- explicit masking only for truly nondeterministic content, with each mask
  documented;
- narrow diff tolerances justified by rendering variance;
- accessible-name, interaction, console-error and overflow assertions next to
  visual comparison;
- actual/expected/diff artifacts on failure;
- baseline updates reviewed as product changes, never automatically accepted.

The screenshot matrix proves observable coverage. It does not prove aesthetic
approval, translation correctness, or customer disposition by itself.

Selected: automated diff plus structured human-readable evidence metadata.

Rejected: generic `screenshot.png`, capture without assertions, broad pixel
tolerance, and replacing the baseline merely to make CI green.

### 9. Knowledge artifacts need identity, provenance, lifecycle and typed edges

Backstage provides a practical reference for a versioned envelope and typed
relations; W3C PROV provides standard provenance semantics. Datarim should use
its own schema, not install Backstage or require RDF. The useful transferable
properties are:

- stable `K_id` independent of a mutable filename or generated database UID;
- artifact `kind`, schema/api version, artifact revision and status/lifecycle;
- accountable owner and maintainer;
- content digest and source commit;
- created/reviewed/deprecated timestamps;
- `hadPrimarySource`, `wasDerivedFrom`, `wasRevisionOf`, `wasAttributedTo`
  equivalents with resolvable target IDs;
- typed dependency and consumer relations;
- supersession/deprecation path that does not erase earlier evidence;
- validation state and evidence references;
- requirement bindings pinned before implementation.

The authoritative graph edge should be machine-resolvable and validated from
both ends where inverse relations are required. Free-text references may
explain a relation but cannot create it.

Selected: compact Datarim-native envelope validated with JSON Schema or the
repository’s canonical schema mechanism, stored in version control.

Rejected: post-hoc attribution, unversioned “latest” bindings, filenames as the
only identity, mutable replacement of historical revisions, and a prose list of
related artifacts.

### 10. Acceptance must be mutation-capable, not presence-based

Stryker’s killed/survived distinction is directly applicable even when the
artifact validator is implemented in shell or another language: an acceptance
test is credible only if an intentionally wrong condition makes it fail.

The Knowledge Contract verification recipe should independently mutate at
least these boundaries:

1. Remove a required artifact binding.
2. Replace a pinned revision with an unbound or nonexistent revision.
3. Introduce an artifact after the implementation timestamp.
4. Remove a primary-source or revision relation.
5. Change the artifact lifecycle to deprecated/rejected.
6. Remove one required locale.
7. Remove one required viewport class.
8. Remove one theme from the evidence matrix.
9. Replace a WCAG criterion binding with prose only.
10. Remove one implementation or live-evidence edge.
11. Accept an empty evidence path or a screenshot without SHA metadata.
12. Loosen a performance/accessibility threshold beyond the policy.

Every mutant must produce a named RED result attributable to the mutated
boundary, followed by GREEN after restoration. A single global mutant cannot
prove every independently claimed relation. Timeouts, skipped cases and no
coverage must not be reported as killed unless the local gate explicitly and
justifiably defines that semantic.

Selected: exact-boundary mutation catalog with preserved RED/GREEN logs.

Rejected: grep-for-heading tests, schema-valid-but-unbound artifacts, aggregate
coverage without task IDs, and one mutation used to claim all relationships.

## Reference implementation synthesis

| Reference | Reusable lesson | Do not copy |
|---|---|---|
| USWDS | Treat accessibility and real user needs as design inputs; use bounded role-based tokens; combine automated and manual verification. | Federal brand, legal framing, or components without project-context testing. |
| GOV.UK Design System | Small-screen-first content layout, readable measure, responsive type/spacing scales, research-backed component lifecycle. | GOV.UK brand language or a rigid two-thirds layout for every content type. |
| WAI APG | Keyboard and semantic behavior for custom widgets, with explicit accessible names and states. | Examples as a production component library or as normative conformance. |
| Playwright | Deterministic axis emulation, interaction assertions and reproducible visual diffs. | One screenshot per run, automatic baseline acceptance, or emulation as proof of every real-device behavior. |
| Lighthouse CI | Repeatable lab measurements, budgets, assertions and stored regression history. | Composite score as field performance or one volatile run. |
| Backstage catalog | Versioned envelopes, ownership, lifecycle and authoritative typed relations. | Backstage runtime, its exact entity kinds, or generated UID semantics. |
| PROV-O | Clear source, derivation, revision and attribution relation vocabulary. | Full RDF/OWL complexity when a smaller Datarim schema is sufficient. |
| Stryker | Killed/survived/no-coverage mental model for testing the tests. | Tool lock-in or mutation score without review of surviving/equivalent mutants. |

## Required future Knowledge Contract artifact set

Research indicates that a complete pre-code contract for this product class
needs the following reusable artifacts. Names and schemas are proposals for the
artifact-creation lane, not artifacts created by this document.

| Kind | Required content | Key evidence |
|---|---|---|
| Role | Frontend designer authority, responsibilities, hand-offs and boundaries | Independent role-resolution test; cannot silently become developer or approver |
| Competency profile | Content hierarchy, visual systems, typography/color, responsive interaction, accessibility, i18n, performance-aware design, evidence literacy | Scenario evaluation across all competencies |
| Skill | `frontend-design` pre-code workflow and routing to existing skills | Forward tests on realistic bilingual design requests |
| Blueprint | Bilingual responsive customer-site design packet | Valid example plus missing-section mutations |
| Token template | Primitive/semantic/component tokens, light/dark pairs, state coverage and consumer bindings | Schema validation, contrast checks and alias integrity |
| Accessibility policy | WCAG 2.2 AA scope, normative criterion bindings and manual/automated evidence | Criterion-level checks and false-positive mutants |
| i18n constraint | UTF-8, BCP 47, language parity, CLDR-backed formats and stress fixtures | RU/EN fixture suite and missing-key RED |
| Responsive constraint | Content-driven breakpoints, 320px reflow, touch/keyboard parity and 12-cell matrix | Browser matrix coverage and overflow mutations |
| Performance policy | CWV field goals, lab methodology and route/resource budgets | Multi-run reports tied to SHA and threshold mutants |
| Visual evidence recipe | Deterministic environment, metadata, screenshots, diffs, interactions and storage | Missing-axis/metadata/baseline mutations |
| Success criteria | Visitor-visible, production-observable outcomes linked to atomic requirements | Requirement-to-AC-to-live-evidence graph validation |
| Knowledge Contract manifest | `K_id`, revisions, pre-work timestamps, bindings, lifecycle, provenance, relations and validator evidence | Fail-closed schema/graph gate and independent forward review |

## Proposed forward-test corpus for the artifact lane

The future `frontend-design` skill should be evaluated by an independent agent
using only the skill and minimum raw request context. The evaluator must not be
given the intended answer or this document’s conclusions.

1. **Positive, constrained site wave:** bilingual technical landing page with
   known brand assets, three viewports, two themes and measurable live goals.
   Expected behavior: reuse inventory, content hierarchy, alternatives, token
   and interaction contracts, complete evidence plan; no product code.
2. **Sparse visual brief:** “make it look excellent” with customer remarks but
   no taste approval. Expected: a defensible first design direction and
   rationale, not a routine approval pause.
3. **Existing design-system conflict:** project tokens/components already
   exist. Expected: reuse and extend without replacing brand conventions.
4. **Accessibility conflict:** requested treatment fails contrast or keyboard
   behavior. Expected: preserve intent through an accessible alternative and
   record the constraint.
5. **Long Russian content:** English mockup fits, Russian stress content does
   not. Expected: redesign the layout; never shrink critical text below policy.
6. **Evidence gap:** screenshots exist but one locale/theme/viewport is absent.
   Expected: Knowledge Contract remains not MET.
7. **Post-hoc binding attempt:** implementation predates the claimed skill or
   uses an unpinned latest revision. Expected: reject as Unbound.
8. **Backend-only request:** expected: do not invoke `frontend-design`.

## Risks and compatibility notes

- **Standards evolution:** bind explicit standard and artifact revisions. WCAG
  and the Design Tokens format can evolve; “latest” must not silently change a
  historical contract.
- **Token tooling variance:** 2025.10 is stable, but tool support may differ.
  Keep the canonical file standard-conformant and validate actual consumers.
- **Visual nondeterminism:** fonts, browser/OS versions, GPU and animations can
  create false diffs. Pin the capture environment and preserve its metadata.
- **Lab/field mismatch:** Lighthouse is diagnostic lab evidence. Production RUM
  is needed for p75 Core Web Vitals claims when traffic permits.
- **Automated accessibility limits:** automated tools find only a subset of
  issues. The policy must preserve manual and assistive-technology checks.
- **Localization parity:** equal message keys do not prove equal meaning. Pair
  structural checks with bilingual human/content review.
- **Artifact bloat:** progressive disclosure is required. Keep the skill’s
  routing and essential invariants concise; move detailed recipes and schemas
  into references, scripts and templates only when they materially improve
  execution.
- **Framework overreach:** the reusable skill must preserve project brand,
  stack and operator scope. It should establish decision criteria, not impose
  GOV.UK, USWDS or another external visual language.

## Research conclusion

A substantive Datarim `frontend-design` skill is justified because the current
skills start too late: they verify code and browser output but do not require a
designer-owned, evidence-backed design contract before implementation. The new
capability should be a short pre-code orchestrator with progressively disclosed
references for design decisions, tokens, accessibility/i18n/responsiveness,
performance and evidence. Its output must bind to a versioned Knowledge
Contract before product code begins.

The selected verification model is deliberately layered: normative WCAG 2.2
AA; semantic/native implementation guidance; RU/EN content parity; a 12-cell
viewport/theme/locale visual matrix; repeatable browser assertions; field Core
Web Vitals goals plus lab budgets; versioned provenance and typed relations;
and independent mutations that force each claimed boundary RED. Tools, docs,
tests or screenshots alone remain insufficient for a customer-visible outcome.

## Research cost ledger

- Research date: 2026-08-24.
- External source records: 29.
- Link verification: 29/29 source URLs returned HTTP 200 on 2026-08-24.
- Primary/official domains represented: W3C/WAI, Unicode Consortium, web.dev /
  Chrome, Playwright, GOV.UK Design System, USWDS, JSON Schema, Backstage and
  Stryker.
- Runtime/package dependencies added: none.
- Product code changed: none.
- Reusable artifacts created: none; this INSIGHTS record is the research input
  to the separate artifact-creation lane.

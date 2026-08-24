---
task_id: TALO-0001
artifact: insights
schema_version: 1
research_mode: full
created_at: 2026-08-24T12:24:36Z
updated_at: 2026-08-24T17:55:23Z
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
- Reuse-first boundary reviewed at exact remote heads: Datarim customer-
  delivery and review-evolution canon, templates, validators, agents and
  frontend skills; Talomnia's authority-controlled knowledge graph and
  TALO-0008/TALO-0028 evidence; and the Talomnia site design, i18n and browser
  verification surfaces. The exact inventory and dispositions follow the
  source register.
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

The navigation URLs and access date above remain the human-readable research
record. Mutable selected implementations S20–S24 and S27–S29 are additionally
pinned in `TALO-0001-research-authority-audit.json` by repository, immutable
40-character commit, path, Git blob, and SHA-256 content digest. The immutable
GitHub URL for each pin contains that commit. The audit validator recomputes
both the blob identity and content digest from the captured source bytes;
`main`, `master`, `develop`, `current`, and a navigation URL alone are never
accepted as immutable identity.

## Reuse-first inventory at exact remote heads

The inventory was read from the remote-tracking commits below, not inferred
from task status or mutable branch names:

| Repository | Exact `origin/main` read | Scope inspected |
|---|---|---|
| Datarim | `a58e1a28454ab35cba26a8df71d4794662b0d339` | customer-delivery/review-evolution canon, templates, gates, agents and skills |
| Talomnia knowledge | `c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae` | ontology, authority events, revisions, receipts and TALO ledgers |
| Talomnia site | `20f58029b1e81a093938e4795ed9d8b6f3ff0ed8` | design/i18n/browser gates and dependency lock |

### Authoritative R1/R2 item audit

The customer-side Revision 1 and Revision 2 reviews are Tier 2 sources under
the TALO-0001 authority model. They decompose and clarify Tier 1 operator
requirements; they cannot weaken, replace or close Tier 1. This audit selects
all 66 items as delivery inputs. No item is rejected. `Direct` means the item
must shape the reusable frontend-design Knowledge Contract; `cross-functional`
means it remains in the atomic product/content/governance ledger without being
misrepresented as a standalone design rule; `human boundary` preserves the
source's explicit acceptance authority. A mapping below is a pinned planning
disposition, never evidence that the visitor-facing finding has been delivered.

The primary item text is pinned to Talomnia knowledge snapshot
`c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae`:

| Review | Primary source | Git blob | Items | Decision |
|---|---|---|---:|---|
| R1 | `research/sources/talo-0033/issue-42-review-r1.md` | `aa584b0f768d7d52d511ae0e1924201f79c3216c` | 28 | changes requested |
| R2 | `research/sources/talo-0033/issue-44-review-r2.md` | `97493085aaccdc50e96b32b3112b4e2ca3c23833` | 38 | changes requested; R1 remains in force |

The complete item bodies, measurements, required changes and acceptance text
remain verbatim in those blobs. The rows below reproduce each item heading
verbatim and bind it to the authoritative executor disposition. This prevents a
short summary from silently dropping an item while avoiding a second mutable
copy of each full review body.

#### Revision 1 item coverage

The mapping source is `research/sources/talo-0033/issue-42-executor-intake.md`
(blob `192c57a5f7c183471b37295790996e1e7fd1e88c`) and its published executor record,
[issue #42 comment 5347868439](https://github.com/Arcanada-one/talomnia-trace/issues/42#issuecomment-5347868439),
canonical body `sha256:2ab1b52a22494f96ceef299a1f776c87879dcace99de60bea377924217f7a1f7`,
accessed 2026-08-24.

| Item | Verbatim item heading | Pinned disposition and delivery mapping | KC research selection |
|---|---|---|---|
| R1-01 | Workforce sells internal capabilities instead of professional work | Taken -> `TALO-0033` | Direct: customer-task hierarchy |
| R1-02 | The commercial surfaces have no data behind them | Taken -> `TALO-0034` | Cross-functional: offer data and intent |
| R1-03 | The mandatory Market Research is not published | Taken -> `TALO-0035` | Cross-functional: publication/projection |
| R1-04 | Workflow pages are readable by engineers, not by humans | Taken -> `TALO-0036` | Direct: progressive evidence hierarchy |
| R1-05 | The Workflow number carries no economic meaning | Taken -> `TALO-0036` | Direct: honest evidence presentation |
| R1-06 | The home page must explain the product faster. | Taken -> `TALO-0037` | Direct: comprehension-first hierarchy |
| R1-07 | Separate the three levels of communication. | Taken -> `TALO-0037` plus Workforce enforcement in `TALO-0033` | Direct: customer/product/technology order |
| R1-08 | Capability Atlas needs an overview mode. | Taken -> `TALO-0039` | Direct: overview before detail |
| R1-09 | Capability Atlas needs search. | Taken -> `TALO-0040` | Direct: findability and filtering |
| R1-10 | Atlas cards must be much shorter. | Taken -> `TALO-0039` | Direct: bounded card density |
| R1-11 | Show the graph, at least minimally. | Taken -> `TALO-0040` | Direct: relationship visualization |
| R1-12 | Make Workflows the primary evidentiary product section. | Taken -> `TALO-0036` | Direct: evidence-led information architecture |
| R1-13 | Publish the site launch itself as a Workflow. | Taken -> `TALO-0041` | Cross-functional: case-study content |
| R1-14 | Market Research must be both Research and Workflow, without duplicated data. | Taken -> `TALO-0035` | Direct: reciprocal information architecture |
| R1-15 | Investor Room reads as a status page. | Taken -> `TALO-0044` | Direct: investor narrative hierarchy |
| R1-16 | Publish the White Paper as HTML. | Taken -> `TALO-0043` | Cross-functional: document publication |
| R1-17 | Produce the Pitch Deck. | Argued dependency deferral -> `TALO-0046` | Cross-functional: content dependency preserved |
| R1-18 | Add Founder / Why us. | Argued identity-source deferral -> `TALO-0045` | Cross-functional: no fabricated identity facts |
| R1-19 | Reduce internal jargon on customer-facing pages. | Taken -> `TALO-0038` | Direct: plain-language ordering |
| R1-20 | Stop mixing Russian prose with English technical vocabulary without need. | Taken -> `TALO-0038` | Direct: bilingual terminology rule |
| R1-21 | Explain Evidence with one concrete example. | Taken -> `TALO-0038` | Direct: example before abstraction |
| R1-22 | Explain Knowledge Contract in plain language before the architecture. | Taken -> `TALO-0038` | Direct: plain-language explanation |
| R1-23 | Every main page needs a contextual CTA. | Taken -> `TALO-0042` | Direct: contextual conversion |
| R1-24 | The contact form must carry the intent it was reached from. | Taken -> `TALO-0042` | Direct: interaction-state continuity |
| R1-25 | Add investor and co-founder intents. | Taken -> `TALO-0042` | Direct: intent taxonomy |
| R1-26 | A human visual review is required before final acceptance. | Planned-not-closed -> `TALO-0049` | Human boundary: screenshot evidence cannot self-accept aesthetics |
| R1-27 | Reduce density on technical pages. | Taken -> `TALO-0048` | Direct: progressive disclosure |
| R1-28 | Give Evidence a visual language. | Taken -> `TALO-0047` | Direct: reusable evidence component |

#### Revision 2 item coverage

The mapping source is the published executor disposition,
[issue #44 comment 5347971637](https://github.com/Arcanada-one/talomnia-trace/issues/44#issuecomment-5347971637),
canonical body `sha256:72abdc0ebe135fc9d33967501032cf63f7dd4c53e23d3385d2ea31b2c10b815f`,
accessed 2026-08-24. `Fold` retains the named R1 requirement and adds only the
R2 delta; it does not replace the R1 item.

| Item | Verbatim item heading | Pinned disposition and delivery mapping | KC research selection |
|---|---|---|---|
| R2-01 | Remove the unapproved refund promise (§15.5 violation). | Taken, new -> `TALO-0051` | Cross-functional: commercial-policy constraint |
| R2-02 | Publish the existing market research (extends R1-03, now much cheaper). | Fold -> `TALO-0035` | Cross-functional: publication/projection |
| R2-03 | Pricing cards must exist as data (same as R1-02). | Fold -> `TALO-0034`; intent preselection also `TALO-0042` | Cross-functional: offer data and intent |
| R2-04 | Resolve the Evidence Gate circularity. | Taken, new -> `TALO-0052` | Direct: non-contradictory availability copy |
| R2-05 | Workforce must sell work, not internals (same as R1-01). | Fold -> `TALO-0033` | Direct: service deliverables before internals |
| R2-06 | Split Workflow 0 from the launch epic, and correct the statuses. | Fold and rescope -> `TALO-0041` | Direct: truthful scope/status presentation |
| R2-07 | Investor Room has no documents (extends R1-16, R1-17). | Fold -> `TALO-0043`, `TALO-0046` | Cross-functional: document dependency |
| R2-08 | Separate measured from estimated in every total. | Fold -> `TALO-0036` | Direct: evidence-state semantics |
| R2-09 | Explain what 12.1h means. | Fold -> `TALO-0036` | Direct: accounting-method presentation |
| R2-10 | Show knowledge-production cost separately from execution cost. | Fold -> `TALO-0036` | Direct: cost-category hierarchy |
| R2-11 | Surface the negative case: "the system stopped itself." | Taken, new -> `TALO-0054` | Direct: failure evidence without status laundering |
| R2-12 | Every workflow shows failures, rework, gaps discovered, contracts evolved. | Fold -> `TALO-0036` | Direct: complete evidence narrative |
| R2-13 | Cost and time visualisation. | Taken, new -> `TALO-0053` | Direct: evidence visualization |
| R2-14 | Home: state what can be given to Talomnia now | Fold -> `TALO-0037` | Direct: concrete deliverables |
| R2-15 | Home: lead with one real workflow rather than counters. | Fold -> `TALO-0037` | Direct: proof-led home hierarchy |
| R2-16 | The Research 0 counter works against the project | No separate task; resolved by `TALO-0035` dependency | Direct: avoid misleading empty-state emphasis |
| R2-17 | Atlas search | Fold -> `TALO-0040` | Direct: search facets |
| R2-18 | Atlas detail pages start with the human question, not the identifier | Fold -> `TALO-0039` | Direct: human-first detail hierarchy |
| R2-19 | Atlas cards show clickable usage evidence | Fold -> `TALO-0040` | Direct: actionable evidence links |
| R2-20 | Make created-for-Talomnia vs reused-from-Arcanada/Datarim vs evolved-during-execution visually plain | Fold -> `TALO-0039` | Direct: provenance visual semantics |
| R2-21 | Knowledge Contract: show a small human example before Resolver and Receipt | Fold -> `TALO-0038` | Direct: example before internals |
| R2-22 | How it works needs one end-to-end example | Fold -> `TALO-0038` | Direct: end-to-end explanatory narrative |
| R2-23 | Ecosystem page is too thin for its role | Taken, new -> `TALO-0055` | Direct: product/technology/research layer map |
| R2-24 | Investor Room needs a compact narrative before the deck | Fold -> `TALO-0044`, `TALO-0045` | Direct: compact investor journey |
| R2-25 | Add a distinct investor intent | Fold -> `TALO-0042` | Direct: intent taxonomy |
| R2-26 | Intent-carrying forms | Fold -> `TALO-0042` | Direct: interaction-state continuity |
| R2-27 | Verify the honeypot field is properly hidden | Measured; regression assertion -> `TALO-0042` | Direct: accessible hidden-control behavior |
| R2-28 | Publish a short glossary on the site | Taken, new -> `TALO-0056` | Direct: terminology support |
| R2-29 | One stated rule for Russian/English mixing | Fold -> `TALO-0038` | Direct: bilingual terminology rule |
| R2-30 | RU/EN parity is now a regression gate, not an aspiration. | Standing constraint -> all subtasks | Direct: i18n parity gate |
| R2-31 | Three-level information architecture: | Fold -> `TALO-0037` | Direct: Understand -> Believe -> Verify hierarchy |
| R2-32 | Internal slugs must not serve as product copy | Fold; verified by `TALO-0048` | Direct: human labels before identifiers |
| R2-33 | Card density: one to three sentences | Fold -> `TALO-0048`; Atlas implementation in `TALO-0039` | Direct: bounded card density |
| R2-34 | Progressive disclosure for raw ledger, artifact matrix, resolution details, provenance, revision metadata | Fold -> `TALO-0048` | Direct: collapse, never delete evidence |
| R2-35 | Diagrams where prose now stands | Taken, new -> `TALO-0057` | Direct: diagram selection and verification |
| R2-36 | Each workflow gets a case-study identity | Fold -> `TALO-0036` | Direct: workflow case-study pattern |
| R2-37 | The legal draft status should not dominate every page. | Taken, new -> `TALO-0058` | Direct: accurate status placement |
| R2-38 | Deduplicate the honesty disclaimer into a reusable status component | Fold -> `TALO-0058` | Direct: reusable status component |

#### Derived planning and reusable-artifact identities

These records prove how the primary reviews were ingested and resolved. They
do not replace the 66 primary rows above and cannot be used to infer customer
acceptance or product delivery.

| Derived record | Exact identity at the pinned snapshot | Boundary |
|---|---|---|
| TALO-0032 R1 planning contract | `K_id sha256:31ab3f467f12afc943d2f977dabc6ea8eb32675453ebe066e8df08b8b1b8cf3c`; `R_id sha256:31ec464ee27fc6079169300a5313697390701a78c9b14beef7bb824875e416f6`; `I_id sha256:48d580be951d458c2bdbf4704c4926e8331c6e380dd3824b9e622d92a405a642` | Planning-only; contract body requires all 28 findings to be dispositioned |
| TALO-0050 R2 planning contract | `K_id sha256:0b3910acfe1fa56758f91d61fec32377574d23b2519dc38acb18f594d0af379d`; `R_id sha256:a996b7f0c7130f7508ba07c8d4ae3c8e2c841947e290f0fceb22fc3e7798679a`; `I_id sha256:f14cde136e75d7b5c481cf1e942e8e05dea7c35b2560ac1e708013856276cc59` | Planning-only; contract preserves R1, overlap folding and no evidence reduction |
| `tal-skill-customer-narrative@r1` | `content_digest sha256:ecdffb0f3c1407858d0cc474ddf58d2c1e9bd88688f77b32076034f0b6a35cb5` | Derived from R1/R2 research for narrative execution; it covers named slices, not the complete reviews |

The R1/R2 sources therefore remain selected as authoritative Tier 2 inputs in
their entirety. The contracts, envelopes, task mappings and narrative skill are
useful derived evidence, but none may silently narrow the source reviews or be
treated as a customer disposition.

#### Digest and audit replay contract

`github-json-body-utf8-no-extra-lf/1` means: parse the GitHub API JSON response,
take the JSON `body` string, encode that string exactly as UTF-8, and SHA-256
those bytes without appending a line feed. A line feed already present in the
JSON string remains part of the body. Rendering the value through a command
that adds another terminal line feed is a different representation and must
not reuse the canonical-body label. This distinction explains the rejected
rendered digests `13632ed476d6aec738e7bdc16b08f47d42707186a8a0d5a56e873b4d4575333b`
and `e959472939f0c81c73636b7a397b8988864696bc565e68d308aa15b46e98f6b1`.

The machine-readable audit and `dev-tools/check-research-authority-audit.py`
jointly verify the 66-row source-to-heading bijection, exact mapping and
applicability table digest, source paths and Git blobs, derived identities,
candidate path/revision/digest and latest `approve` event, declared-English
item surface, canonical comment bodies, and immutable external-source pins.
The companion Bats suite independently mutates omission, duplication, heading,
mapping, source path/blob, candidate identity/digest/authority, language,
comment newline representation, and external commit/blob/content boundaries.

### Canonical ontology boundary

`ontology/schemas/knowledge-contract.schema.json` defines exactly seven
managed kinds. Primary selections are `Role`, `Skill`, and `Blueprint`;
governance selections are `Constraint`, `SuccessCriterion`, `Policy`, and
`CapabilityDescription`. `CapabilityDescription` is therefore required in the
gap analysis. `Competency` is not a managed primitive and must not be invented
as an eighth kind. Competency-shaped needs are expressed through a
`CapabilityDescription`, the `provides` claims of selected artifacts, and
their pinned dependency closure.

Every reusable selection below remains conditional on an issued contract that
pins both `revision_id` and `content_digest`. An approved graph revision is a
candidate, not retrospective proof that an earlier task used it.

### Datarim canon and operational projections

| Disposition | Existing path(s) | Applicability and boundary |
|---|---|---|
| **Reuse** | `skills/customer-delivery/SKILL.md`; `config/customer-requirement.schema.json`; `config/customer-delivery-receipt.schema.json` | Atomic remark-to-requirement-to-production-AC mapping and delivery receipt. These govern customer-visible closure; tools/docs/tests alone cannot close it. |
| **Reuse** | `config/review-evolution.schema.json`; `templates/review-evolution-template.yaml`; `dev-tools/check-review-evolution.sh`; `dev-tools/tests/check-review-evolution.bats` | Review-to-evolution disposition and validation. Bind the reviewed implementation to its forward reusable change or explicit no-change result. |
| **Reuse** | `templates/customer-requirements-template.yaml`; `templates/customer-delivery-receipt-template.yaml`; `templates/insights-template.md` | Canonical requirement, receipt and research starting shapes; specialize through schema-valid fields, not parallel ad hoc formats. |
| **Reuse** | `dev-tools/check-customer-delivery.sh`; customer-delivery schema and mutation suites under `dev-tools/tests/` and `tests/` | Deterministic and mutation-sensitive receipt verification. These are evidence mechanisms, not customer-visible fulfillment. |
| **Modify/project** | `agents/researcher.md` plus the Talomnia `tal-role-design-lead@r4` selection | Researcher already exists as an agent; the approved design role exists in the knowledge graph. Add only the missing Datarim execution projection/binding needed by the contract. There is no `config/roles/` designer or researcher registry at this head. |
| **Create** | no `skills/frontend-design/` path exists | A substantive Datarim-owned pre-code `frontend-design` skill is the central missing reusable artifact. It must route to, rather than duplicate, existing implementation and QA skills. |

### Approved Talomnia candidates

`approved` below means the latest authority event for that exact revision and
digest is `approve`. Relations summarize pinned dependencies or declared graph
edges relevant to this wave. Full digests are retained so a later contract can
select without a mutable-name lookup.

| Disposition | Kind; path | Exact revision and digest | Lifecycle; relevant relations |
|---|---|---|---|
| **Reuse** | Role; `graph/data/local/tal-role-design-lead@r4.json` | `tal-role-design-lead@r4`; `sha256:846f1da87895f136f8594586ff8ae24c362dd3020a8542ec29d9fbdebc98ce8c` | approved 2026-08-20; uses design-research@r3, theming-anti-fouc@r3 and honesty-presentation@r2; predecessor r3 |
| **Reuse** | Role; `graph/data/local/tal-role-knowledge-curator@r2.json` | `tal-role-knowledge-curator@r2`; `sha256:3ee16a52b8baa517b24fd3d56e54a624f34d891809fb09c8e8038fbcb8c78078` | approved 2026-08-19; predecessor r1; use for lifecycle/provenance custody |
| **Reuse** | Role; `graph/data/local/tal-role-evidence-auditor@r2.json` | `tal-role-evidence-auditor@r2`; `sha256:f7677f8a2b6d8fea8182a6d50e09de930af64be5f6ee0c2b16461ba0654cfac5` | approved 2026-08-19; predecessor r1; use for independent evidence review |
| **Reuse** | Role; `graph/data/local/tal-role-deployment-operator@r2.json` | `tal-role-deployment-operator@r2`; `sha256:422083673c8de8626a993efda3ef1f9b42a7979a1fbe0f0c82e399ed25ca47a8` | approved 2026-08-19; depends on deployment skills and sanitized-projection@r1; predecessor r1 |
| **Reuse** | Skill; `graph/data/local/tal-skill-design-research@r3.json` | `tal-skill-design-research@r3`; `sha256:35d993fba2af939f11cd1f17dc704f8a69f26775c4e4eae5fd15c19fadb3bd61` | approved 2026-08-19; predecessor r2; feeds design-lead and design-system blueprint |
| **Modify** | Skill; `graph/data/datarim/datarim-skill-frontend-ui@r2.json` | `datarim-skill-frontend-ui@r2`; `sha256:2041e05aad7da1e8e1018f32adc3e343f740f4ea96a686e88de2c42bb64b718c` | approved 2026-08-19; predecessor r1; keep as implementation checklist and add no pre-code design authority |
| **Modify** | Skill; `graph/data/datarim/datarim-skill-playwright-qa@r2.json` | `datarim-skill-playwright-qa@r2`; `sha256:716b8dcca722330010f580532d2c36694f7b48c3e7375d01bc4defe79663269d` | approved 2026-08-19; predecessor r1; extend or pair with a unified 12-cell evidence recipe |
| **Reuse** | Skill; `graph/data/local/tal-skill-theming-anti-fouc@r3.json` | `tal-skill-theming-anti-fouc@r3`; `sha256:8345cb3b535c4615dfd78be1116c17d6a0949918f65108250b32b83ceef2a400` | approved 2026-08-20; depends on style-guide@r3; predecessor r2 |
| **Reuse when applicable** | Skill; `graph/data/local/tal-skill-graph-neighbor-visualization@r1.json` | `tal-skill-graph-neighbor-visualization@r1`; `sha256:4ab784b3750853a7ee611330b9457b3f5ec07c02579edb996a4b59b2dda145b4` | approved 2026-08-19; provides `skill.graph-neighbor-visualization`; only graph-bearing page work should bind it |
| **Reuse** | Skill; `graph/data/local/tal-skill-success-criterion-measurement@r2.json` | `tal-skill-success-criterion-measurement@r2`; `sha256:c1142ce770b875b936b03b7dc58bb49a5ec952c47beaafdf09f2ffd82f9907b4` | approved 2026-08-19; predecessor r1; binds measurements to success criteria |
| **Reuse** | Blueprint; `graph/data/local/tal-blueprint-design-system-atlas@r4.json` | `tal-blueprint-design-system-atlas@r4`; `sha256:32bf46a553a3deaed9a3999d77e3e79908cbb9f571cbfbbc9d8d77b6781dcf8e` | approved 2026-08-20; depends on design-research@r3, design-lead@r3 and honesty-presentation@r2; predecessor r3 |
| **Reuse** | Blueprint; `graph/data/local/tal-blueprint-component-library@r4.json` | `tal-blueprint-component-library@r4`; `sha256:87d0a35d6ce59ae2c37e0d007f16fb38ad3abe759a3b56d25bc65b48ed938e6b` | approved 2026-08-20; depends on style-guide@r4, theming-anti-fouc@r3 and design-concept@r3; predecessor r3 |
| **Modify** | Blueprint; `graph/data/local/tal-blueprint-evidence-bearing-verification@r2.json` | `tal-blueprint-evidence-bearing-verification@r2`; `sha256:30236909268f9d1a188da61ce2b9b54db0b86b4d34660cc63720fc32d05796f1` | approved 2026-08-19; depends on evidence-auditor@r1 and success-criterion-measurement@r1; add or compose the tablet-inclusive browser matrix without rewriting history |
| **Reuse** | Constraint; `graph/data/local/tal-constraint-style-guide@r4.json` | `tal-constraint-style-guide@r4`; `sha256:8207f39ec69afde69a229e761f49f6d88d22e6ece30c3b8210e4c96770ed86c6` | approved 2026-08-20; depends on design-concept@r3; predecessor r3 |
| **Reuse** | Constraint; `ontology/lifted/tal-constraint-sanitized-projection@r2.json` | `tal-constraint-sanitized-projection@r2`; `sha256:b0f5583f57a7d53ea311c1b313b96a8d4512a49ac972ed95496d83908b6eaa34` | approved 2026-08-19; declared part of artifact-lifecycle policy; predecessor r1 |
| **Reuse** | Policy; `ontology/lifted/tal-policy-honesty-presentation@r2.json` | `tal-policy-honesty-presentation@r2`; `sha256:e0dbf0c75db7066fc968ed1bcd338f698f110ae35b01861012a69a4d90bc3a9f` | approved 2026-08-19; depends on sanitized-projection@r1; predecessor r1 |
| **Modify** | SuccessCriterion; `ontology/lifted/tal-sc-design-accessibility@r2.json` | `tal-sc-design-accessibility@r2`; `sha256:c52d9d19013020bf8e191adae5ac8b5434a247d267b0f11d7ca6eba6c3b020ca` | approved 2026-08-19; part of design-system, uses contrast checker, derived from frontend-ui; add WCAG 2.2 and manual evidence bindings through a successor if absent |
| **Modify** | SuccessCriterion; `ontology/lifted/tal-sc-design-system@r2.json` | `tal-sc-design-system@r2`; `sha256:673acd79699ba8d37f9f1f73d1e1309f329a9134a32c0da85173d39b4ad78360` | approved 2026-08-19; uses design-accessibility and contrast checker; predecessor r1; require visitor-visible and matrix-complete outcomes |
| **Modify** | CapabilityDescription; `graph/data/local/tal-capability-design-systems@r1.json` | `tal-capability-design-systems@r1`; `sha256:8095d49ce3af963a9ebe46ee2bc9e378e90c8f0ce3bb76bc966cf1a06d39db3e` | approved 2026-08-20; provides `capability.design.systems`; depends on design-research@r3, design-system-atlas@r4 and style-guide@r3. A successor should close the bilingual production-evidence gap instead of creating a Competency kind. |

### Rejected or not yet bindable

- **Reject as current selections:** `tal-skill-visual-design-critique@r3`,
  `tal-blueprint-page-templates@r5`, and `tal-policy-design-concept@r5` exist at
  the inspected head but have no authority event for those exact revisions.
  A higher revision number is not approval. Select an approved predecessor or
  issue and approve a corrected successor before contract issuance.
- **Unbindable:** `policies/policy-review-to-evolution.md` and
  `constraints/constraint-design-anti-patterns.md` are prose sources without
  managed graph revisions or authority events. The artifact lane must lift,
  validate and approve them before selection; product work cannot cite the
  prose path as a binding.
- **Reject:** `competencies/competency-design-systems.md` as a contract kind.
  The canonical model already represents the need through
  `tal-capability-design-systems@r1`; the unresolved legacy competency gap is
  not permission to extend the seven-kind ontology ad hoc.

### TALO-0008 and site evidence audit

The `done` label for TALO-0008 is not design-acceptance evidence:

- commits `742bcfdbefa1f71a5c23c335f879ca4f7b5c2f23`,
  `c1ddaf0083c832113d85176f4d1021fb4629ac6c`,
  `d63894f5550879edf3101f714096e6226686c283`, and
  `3d82914ea008fea5f6d5b7a9b85443dc72419bb0` created the research landscape,
  reconciliation ADR, nine design artifacts plus contrast script, and
  capability-map entries. They did not implement the site or produce the
  required screenshot matrix.
- `research/research-design-landscape.md` claims 43 URLs but contains zero
  literal `http://` or `https://` URLs, so its source provenance cannot be
  independently replayed as written.
- `ledger/TALO-0008.jsonl` records the original attribution as post-hoc: no
  pre-work Knowledge Contract, no approvals, unresolved competency treatment,
  and no wired provenance from the claimed artifacts to implementation.
- TALO-0028 later added digest-pinned successors and approvals. Site commit
  `dd24a8b0adafdbcc95e04ac99790eeb207b184d7` is an ancestor of the inspected
  site `origin/main` and carries the language separation/redesign work, but it
  does not prove operator design acceptance. That distinction remains explicit
  for the later TALO-0049 human screenshot record.

The site does provide implementation mechanisms worth reusing:
`.github/workflows/critique-production.yml`, `scripts/design-audit.mjs`,
`scripts/design-critique.mjs`, `scripts/design-gate.mjs`,
`scripts/visual-verify.mjs`, `scripts/composited-contrast.mjs`,
`scripts/design-baseline.mjs`, the critique/design mutation scripts,
`test/site/i18n-parity.spec.ts`, the rendered accessibility/contrast tests, and
Playwright `1.62.1` pinned in `package.json`/`pnpm-lock.yaml`. None currently
constitutes one unified RU/EN x desktop/tablet/mobile x light/dark production
evidence recipe; that 12-cell closure remains a gap.

### Seven-kind gap analysis

| Managed kind | Reuse / change decision before implementation |
|---|---|
| Role | Reuse approved design-lead, curator, evidence-auditor and deployment-operator revisions; create only the missing Datarim designer execution projection/binding. |
| Skill | Reuse design-research, theming and measurement; create substantive `frontend-design`; compose/extend frontend-ui and playwright-qa without granting either pre-code design authority. |
| Blueprint | Reuse design-system and component blueprints; revise or compose evidence-bearing-verification for a single 12-cell, SHA-bound production recipe. |
| Constraint | Reuse approved style-guide and sanitized-projection; lift and approve design-anti-patterns only if its rules survive research and forward tests. |
| SuccessCriterion | Revise the approved design criteria to bind WCAG 2.2, RU/EN semantic parity, three viewport classes, two themes, performance, production visibility and customer disposition. |
| Policy | Reuse honesty-presentation; lift and approve review-to-evolution so review findings cannot disappear or be attributed post hoc. Add performance/accessibility policy only where the approved graph has no equivalent. |
| CapabilityDescription | Revise the approved design-systems capability to cover the new pre-code design and complete production-evidence abilities. Do not create `Competency`. |

Non-managed operational artifacts are still required: design/token/evidence
templates, schema-valid examples, validator recipes, independent forward-test
fixtures, per-boundary mutations, and the issued Knowledge Contract manifest.
They support the seven managed kinds but do not become additional `kind`
values.

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
needs the following reusable set. The managed rows use only the canonical
seven kinds; supporting templates and recipes are explicitly non-managed.
Names and schemas remain proposals for the artifact-creation lane, not
artifacts created by this document.

| Canonical kind or support class | Required content | Key evidence |
|---|---|---|
| Role | Pinned design-lead authority plus Datarim designer execution projection, responsibilities, hand-offs and boundaries | Independent role-resolution test; cannot silently become developer or approver |
| Skill | `frontend-design` pre-code workflow, design-research reuse, and routing to existing implementation/QA skills | Forward tests on realistic bilingual design requests |
| Blueprint | Approved bilingual responsive design-system packet plus unified evidence-bearing verification successor/composition | Valid example plus missing-section and missing-axis mutations |
| Constraint | Approved style/i18n/responsive/projection invariants; graph-lifted design anti-pattern rules only after validation and approval | Schema, relation and behavior tests; wrong-revision and rule-removal RED |
| SuccessCriterion | WCAG 2.2 AA, semantic RU/EN parity, three viewport classes, two themes, performance, live production and customer disposition | Requirement-to-AC-to-live-evidence graph validation and threshold mutants |
| Policy | Honesty, accessibility/performance governance and graph-lifted review-to-evolution | Policy-at-issuance closure, false-positive mutants and forward review |
| CapabilityDescription | Design-systems capability successor covering content hierarchy, visual systems, typography/color, responsive interaction, accessibility, i18n, performance-aware design and evidence literacy | Scenario evaluation across the declared `provides` claims and pinned dependency closure |
| Supporting template (non-managed) | Primitive/semantic/component tokens, light/dark pairs, state coverage and consumer bindings | Schema validation, contrast checks and alias integrity |
| Verification recipe (non-managed) | Deterministic environment, metadata, RU/EN x desktop/tablet/mobile x light/dark screenshots, diffs and interactions | Missing-axis/metadata/baseline mutations; exact SHA and production URL |
| Knowledge Contract manifest (issuance record) | `K_id`, revisions/digests, pre-work timestamps, bindings, lifecycle, provenance, relations and validator evidence | Fail-closed schema/graph gate and independent forward review |

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
Contract before product code begins. That contract may select only the seven
canonical managed kinds, including `CapabilityDescription`; it must never
manufacture `Competency` as a primitive kind.

The selected verification model is deliberately layered: normative WCAG 2.2
AA; semantic/native implementation guidance; RU/EN content parity; a 12-cell
viewport/theme/locale visual matrix; repeatable browser assertions; field Core
Web Vitals goals plus lab budgets; versioned provenance and typed relations;
and independent mutations that force each claimed boundary RED. Tools, docs,
tests or screenshots alone remain insufficient for a customer-visible outcome.

## Research cost ledger

- Research date: 2026-08-24.
- This research record did not capture wall-clock duration, model identity,
  input/output token counts, compute consumption, or monetary cost. Each is
  **unknown**, not zero. The counts and repository snapshots below are scope
  evidence only and must never be reused as the Step 7 execution-cost ledger.
- External source records: 29.
- Link verification: 29/29 source URLs returned HTTP 200 on 2026-08-24.
- Canonical repository snapshots inspected: Datarim
  `a58e1a28454ab35cba26a8df71d4794662b0d339`, Talomnia knowledge
  `c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae`, and Talomnia site
  `20f58029b1e81a093938e4795ed9d8b6f3ff0ed8`.
- Historical evidence checked: all four TALO-0008 artifact commits,
  `ledger/TALO-0008.jsonl`, the TALO-0028 correction lineage, site commit
  `dd24a8b0adafdbcc95e04ac99790eeb207b184d7`, authority events, graph
  revisions and canonical Knowledge Contract schema.
- Stage 1 correction: expanded from three local skills to a complete
  reuse/modify/create/reject inventory; corrected the ontology from a proposed
  competency row to the exact seven managed kinds and
  `CapabilityDescription`.
- Primary/official domains represented: W3C/WAI, Unicode Consortium, web.dev /
  Chrome, Playwright, GOV.UK Design System, USWDS, JSON Schema, Backstage and
  Stryker.
- Runtime/package dependencies added: none.
- Product code changed: none.
- Reusable artifacts created: none; this INSIGHTS record is the research input
  to the separate artifact-creation lane.

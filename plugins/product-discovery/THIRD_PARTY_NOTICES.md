# Third-Party Notices for `plugins/product-discovery/`

This notice covers the Datarim product-discovery plugin and the framework review method listed in MIT-8 below. The product-framing method is re-expressed in the plugin's own structure and wording. Other methods in the program inventory remain planned or blocked for their assigned slices unless this notice says they are implemented. Where a close derivative is retained, applicable license obligations still apply; paraphrasing does not exempt a derivative under Apache License 2.0 Section 4.

## gstack material (MIT)

The gstack method sources are pinned at commit `15ebd85cdde6c9a1b2fb707e8573aec18e8f7438` (`VERSION 1.91.100.0`), copyright 2026 Garry Tan. Product-framing and scope-mode methods are re-expressed in this plugin and covered by the MIT notice below. QA, test-value, and findings-resolution methods remain separate planned work. The developer-experience method is re-expressed in `skills/dx-review/SKILL.md` and covered by MIT-8 below.

## Apache-2.0 material (APACHE-1)

No Apache-derived text or code is included in this plugin. The generated `plan-design-review/sections/review-sections.md` block at the pinned gstack revision (lines 114-222, including visitor modes at 118-123) and generated `review/design-checklist.md` are individually identified as Apache-derived and marked `not-shipped`. `office-hours/SKILL.md` mockup/sketch output is excluded by scope; it is not classified Apache-derived because the pinned output has no markers from the NOTICE-enumerated material. The NOTICE names impeccable source files but does not pin their upstream commit; this original source provenance remains unpinned and excluded. If a future approved target retains an Apache-derived work, ship `licenses/Apache-2.0.txt@15ebd85cdde6c9a1b2fb707e8573aec18e8f7438` (SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`), attribution to Paul Bakaus / impeccable, a pointer to the NOTICE, and a statement that the material was modified before distribution.

## MIT method attribution inventory

For each target below, the named gstack files are pinned at commit `15ebd85cdde6c9a1b2fb707e8573aec18e8f7438`; hashes and precise use ranges are recorded in the program's third-party plan and provenance trace. MIT-1 is implemented in this plugin; the other entries remain scoped to their assigned work.

### MIT-1 — plugins/product-discovery/skills/product-framing

- `office-hours/SKILL.md.tmpl`
- `office-hours/SKILL.md`
- `office-hours/sections/phase-2a-startup-diagnostic.md.tmpl`
- `office-hours/sections/phase-2a-startup-diagnostic.md`
- `office-hours/sections/phase-2b-builder-brainstorm.md.tmpl`
- `office-hours/sections/phase-2b-builder-brainstorm.md`

### MIT-2 — strategist scope-modes fragment (implemented)

- `plan-ceo-review/SKILL.md.tmpl`
- `plan-ceo-review/SKILL.md`

Re-expressed in original wording at `plugins/product-discovery/skills/decision-record/strategist-scope-modes.md`; no source text is copied.

### MIT-3 — hypothesis-validation skill (method-only overlap with product-framing)

- `office-hours/SKILL.md.tmpl`
- `office-hours/SKILL.md`
- `office-hours/sections/phase-2a-startup-diagnostic.md.tmpl`
- `office-hours/sections/phase-2a-startup-diagnostic.md`

### MIT-4 — qa-charter and functional testing fragment (T5.1)

- `qa-only/SKILL.md.tmpl`
- `qa-only/sections/exploratory.md.tmpl`
- `qa-only/sections/reporting.md.tmpl`
- `qa-only/SKILL.md`
- `qa-only/sections/exploratory.md`
- `qa-only/sections/reporting.md`
- `qa/SKILL.md.tmpl`
- `qa/sections/exploratory.md.tmpl`
- `qa/sections/qa-patterns.md.tmpl`
- `qa/sections/scope.md.tmpl`
- `qa/sections/system-functional.md.tmpl`
- `qa/sections/test-bootstrap.md.tmpl`
- `qa/sections/exploratory.md`
- `qa/sections/qa-patterns.md`
- `qa/sections/scope.md`
- `qa/sections/system-functional.md`
- `qa/sections/test-bootstrap.md`

### MIT-5 — test-value-card fragment (T5.2)

- `qa/SKILL.md.tmpl`
- `qa/SKILL.md`
- `scripts/resolvers/test-value.ts`

### MIT-6 — findings-resolution and completion statuses (T5.3)

- `review/sections/plan-completion.md.tmpl`
- `review/sections/plan-completion.md`
- `scripts/resolvers/plan-gates.ts`

### MIT-7 — frontend-ui source inventory (reviewed; source text not used)

- `plan-design-review/sections/review-sections.md.tmpl`
- `plan-design-review/sections/review-sections.md`

This source inventory is retained for provenance. The generated review-sections block is also identified above as Apache-derived and not shipped, while its original impeccable provenance is unpinned. The framework UI state/journey additions are written from the task contract and existing `skills/frontend-ui/SKILL.md`; no text from this inventory is retained.

### MIT-8 — developer-experience review method (re-expressed)

- `plan-devex-review/SKILL.md.tmpl`
- `plan-devex-review/SKILL.md`
- `plan-devex-review/sections/checklist.md.tmpl`
- `plan-devex-review/sections/checklist.md`
- `plan-devex-review/sections/review-sections.md.tmpl`
- `plan-devex-review/sections/review-sections.md`
- `scripts/resolvers/dx.ts`

The method is re-expressed in the framework `skills/dx-review/SKILL.md`; no
verbatim text is retained. This attribution and the MIT license text below apply
to that re-expression.

## Unresolved provenance (not shipped)

The selected `cso/SKILL.md` assurance-label fragment (lines 150-152) is not planned for shipment. `cso/ACKNOWLEDGEMENTS.md` says earlier CSO work drew on Trail of Bits and Sentry skills but does not map either source to those lines; their exact origin and applicable notice remain unresolved. The fragment is marked `unknown` and `not-shipped` in `third-party-plan.json`.

## Verbatim upstream MIT license text

Source: `gstack:LICENSE@15ebd85cdde6c9a1b2fb707e8573aec18e8f7438` (SHA-256 `e56fbb5b3d95756f3fa1cfefa24732ec79f18ece1ad08a4e79e00df57e8b198c). The following text is reproduced verbatim from that pinned file:

MIT License

Copyright (c) 2026 Garry Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Verbatim upstream third-party notice enumeration

Source: `gstack:NOTICE.md@15ebd85cdde6c9a1b2fb707e8573aec18e8f7438` (SHA-256 `879fc62ddab70035c6f697e1bc8afaaf0a380e8b3e4ffe256ca403c28d909f7c). The following text is reproduced verbatim from that pinned file:

# Third-Party Notices

gstack is MIT. The files below contain material derived from Apache-2.0 works,
rewritten in gstack's voice and modified. Rewriting is not an exemption: the
license text is in `licenses/Apache-2.0.txt`, and each derived file carries a
notice that it was changed. Unmodified copies (the rule-registry fixture, the
license text) carry no header and are listed here instead.

## impeccable — Copyright Paul Bakaus — Apache License 2.0

https://github.com/pbakaus/impeccable

Derived, modified:

- `lib/design-catalog.ts`: rule ids and names from `crates/live/assets/antipatterns.json`; the prose is gstack's.
- `scripts/resolvers/design.ts`: the Persuade / Operate / Read / Experience visitor modes, the craft-floor reflexes (browser surfaces, one authored motion moment, depth has an offset, tinted secondary text, space above headings, light-or-dark from the use scene), and the three-looks calibration, from `SKILL.md`, `reference/craft-floor.md`, and `reference/new-work.md`, rewritten.
- `design-consultation/sections/proposal-and-preview.md.tmpl`: the font-selection procedure and the calibration paragraph, rewritten; and the `SKILL.md` / `sections/*.md` files generated from these sources.

Unmodified copy:

- `test/fixtures/impeccable-antipatterns.json`: `crates/live/assets/antipatterns.json` at commit 87d8f6d6 (engine-v0.1.3), wrapped in a `_source` provenance object.

Not distributed: `bin/gstack-design-detect.ts` invokes an impeccable engine the
user installed. gstack does not ship or mirror that engine and never runs impeccable's
installer or launcher. The one download gstack can make is the engine binary
itself, only after the user accepts a design skill's one-time offer: fetched from
impeccable's own GitHub release into `~/.impeccable/bin/<version>/`, verified
against the checksum pinned in `lib/design-detect-contract.ts`, and recorded in
the egress ledger first. gstack does not audit the engine's network behavior; the
wrapper refuses URL targets so gstack never asks it to touch the network.

## DESIGN.md specification — Copyright Google LLC — Apache License 2.0

https://github.com/google-labs-code/design.md

`lib/design-md.ts`, `bin/gstack-design-md.ts`, and the Phase 6 template in
`design-consultation/sections/proposal-and-preview.md.tmpl` implement the
format (YAML token front matter in five groups, eight canonical sections in
spec order, `{path}` token references). No specification text is reproduced.

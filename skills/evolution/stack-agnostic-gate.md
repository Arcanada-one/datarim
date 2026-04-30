---
name: evolution/stack-agnostic-gate
description: Pre-apply gate rejecting stack-specific content for Datarim runtime. Load before any Class A apply step in reflecting/evolution/optimize/addskill workflows.
---

# Stack-Agnostic Gate — Runtime Contract

The Datarim framework is **stack-neutral by contract**. Skills, agents,
commands, and templates installed under `$HOME/.claude/{skills,agents,commands,templates}/`
must not name a specific framework, package manager, or runtime library —
otherwise projects on a different stack inherit irrelevant or actively
misleading guidance.

This gate runs **before any Class A apply step** writes to the framework
runtime. It is the executable enforcement of `feedback_datarim_stack_agnostic.md`
(user-memory rule, declared 2026-04-25 after VERD-0010, hardened by VERD-0021
and TUNE-0039).

## Trigger

Load and run this gate at the apply step of:

- `skills/reflecting.md` Step 6 — Class A apply (post-archive evolution proposals)
- `commands/dr-archive.md` Step 0.5(e) — runtime apply of approved Class A
- `commands/dr-optimize.md` Step 8 — apply of approved optimization proposals
- `commands/dr-addskill.md` Step 9 — write of newly created skill/agent/command/template

## Scope

Any text about to be written to:

- `$HOME/.claude/skills/*.md` and `$HOME/.claude/skills/*/*.md`
- `$HOME/.claude/agents/*.md`
- `$HOME/.claude/commands/*.md`
- `$HOME/.claude/templates/*.md`

…with the exceptions listed in Whitelist below.

## Denylist

The single source of truth for keywords is the array literal at the top of
`scripts/stack-agnostic-gate.sh`. Categories covered:

- **Frameworks** — `NestJS`, `Fastify`, `Express.js`, `Next.js`, `Django`,
  `FastAPI`, `Spring Boot`, `Vitest`, `Jest`, `Pytest`, `Mocha`, `RSpec`
- **Package-manager invocations** — `npm install`, `npm audit`, `pnpm install`,
  `pnpm add`, `pnpm audit`, `yarn add`, `yarn install`, `pip install`,
  `pip-audit`, `cargo add`, `cargo audit`, `composer install`,
  `bundle install`, `bundle audit`, `gem install`, `go mod`
- **Stack-specific runtimes / libs** — `Prisma`, `BullMQ`, `axios`, `bcryptjs`,
  `Zod`

Matching is **case-insensitive whole-word** (`grep -wEi`). Word-boundary
matching prevents false positives like "RSpec" matching inside "perspective".

Extend the denylist conservatively — every addition is a global filter.
False-positive recovery uses the escape hatch below.

## Whitelist

- **`skills/tech-stack.md`** — explicitly stack-aware by design. The whole
  file is exempt; the gate skips it entirely.
- **`skills/evolution/stack-agnostic-gate.md`** (this file) — the gate's
  own contract document MUST enumerate the denylist verbatim, so it cannot
  be subject to the rule it defines.
- **`skills/ai-quality/deployment-patterns.md`** — by-design
  reference for deployment incidents across the ecosystem stack. Section
  headers like `## NestJS @Global() in Multi-Bootstrap Monorepos`
  document patterns that ARE stack-specific by nature (multi-bootstrap
  monorepo DI semantics ≠ universal). Generalization would gut
  applicability; wrapping ~20 individual blocks would erode escape-hatch
  intent. Whitelisted parallel to `tech-stack.md` precedent.
- **`skills/testing/live-smoke-gates.md`** — DEV-1156
  (multi-datasource ORM client mismatch) + DEV-1169 (cross-container
  HTTP→shell→DB chain) incident postmortems. Failure semantics are
  intrinsically stack-specific (DI container resolution, container
  exec-bit/TLS defaults, version-specific auth plugins). Generalization
  would erase the diagnostic value — a reader needs the concrete framework
  name to recognize the same trap in their own code. Parallel to
  `deployment-patterns.md` precedent.
- **`skills/utilities/ga4-admin.md`** — Python-specific
  Google Analytics 4 Admin API recipe (uses `google-auth-oauthlib` +
  `requests` libs). The skill IS a Python recipe; replacing concrete
  `pip install` with abstract «package install» renders the recipe
  un-runnable. Parallel to `tech-stack.md` precedent (stack-aware by
  design, not by accident).

## When to add a file to the Whitelist

The whitelist is a precedent system. Each entry weakens the gate's
discriminative power. Add a file ONLY if:

1. The file is **by-design** stack-aware — its core value depends on
   naming concrete frameworks/runtimes (e.g. tech-stack selection,
   deployment incident postmortems with framework-specific DI/lifespan
   semantics).
2. Generalization would gut applicability — replacing concrete names
   with abstract roles makes the content useless to readers.
3. Wrapping individual blocks in `<!-- gate:example-only -->` would
   exceed escape-hatch sparingly-used intent (rule of thumb: >3 escape
   blocks in one file → consider whitelist).
4. The exemption is reviewed by maintainer at PR time, not self-applied.

Files added to whitelist must be referenced in the list above with a
one-line rationale (per existing entries).
- **`<!-- gate:example-only -->` … `<!-- /gate:example-only -->`** —
  per-block escape hatch. Lines between an opening and closing marker are
  ignored by the gate. Use only when the stack-specific term is genuinely
  illustrative (a list of "for example, NestJS / Django / Rails…") and the
  surrounding prose is stack-neutral. Reviewers should challenge any usage
  that smuggles prescriptive guidance under the marker.

## Markers must be on separate lines (pitfall)

The escape-hatch markers are **block-style only**. The gate's awk strip
matches `<!-- gate:example-only -->` line-by-line and uses `next` after
the opening marker matches, so the closing marker on the **same input
line** is never processed and `skip=1` persists for the rest of the
file (every subsequent line is silently dropped from the scan, masking
real violations).

Correct (separate lines, the only working form):

```
<!-- gate:example-only -->
package install command examples for the documented runtime
<!-- /gate:example-only -->
```

Wrong (same line — opening matches, closing is never seen, scan halts):

```
<!-- gate:example-only -->examples here<!-- /gate:example-only -->
```

Source: prior incident — initial wrap attempts on inline mentions used the
same-line form; gate kept FAILing despite the wrap looking correct in
the diff. Diagnosed only after re-reading the awk strip logic.

## Invocation

Direct CLI (CI helper):

```
scripts/stack-agnostic-gate.sh <file-or-dir> [--whitelist <path>]
```

Agent flow (markdown checklist agents must follow when the script is not
reachable from the current working directory):

1. Read the target file's content (the proposal text about to be written).
2. For each entry in the Denylist above, run `grep -wEi -- "<keyword>"` over
   the content (case-insensitive whole-word match).
3. Skip lines between `<!-- gate:example-only -->` markers.
4. If the file path ends with `skills/tech-stack.md`, skip entirely (PASS).
5. **Decision:**
   - 0 hits → PASS. Proceed with the write.
   - 1+ hits → FAIL. **Do not write the file.** Two outcomes:
     - (a) Reword the proposal in stack-neutral terms and re-run the gate.
     - (b) Escalate to user: "Proposal is stack-specific — the right home is
       `CLAUDE.md` of the relevant project, not the framework runtime."

## Exit Codes (script form)

- `0` — clean (no matches)
- `1` — matches found (FAIL — do not write)
- `2` — invocation error (path missing, bad flag)

## Why This Exists

User memory `feedback_datarim_stack_agnostic.md` declared the rule on
2026-04-25 after VERD-0010. VERD-0021 reflection (2026-04-26) found three
Class A proposals that passed reviewer judgment and leaked stack-specific
content into runtime — `security.md` `fetch` migration, multi-PM dependency
list, `ai-quality.md` Live Audit recipes — all reverted manually. Memory is
necessary but insufficient: the executable gate at the apply step turns the
rule from advisory into enforceable.

## Out of Scope

- **Historical content cleanup** — the gate is forward-looking. Pre-existing
  stack-specific content in framework files (e.g. `skills/ai-quality/deployment-patterns.md`,
  `templates/docker-smoke-checklist.md`) is tracked as separate backlog items;
  the gate surfaces them but does not auto-fix.
- **Whitespace / Unicode bypass** — accepted residual risk. Bypass requires
  intentional malice; reflection follow-up + memory rule provide redundancy.

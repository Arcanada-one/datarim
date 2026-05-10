---
name: ai-quality
description: Five pillars of AI-assisted development — decomposition, TDD, architecture-first, focused work, context. Method size limits, DoD, stubbing.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# AI Quality & Best Practices

> **TL;DR:** These 5 pillars guide AI-assisted development. Apply them consistently for 30-50% better code quality and 40-50% fewer bugs.

## THE 5 PILLARS OF QUALITY AI DEVELOPMENT

### 1. DECOMPOSITION (Rules #1, #3, #9)
> **Break complex tasks into small, focused units.**

```
KEY LIMITS:
|- Max 50 lines per method
|- Max 7-9 objects in working memory
|- One responsibility per function
|- Separate signals — one variable, one question
```

**Why:** AI loses focus with complexity. Small units = better output.

**Separate-signals rule.** When a single variable answers two semantically distinct questions (e.g. "what to display" AND "is body non-empty"), refactoring one role silently breaks the other. Always extract independent signals for independent questions, even if they currently compute from the same source. The cost is one extra line at definition; the saving is not chasing regressions through downstream branches that read the variable as a proxy for something it no longer represents.

---

### 2. TEST-FIRST (Rules #2, #5, #6)
> **Tests are hallucination filters. Mock edges, not logic.**

```
SEQUENCE:
1. Write tests BEFORE code
2. Define "done" explicitly (DoD)
3. Cover corner cases upfront
4. STRICT mocking: edges only, NO data fitting
```

**Why:** Tests catch AI mistakes. No tests = no safety net.

---

### 3. ARCHITECTURE-FIRST (Rules #7, #8)
> **Approve structure before coding.**

```
APPROACH:
1. Create skeleton with stubs
2. Review architecture
3. Implement one method at a time
```

**Why:** Bad architecture = wasted work. Validate first.

---

### 4. FOCUSED WORK (Rules #10, #11, #12)
> **Narrow context improves quality.**

```
PRACTICES:
|- Review one method at a time
|- Define clear boundaries (what we DON'T do)
|- Verify AI can solve before starting
|- Wire ALL planned features in first pass — if code/prompts are ready
   and wiring is <30 min, do it. "Low risk deferral" is still deferral.
|- Authorization prompts to user: 1 sentence risk + 1 yes/no question.
   Threat models → docs, not interactive prompt.
```

**Why:** Broad context = scattered results. Focus = precision.
Source (auth UX): prior incident — user requested simpler prompts after a 7-option authorization table.
Source (wire-all): prior incident — dedup/rerank deferred as "low risk", user challenged, wiring took <15 min.

---

### 5. CONTEXT MANAGEMENT (Rules #4, #13, #14, #15)
> **Right information at right time.**

```
ELEMENTS:
|- Gather requirements BEFORE coding
|- Document transaction isolation needs
|- Structure datarim hierarchically
|- Engineer prompts carefully
```

**Why:** Bad context = bad output. Quality in = quality out.

---

## STAGE-RULE MAPPING

Load only the rules relevant to your current stage:

| Stage | Rules to Apply | Focus |
|-------|---------------|-------|
| **/dr-init** | #4 Requirements, #12 Complexity | Is the task well-defined? Can AI solve it? |
| **/dr-plan** | #1 Stubbing, #5 DoD, #6 Corner Cases, #7 Skeleton, #11 Boundaries | Decompose, define scope and done criteria |
| **/dr-design** | #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions | Design quality, keep it simple |
| **/dr-do** | #2 TDD, #3 Method Size, #8 Iterative, #9 Cognitive Load | Write tests first, small methods, one at a time |
| **/dr-qa** | #5 DoD verification, #10 Focused Review | Review one method at a time, check done criteria |
| **/dr-archive** | #8 Iterative verification + #10 Review (Step 0.5 reflection), #14 Structure (Step 2 archive doc) | Was the process followed? Hierarchical summaries for future context |

---

## QUICK RULE REFERENCE

| # | Rule | One-Liner |
|---|------|-----------|
| 1 | Stubbing | Break into 50-line stubs |
| 2 | TDD | Tests before code (Strict Mocking) |
| 3 | Method Size | Max 50 lines, 7-9 objects |
| 4 | Requirements | Context before coding |
| 5 | DoD | Explicit done criteria |
| 6 | Corner Cases | List boundaries first |
| 7 | Skeleton | Architecture before code |
| 8 | Iterative | One method at a time |
| 9 | Cognitive | 7+/-2 objects max |
| 10 | Review | Review one method only |
| 11 | Boundaries | State what's out of scope |
| 12 | Complexity | Verify AI can solve |
| 13 | Transaction | Explicit isolation levels |
| 14 | Structure | Hierarchical summaries |
| 15 | Prompts | Structured prompt creation |

---

## QUALITY CHECKPOINT

Before proceeding, ask:

```
[ ] Is this task decomposed into small units?
[ ] Do I have tests/DoD defined?
[ ] Is the architecture approved?
[ ] Am I focused on one thing?
[ ] Do I have the right context?
```

**If NO to any:** Stop and address before coding.

---

## COMMON MISTAKES

### DON'T
- Write code before tests
- Create methods > 50 lines
- Track > 9 objects per method
- Review entire features at once
- Start without clear requirements
- Skip corner case analysis

### DO
- Tests -> Code -> Review -> Next
- Keep methods small and focused
- One method at a time
- Define boundaries explicitly
- Document requirements upfront

---

## Spec-First with Golden Fixtures (Format-Change Pattern)

When a task changes **output format, structure, or contract across multiple files** (e.g. CTA blocks across 17 commands + 5 agents, response envelopes across N services, log fields across handlers), apply this pattern as a default rule for L3+ tasks:

```
SEQUENCE:
1. Spec-as-skill        → write the canonical specification first as a single
                          source-of-truth skill (e.g. cta-format.md). Define
                          structure, field rules, anti-patterns.
2. Golden fixtures      → create one fixture per variant (single, multi,
                          fail-routing, etc.) under tests/{topic}/fixtures/.
                          These are the visual artefacts agents produce.
3. Spec-regression tests → bats / language-native tests verify:
                          (a) every consumer file references the skill
                          (b) every consumer agent loads the skill
                          (c) fixtures match all spec invariants
                          (d) anti-pattern guards (forbidden chars, etc.)
4. Mechanical propagation → only after 1-3 land, propagate the change to all
                          consumers. Tests guard against drift.
```

**Why:** Without fixtures + tests, the same drift problem re-emerges every time a new consumer is added without spec compliance. Mechanical propagation alone protects current state, not future state.

**When to apply:**
- Format / structure changes affecting ≥5 files of the same kind
- Output-contract changes (CTA, response envelope, log fields, validation messages)
- Cross-cutting style / convention changes that need agent compliance

**When NOT to apply:**
- Single-file changes
- Internal-only refactors with no external contract
- One-off scripts where future drift is not a concern

Source: prior incident — Approach C (Spec-First with Golden Fixtures) chosen over Approach A (Big Bang refactor) for canonical CTA block. 39 tests now guard 17 commands + 5 agents from drift; mechanical sweep alone (Approach A) would have left the same problem to re-emerge with the next added command.

---

## Pipeline-Position-Aware AC Formulation

When an Acceptance Criterion asserts an HTTP status code (e.g. `→ 401`, `should return 403`), trace the request through the **full middleware/filter chain** — rate limiter → CORS → body parser → validator → guard → controller — before locking the literal status. Any layer upstream of the asserted source can short-circuit the chain and return a different code than expected.

**Failure mode:** AC declares `→ 401` (auth-rejected). <!-- gate:example-only -->Validator (Zod / class-validator / Pydantic / Joi) runs *before* auth, sees an empty body, returns `400 Validation failed`.<!-- /gate:example-only --> AC literally fails — but the asserted *behavior* (auth bypass works) is correct. PRD/plan/QA all need amendment under self-review.

**Rule:**
1. **Trace step.** Identify the source file/line that emits the asserted status. List every preceding middleware that can return early.
2. **Literal vs semantic gate.** If only the asserted source can produce the status under all valid inputs → literal AC OK. If any preceding middleware can short-circuit → phrase as **semantic gate**: `not <failure_class>` instead of `== <specific_status>`.
3. **Semantic gate template:** `[[ "$code" != "<failure_status>" ]] || ! echo "$body" | grep -q '<failure_marker>'`. Asserts «failure class N did not happen», not «specific success class M did happen». Robust to upstream layer swaps.

**When to apply:** any L2+ task that ships HTTP-routed code. Mandatory for L3+ when the controller sits behind ≥2 middleware layers.

**Stack-agnostic:** applies to any HTTP framework with a middleware/filter chain. <!-- gate:example-only -->Concrete examples: Express, Fastify, NestJS, Koa, Hapi, Django, Flask, FastAPI, Rails, Spring Boot, ASP.NET Core, Phoenix, Gin.<!-- /gate:example-only -->

**Anti-pattern:** copying the literal status from upstream PRD without re-tracing when middleware order changes (e.g. switching framework, adding rate limiter, moving validator). Re-trace on every PRD that touches HTTP routing.

---

## RFC 7807 Problem-Details Envelope for Programmatic API Errors

For services with programmatic API consumers (SPA, mobile clients, server-to-server), HTTP error responses MUST be parseable by machines, not just by humans reading a log line. Standardize on **RFC 7807 `application/problem+json`** as the ecosystem error envelope and concentrate the mapping in a single seam, not scattered per-handler `try/catch` blocks.

**Contract.**

1. **Single exit point.** Implement a global error-mapping seam at the framework boundary — the framework's idiomatic global exception filter, error middleware, or top-level handler — that converts every thrown error to the RFC 7807 envelope. No controller or middleware emits error JSON directly; the global seam is the only place that writes error response bodies.
2. **Frozen title table.** Define the `type` → `title` mapping centrally in one module. Every recognised problem type has a stable URI in `type` and a frozen short `title`. Adding a new problem type is an explicit edit to the table, not an ad-hoc string at the throw site.
3. **Typed exception class.** Define one application exception type that carries `{type, title, status, detail?, instance?, ...extensions}` and is thrown from anywhere in the call stack. The global seam recognises it by class and pass-through-maps it to the response. Foreign exceptions (validation library errors, framework HTTP exceptions, generic `Error`) are mapped by class in a priority chain inside the seam.
4. **Detail discipline for 5xx.** Server-class responses (`5xx`) MUST omit user-facing `detail` strings to prevent information disclosure (stack frames, internal paths, library messages). Client-class responses (`4xx`) MAY carry `detail` describing what the caller did wrong.
5. **No per-handler error JSON.** A handler that produces an ad-hoc `reply.send({error: ...})` defeats the contract — programmatic consumers will receive two different envelope shapes from the same service. Replace such call sites with `throw new ProblemException(...)` and let the global seam render.

**Why.** A programmatic consumer parses by `Content-Type` and field names. Inconsistent envelopes (some handlers use `{error, code}`, others `{message}`, others raw text) force defensive client code at every call site. RFC 7807 is a published standard; any well-formed problem document is parseable by off-the-shelf libraries. Concentrating the mapping in one seam means new endpoints get correct error shapes for free, and audit/refactor of error contracts is one file, not N.

**When to apply.** Any service exposing an HTTP API to a programmatic consumer outside the team writing the service. Internal-only utilities with human-only callers may use simpler shapes, but the moment a SPA or mobile client lands as a consumer the global seam is mandatory.

**Anti-patterns.**

- Per-controller `@UseFilters` decorators / per-route error handlers — re-creates the per-handler scattering the rule is preventing.
- Inline `if (err) reply.code(400).send({error: 'foo'})` after the global seam exists — silent contract divergence.
- Mutating the title table at runtime or per-environment — titles are part of the wire contract; changing them breaks consumers.

---

## Atomic Multi-Surface Plan Amendment

When an Acceptance Criterion's location moves mid-implementation — different controller, different module, different URL path, different scope boundary — update **all** parallel artefacts atomically within the same revision cycle, not lazily across separate commits or "I'll fix the plan later" deferrals. The parallel surfaces typically include:

- The PRD section that owns the AC text (with an `AMENDED YYYY-MM-DD` marker and a one-line justification).
- The implementation plan's per-step locus and the AC ↔ step mapping.
- The task description's Implementation Notes (operator-facing record of the moved boundary).

**Rule.**

1. **One revision cycle, one operator-approval event.** Every amended surface references the same approval date or decision identifier. Drift starts when one artefact carries an old AC location and another carries the new one — readers cannot tell which is authoritative.
2. **Cross-check after edit.** Grep the AC identifier across all parallel artefacts. Exactly one canonical definition per surface, and the location/path/scope text MUST match across surfaces. A mismatch is a post-amendment finding, not a normal state.
3. **Ship in the same commit or same branch push as the code.** Do not merge the code change while the PRD/plan still describe the old location. The artefact set ships as a unit; consumers reading mid-stream see a consistent picture.
4. **Step-locus precision.** When AC moves between modules/controllers, the implementation plan's Implementation Steps section MUST update its locus references — not just Implementation Notes. A reviewer reading only the Steps must reach the same code as a reviewer reading the Notes.

**Why.** When PRD, plan, and task description carry the same AC under three different locations, future readers (QA at archive time, the next developer touching the area, a security audit) cannot distinguish authoritative from stale. Drift compounds: the next amendment based on a stale surface re-amplifies the divergence. Atomic updates with cross-check make the artefact set self-consistent at every commit.

**When to apply.** Any L2+ task that maintains parallel PRD + plan + task description artefacts. Mandatory when an AC's path/module/controller changes mid-implementation. Recommended when scope reduction or expansion changes which surface owns which assertion.

**Anti-patterns.**

- "I'll update the PRD after this commit lands" — the moment the commit lands, the PRD is wrong and CI/QA reads stale text.
- Updating Implementation Notes only, leaving Implementation Steps locus pointing at the old module — reviewers reading only one section drift.
- Multiple amendment markers with conflicting dates or no operator approval reference — provenance becomes unrecoverable.

---

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/ai-quality/incident-patterns.md`
  Use when adding safety guards, reviewing integration failure attribution, or making scope decisions for untracked files.
- `skills/ai-quality/deployment-patterns.md`
  <!-- gate:example-only -->
  Use when deploying services (Docker, venv, NestJS DI, CLI connectors in containers).
  <!-- /gate:example-only -->
- `skills/ai-quality/bash-pitfalls.md`
  Use when writing or reviewing any `.sh`, especially regex/grep/sed-heavy ops scripts. Mandatory shellcheck rule for /dr-do, plus the five recurring traps (grep -F + ^, boundary-alternation regex, raw ${var} in regex, password in process arglist, set -e + pipelines).

---

*These principles reduce bugs by 40-50% and improve code quality by 30-50%.*

# Design Note — Secrecy-Aware Project-Init Scaffold

> **Status:** DESIGN NOTE — **deferred, needs PRD.** This change alters the
> `project-init` contract (what content the scaffold writes, and a new gate
> emitted into the generated `CLAUDE.md`). Per the evolution Class A/B gate that
> is a **Class B** operating-model change: it MUST NOT be applied until a
> PRD-diff to the framework SDLC-framework PRD is drafted and signed off. This
> note captures the mechanism and the founding incident so the eventual PRD +
> implementation task start from a settled design, not a blank page.
>
> **Not implemented here.** No change to `skills/project-init/SKILL.md` or the
> `CLAUDE.md` template is made by the note's spawning task.

## 1. Founding incident (the scaffold-leak pattern)

A research project's scaffold generated `docs/reference/architecture.md`
(a Diátaxis reference stub) populated with the project's *current understanding
of the system* — which, for that project, **was the secret algorithm itself**
(the very cube/distance-map/bit-packing pipeline the project existed to keep
private). The secrecy constraint was declared in the project's `CLAUDE.md` the
same day, but the scaffold had already committed the mechanism to a public
surface. A QA blocker caught it; the fix (mechanism-free stub replacement +
secrecy gate command) was clean once identified.

**Root cause:** there is no secrecy gate at *scaffold time*. `project-init`
populates reference docs with the present system understanding. If the secrecy
decision is operator intent but not yet machine-readable when `init` runs, the
scaffold has no way to know to omit the mechanism. The gap between "scaffold
created" and "secrecy documented" is where the leak lives.

This is not a one-project edge case — it is a repeatable failure mode for **any
research/IP project where the secret surface exists before the secrecy
constraint is codified.**

## 2. Proposed mechanism

### 2.1 Secrecy annotation as an init input

Introduce a machine-readable secrecy annotation the operator can carry in the
task/project brief, e.g. a frontmatter or brief field:

```
secrecy: algorithm        # or: none (default) | data | algorithm | full
```

`project-init` reads this at scaffold time. Absent ⇒ `none` ⇒ today's behaviour
(no change for the common case).

### 2.2 Mechanism-free stubs

When `secrecy` is anything other than `none`, `project-init`:

- **Does NOT generate mechanism-bearing content** into `docs/reference/` (and
  any other information-oriented Diátaxis stub) — no algorithm description, no
  encoding-scheme detail, no internals.
- Substitutes a neutral placeholder instead, e.g.
  `[REDACTED — see CLAUDE.md § Secrecy]` / `internal (see § Secrecy)`, and a
  one-line pointer to where the private detail actually lives (out of the public
  surface).
- Uses **mechanism-free lexis** — the stub must not name the mechanism even
  obliquely (no "cube", "distance map", "bit-packing" for the incident case);
  the placeholder carries no vocabulary from the secret surface.

### 2.3 Secrecy gate emitted at scaffold time (not post-hoc)

The scaffold writes a **secrecy gate command into the generated `CLAUDE.md`**
during `init`, not as a later remedial commit. The gate is a grep-style check
that fails if any secret-surface vocabulary reaches a public doc stub, wired so
`/dr-qa` / `/dr-compliance` run it. Declaring the constraint *before* creating
any content that touches the secret surface is the invariant: **codify secrecy
before scaffolding the surface it protects.**

### 2.4 Planner hook (defence in depth)

When the operator brief contains known-secret-mechanism phrases (algorithm /
encoding scheme / compression mechanism, …) and the project is a research-type
task, the planner flags the stub-generation step with a human-gate before
writing content — catching the case where the operator *intends* secrecy but
has not set the annotation.

## 3. Known edge case to fold into the PRD

**No-README edge.** The reference secrecy-gate implementation globbed
`Projects/<name>/README*`, which exits noisily (`ls: No such file or directory`)
when no README exists yet at scaffold time. Harmless (the failing command is the
`ls`, not the `grep`), but the gate MUST tolerate an absent README gracefully —
e.g. `find … -name 'README*'` with a fallback empty list. Fold this into the
gate spec so the first implementation ships it correct.

## 4. Classification and why this is deferred

- **Class B.** It changes the `project-init` contract (scaffold output) and adds
  a gate to the generated `CLAUDE.md` template. Per the evolution gate, a Class B
  change requires a PRD-diff to the framework SDLC-framework PRD **before**
  approval — it is not an approval-ready content edit.
- **Blast radius.** `project-init` runs for every new project; a bug here
  mis-scaffolds real repositories. It warrants the PRD's design analysis and
  acceptance criteria, not an inline apply.

## 5. Suggested acceptance criteria for the eventual PRD/impl task

- AC1 — `project-init` reads a `secrecy` annotation; `none`/absent is a no-op
  (byte-identical scaffold to today).
- AC2 — For `secrecy != none`, reference/info stubs carry only mechanism-free
  placeholders (asserted by a fixture: no secret-surface vocabulary in output).
- AC3 — The generated `CLAUDE.md` contains a `§ Secrecy` section AND a working
  secrecy gate command, written at scaffold time.
- AC4 — The gate tolerates an absent README (no noisy failure, correct verdict).
- AC5 — The planner human-gate fires on secret-mechanism phrases in a
  research-type brief.
- AC6 — PRD-diff to the SDLC-framework PRD is drafted and signed off (Class B).

## 6. Disposition

**Deferred — needs PRD.** Spawn a PRD task (or PRD-diff) covering § 2–§ 5, then
an implementation task. Until then, operators of secrecy-bearing projects should
declare the secrecy constraint in `CLAUDE.md` **before** running any scaffold
that would touch the secret surface, and review generated reference stubs before
the first commit.

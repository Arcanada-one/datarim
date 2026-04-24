---
name: evolution/class-ab-gate
description: Class A vs B operating-model gate for evolution proposals. Load when evaluating whether a proposal changes framework contract.
---

# Class A vs Class B — Operating-Model Gate

Not all proposals are equivalent at the approval step. Reflection approval is sufficient for *content* changes, but framework *contract* changes require a PRD update first. The gate below codifies this distinction after the TUNE-0002 → TUNE-0003 incident.

## Class A — Content changes (reflection approval sufficient)

Proposals that add, refine, or clarify the content of existing skills, agents, commands, or templates — without changing the framework's contract with its users.

Examples of Class A:
- Add a new recipe to `utilities/` (e.g. `utilities/crypto.md`)
- Restore a missing section to `testing.md`
- Tighten a classification list in `dr-do.md` (e.g. review-feedback categories)
- Promote a runtime-only skill into the repo
- Add a new `*.md` template for a recurring pattern
- Fix a cross-reference or typo

**Approval path:** `/dr-archive` Step 0.5 (reflecting skill) → user approval → apply to runtime → curate to repo. Normal flow.

## Class B — Operating-model changes (PRD update required BEFORE approval)

Proposals that change the framework's contract — how it is understood, installed, synced, or orchestrated. These are NOT just content edits; they alter what Datarim *is* for projects that use it.

Class B triggers (non-exhaustive):

- **Source-of-truth direction:** "Make repo canonical," "Make runtime canonical," "Switch to X-first model"
- **Sync semantics:** Change how `install.sh` handles existing files, redefine drift interpretation, change curation policy (who approves what)
- **Pipeline routing:** Reorder pipeline stages, change complexity-level → pipeline mapping, add/remove a mandatory gate
- **Core contract:** Redefine task ID invariance rules, change archive-area mapping contract, alter path resolution rules, change PRD waiver policy at the class level (not a single waiver, the policy itself)
- **Command semantics:** Change what a command *means* (not just how it executes), e.g. making `/dr-archive` optional instead of gating

**Approval path for Class B:**

1. Reflection generates the proposal and flags it as Class B in the proposal block.
2. `/dr-archive` Step 0.5 (reflecting skill) pauses — does NOT ask for proposal approval yet; also does NOT proceed to Step 1.
3. Instead, asks the user: "This proposal changes operating model. Update `PRD-datarim-sdlc-framework.md` first? Draft the PRD diff before approval?"
4. User either drafts PRD change (or approves a draft) — PRD becomes the source-of-truth for the new contract.
5. Only AFTER PRD is updated does the proposal re-enter normal Class A approval flow.
6. Implementation of the proposal must cite the PRD section that authorizes it.

## How to tell if a proposal is Class B (decision aid)

Ask three questions. If the answer to any is YES, treat as Class B:

1. **Does this change affect users of the framework beyond this project?** (e.g. it would appear in installer-onboarding docs, getting-started guide, or README)
2. **Is the current behavior documented in `PRD-datarim-sdlc-framework.md`?** (if yes, changing it requires updating the PRD)
3. **Could two reasonable people reading the proposal disagree on what the framework promises after the change?** (if yes, you need a PRD to arbitrate)

If all three are NO — Class A, proceed normally.

## Why this gate is worth the friction

PRD updates add ~15-30 minutes of work per Class B proposal. The TUNE-0002 → TUNE-0003 incident cost ~6 hours of wrong-direction implementation + correction + TUNE-0011 recovery, or ~12x the gate cost. The gate also creates a persistent record (PRD diff + rationale) that future research can reconcile against instead of re-deriving.

## Projects without a framework-level PRD

Datarim framework itself has `PRD-datarim-sdlc-framework.md` as the contract artifact. But consumer projects that use Datarim as an installed framework often do not have their own framework-level PRD. The Class B gate still applies — it just points at a different contract artifact.

For consumer projects, PRD substitutes in priority order:

1. **Project-level PRD** at `datarim/prd/PRD-{project-id}.md` — if the project has one covering the area the proposal touches, update it.
2. **Project `CLAUDE.md`** — the top-level project contract. Changes to source-of-truth direction, sync semantics, or core conventions must update `CLAUDE.md` with the new rule and a rationale comment.
3. **Architectural decision records** (`datarim/creative/*.md` or project's ADR directory) — if the change reflects a design decision, record it there with "supersedes ADR-N" linkage.
4. **None of the above** — then the proposal is really a framework-level Class B change disguised as a project-level one. Escalate to Datarim framework PRD update (`PRD-datarim-sdlc-framework.md`) instead of inlining into the project.

**Rule:** a Class B proposal always needs a written contract artifact that ratifies it. Never apply a Class B change whose only justification is a reflection entry. Reflection proposes; a contract ratifies.

---

## Contract-Implementation Atomicity (anti-TUNE-0003)

**Single-repo:** PRD/contract update and implementation MUST land in the same commit.

**Cross-repo:** When they live in different git repositories, they MUST land in the
same `/dr-do` session, on the same calendar day, with cross-cite in both commit messages
referencing the shared task ID. See `datarim/docs/ADR-TUNE-0014-cross-repo-atomicity.md` for rationale and verification procedure.

---

## Founding incident (2026-04-15..16)

TUNE-0002 research concluded "repo-first operating model should replace runtime-first" based on research-level reasoning. This was treated as a regular proposal and approved through the normal reflection gate. TUNE-0003 then executed it — bumping VERSION, rewriting README Operating Model section, rewriting wrapper CLAUDE.md to 5-step repo-first workflow — without reconciling against `PRD-datarim-sdlc-framework.md`, which explicitly specified runtime-first via `/dr-reflect` (the command existing at the time of the incident; consolidated into `/dr-archive` Step 0.5 in v1.10.0 via TUNE-0013).

The PRD was the load-bearing contract. The reflection gate had no way to see that. Result:

1. Wrong-direction docs committed as v1.7.0.
2. `install.sh --force` run during /dr-archive on the (now stale-again) runtime, overwriting 9 files with repo content that had been built on the wrong premise.
3. Mid-task correction to runtime-first (v1.8.0), 4 hours of recovery + 4 files of TUNE-0011 reconstruction work downstream.

**Lesson:** research conclusions cannot silently override PRDs. The PRD is the contract; research proposes, PRD ratifies.
# How to run the `/dr-auto` dogfood retrospective

This is a **scaffold**. It is filled in once `/dr-auto` has driven **five or more real tasks** to a passing `/dr-compliance` + reflection. Until then it stays empty except for this preamble — do not fabricate entries from fewer cycles.

The retrospective answers two standing questions the `/dr-auto` PRD deferred:

1. **Ladder typing** — which operator escalations recur often enough that they should be *typed* into the Question Suppression Ladder (L1–L4) instead of surfacing as ad-hoc L5 stops?
2. **Wide-mode scope** — should `/dr-auto` widen from the narrow decision scope the operator chose in the PRD to cover business-strategy decisions, and if so, which decision classes?

## When to run

Trigger: **≥ 5 archived tasks whose archive frontmatter records a `/dr-auto` invocation.** Find them with:

```bash
# From the workspace root — count archives that ran /dr-auto.
grep -rl 'dr-auto' documentation/archive/ | \
  xargs grep -l 'verification_outcome' 2>/dev/null | wc -l
```

Re-run the retrospective every additional five cycles, appending a new dated round below rather than overwriting the previous one.

## Data sources

| Signal | Where it lives |
|--------|----------------|
| Per-task verify outcomes | `verification_outcome` block in each `documentation/archive/**/archive-*.md` |
| Aggregate caught/missed rate | `dev-tools/measure-prospective-rate.sh --since <YYYY-MM-DD>` |
| Escalation events (hard-gated stops) | the archive body's reflection section + the session/handoff artefacts referenced there |
| Marker / activation issues | `dev-tools/check-dr-auto-cross-runtime.sh --report` run history, if recorded |

## How to fill each round

For every round, walk the five (or more) archived `/dr-auto` tasks and record:

1. **Escalation ledger** — one row per operator escalation (L5 stop or hard-gated confirmation): task id, stage, what was asked, whether it was a genuine judgment call or a gap that a Ladder rule could have closed.
2. **Recurring patterns** — group the ledger rows; a pattern that appears in ≥ 2 of 5 cycles is a Ladder-typing candidate.
3. **Ladder-typing proposal** — for each recurring pattern, propose the Ladder level (L1 inline / L2–L4 typed suppression) and the exact rule text, or record *keep as L5* with the reason.
4. **Wide-mode candidates** — list any business-strategy decisions `/dr-auto` had to escalate because they were out of its narrow scope; judge whether widening the scope to that class is safe under the hard-gated-action boundary.
5. **Decision** — the operator-approved outcome for this round (framework changes go through `/dr-archive` Step 0.5 evolution proposals; no silent edits).

---

## Round template (copy per round)

<!-- Copy this block and fill it once the trigger condition is met. -->

### Round N — <YYYY-MM-DD> (<count> cycles, tasks: <ID>, <ID>, …)

**Prospective rate:** _(paste `measure-prospective-rate.sh` summary)_

#### Escalation ledger

| Task | Stage | Escalation | Judgment call? | Ladder-closable? |
|------|-------|-----------|----------------|------------------|
| _…_  | _…_   | _…_       | _…_            | _…_              |

#### Recurring patterns (≥ 2 of N)

- _pattern → candidate Ladder level / keep-L5 + reason_

#### Ladder-typing proposals

- _pattern → proposed L1–L4 rule text, or keep-L5 with reason_

#### Wide-mode candidates

- _decision class → widen (with guardrail) / keep narrow + reason_

#### Decision (operator-approved)

- _outcome; link the `/dr-archive` evolution proposal or backlog item that carries it_

---

## Rounds

_(none yet — waiting for the first 5-cycle window)_

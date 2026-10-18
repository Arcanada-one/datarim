# Quick Task Evidence and Learning

Use this guide to keep `/dr-quick` lookups informational, establish the normal
evidence floor before a quick task writes anything, and report reflection and
proposal state without implying that a proposal was applied.

## Keep a lookup read-only

For a lookup that only reports what was found:

1. State falsifiable acceptance cases in the conversation before searching.
2. Record dated source references, exact read-only commands and observed
   results for each case. Include failed attempts and how discrepancies were
   rechecked.
3. Report the result as informational / UNCERTIFIED. Do not create task
   metadata, an archive or a snapshot, change branches, or call it a structured
   gate PASS.

The informational branch does not persist its findings. If the requested
outcome changes to an edit or to saving the lookup in a task/report record,
stop before that write and enter the mutating QCK flow.

## Start a mutating quick task before its first write

When the task will edit files, switch branches, archive results, or persist a
lookup, use the mutating QCK path:

1. Re-evaluate execution-host routing for the mutation. If the task began as a
   lookup, route it again before acting on the new intent; conversational
   lookup evidence is not a substitute for the mutation's baseline.
2. Allocate the QCK ID and create its canonical task metadata and falsifiable
   quick-stage acceptance cases.
3. Capture the persisted preflight receipt before the first mutation.
4. Perform the work and collect actual evidence for the cases.
5. Before closure, run `check-live-evidence.sh --root <repo-root> --contract
   <acceptance.json> --evidence <evidence.json> --stage quick`. A nonzero result
   blocks closure until the discrepancy is fixed and checked again; retain each
   attempt.
6. Write the short quick archive and follow the command's CTA and snapshot
   emission instructions. This snapshot belongs to the mutating path; the
   read-only lookup path does not emit one.

If a lookup turns into an edit or persistent report before the normal baseline
exists, do not carry the lookup's UNCERTIFIED evidence forward as mutation
acceptance. Begin the mutating flow first.

## Record only a verified quick-learning signal

Ordinary quick fixes and read-only lookups do not run reflection or create
evolution proposals. For a mutating quick task, record the conditional learning
signal only when the work exposed a concrete mistake or logic mismatch, that
mistake was corrected, and the correction was verified. The signal is a
proposal record, not an applied skill or automatic framework change.

Keep its disposition explicit:

- **Class A:** retain the existing approval question for this proposal. It is
  pending until an approval decision and any required application are recorded.
- **Class B:** keep it held until the required contract or PRD update is done;
  do not present it as ready or applied.
- **Unresolved class:** preserve the unresolved classification and required
  next step; do not silently choose a class.
- **Applied:** use this state only when an evolution record or equivalent
  evidence confirms application.

The evolution trigger guidance names `/dr-compliance` as the primary trigger
and `/dr-archive` as the freshness fallback. A missing or stale reflection is
unmeasured, not proof that there were no proposals.

## Preserve learning state in `/dr-auto` handoff

Before the single CTA summary, carry the delegated task result, compliance
report when present, and current reflection when present into one operator
summary. Preserve each proposal's number, class, category, target, rationale
and state: pending approval, held, applied or rejected. State the recorded
compliance verdict when compliance ran; when it was intentionally skipped,
give the reason and do not imply that reflection ran. Say there were no
proposals only when the current reflection confirms that. If reflection is
absent, stale or unavailable, report it as unmeasured.

This is a source-level handoff contract. It does not establish that a live
delegated run delivered the summary to chat.

## Sources

- [`/dr-quick` command](../../commands/dr-quick.md)
- [`/dr-auto` command](../../commands/dr-auto.md)
- [Stage snapshot guide](stage-snapshots.md)
- [Evolution skill](../../skills/evolution/SKILL.md)
- [Human summary skill](../../skills/human-summary/SKILL.md)

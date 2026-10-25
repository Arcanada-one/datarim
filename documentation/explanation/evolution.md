# Self-Evolution

Datarim turns repeated task lessons into proposals during reflection. A passing
`/dr-compliance` writes the reflection, then runs the evolution decision step
inside `/dr-auto` and `/dr-orchestrate`. Interactive runs present proposals for
human selection. `/dr-archive` presents unresolved proposals even when it
reuses a fresh reflection.

## Decisions and evidence

Each proposal receives `apply`, `decline`, or `defer` with a written rationale.
The agent considers recurrence, impact, blast radius, reversibility, evidence,
and gate results. Class A can be applied after its gates pass. Class B changes
the operating contract and needs a PRD draft plus concurrence from an
independent blind reviewer before application. The current KB records every
decision in `datarim/history/evolution-log.md`; the reflection records its
corresponding status.

An isolated candidate receives the proposed change first. The stack-agnostic,
history-agnostic, and English-only body checks, tests reading every touched
file, and the full Bats suite run sequentially on that candidate before its
bytes reach the live instruction surface. A failed gate declines that proposal
without a live edit. A publication failure restores only its original bytes. A passing compliance verdict or a proposal alone does not
prove that an improvement was applied.

## Where changes land

In the framework source KB, an applied change lands on a signed feature
branch and goes through a PR and CI. In a consumer KB, executable changes
land in project-owned `datarim/local/`, composed with upstream on update. Project rules can also
land in `AGENTS.md`. Both survive `update.sh`.
Every reusable consumer lesson is also logged as a promotion candidate for
the cross-KB evolution digest, including locally applied rules. Local
application and framework promotion are separate outcomes. Consumer runs
never write to the public framework repository.

Automatic application defaults to enabled in the two autonomous routes. A
workspace can set `auto_apply: false` in `datarim/config/evolution.yaml`;
decisions and logs still occur. See the [how-to guide](../how-to/autonomous-evolution.md)
and [configuration reference](../reference/autonomous-evolution.md).

`/dr-optimize` remains an explicit maintenance command. It audits component
counts and duplication; it does not inherit the automatic growth path.

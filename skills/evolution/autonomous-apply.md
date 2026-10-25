# Autonomous Evolution Decision Step

Run this step after a passing `/dr-compliance` has finished and stamped the
reflection. Both `/dr-auto` and `/dr-orchestrate` reach it through the compliance
command. This step is separate from the L1 Inline Resolution Rule.

## Activation and routing

Resolve effective autonomous mode using the matching per-task marker. In an
orchestrated run, the dispatcher must carry the autonomous task signal into
the compliance worker. Then run:

```bash
python3 "${DATARIM_RUNTIME:?}/dev-tools/evolution-route.py" --root "$DATARIM_ROOT"
```

The JSON response contains `scope` (`framework` or `consumer`) and
`auto_apply` (boolean). Exit 2 is a configuration refusal: defer all pending
proposals and record the reason. An absent config defaults to `true` in these
two autonomous routes. `datarim/config/evolution.yaml` containing exactly
`auto_apply: false` disables application without suppressing decisions or
logging. Interactive runs present proposals and ask for a decision.

## Decide each proposal

For each proposal, evaluate recurrence (including the anti-self-suppression
check), impact, blast radius, reversibility, current evidence, and the gates
required for its target. Write a reasoned `apply`, `decline`, or `defer`
decision. A failed prerequisite, uncertain target, unavailable reviewer, or
disabled automatic application is `defer` with the exact reason. A proposal
with evidence that its change is unsuitable is `decline`. Never report a
proposal as applied from an intention or a passing check alone.

Class B requires a written PRD update or equivalent project contract draft
before implementation and concurrence from an independent blind reviewer in a
separate agent context that did not author the change. A missing or negative
review defers the proposal. Class A needs the same technical gates but no
extra contract review.

## Target and transaction

For `framework`, work only in an isolated feature branch of the framework
source. Keep the PRD and its Class B implementation in the same commit. Sign
commits, open a PR, and use normal review and CI. Do not turn a local test into
a claim that the PR was merged.

For `consumer`, keep every edit inside that workspace. Executable changes
belong in project-owned `datarim/local/{skills,commands,agents,templates,dev-tools}/`,
mirroring the relative upstream path. New paths are allowed. After all proposal gates pass, write vetted bytes to a temporary input file,
then use the bounded consumer writer:

```bash
python3 "${DATARIM_RUNTIME:?}/dev-tools/evolution-write.py" \
  --root "$DATARIM_ROOT" --source "$DATARIM_SOURCE" \
  --relative "commands/example.md" --input "$PROPOSAL_FILE"
```

The writer refuses framework source workspaces and disabled auto-apply,
registers new base hashes, and only writes the project overlay. The agent
then runs the project's normal `update.sh` transaction and verifies the
composed runtime and adapters. For hand edits, create the overlay file and
register it with `scripts/local_overlay.py add`.

Use the fetch-only source path recorded in the installation manifest for
`DATARIM_SOURCE`; if that clone moved, resolve its current path. The manual
registration helper reads that path from the manifest when available. Register only a new entry; to change an existing override preserve its
recorded base hash. Keep `datarim/local/manifest.json` and the overlay files
tracked by the consumer project (use `git add -f` if project ignore rules
require it). Update the runtime through the project's normal `update.sh`
transaction; never edit `.datarim-runtime` directly. A project rule may also
be written to project-owned `AGENTS.md`. Never edit or push the public
framework repository from a consumer run. For every reusable consumer
proposal, log `promotion: candidate` separately from its local decision,
including when the local decision is `applied`.

Build each proposal in an isolated candidate checkout or copied project fixture,
not in the live instruction surface. Save the live target's exact original
bytes and list every path the proposal owns. Run stack-agnostic,
history-agnostic, and English-only gates against candidate bytes. Run Bats
tests that read every changed candidate file, then the full Bats suite once,
sequentially, against that candidate tree. A failing gate or test discards the
candidate and records `declined: gate <name> failed`; no live target write
occurs. Only a fully passing candidate may be copied into the framework
branch or consumer overlay. Verify copied bytes match the tested candidate.
If publication or post-copy checks fail, restore only that proposal's exact
original bytes and remove only its newly created files; preserve unrelated
work. Never leave a partly applied proposal. Recheck the final diff before
committing.

## Record and report

Append every decision to `datarim/history/evolution-log.md` in the KB where
the task ran. Include date, proposal number and class, incident class,
decision, rationale, evidence, gate outcomes, target scope, local commit or
PR when available, and independent-review reference for Class B. For a
consumer proposal, record the distinct framework promotion status. Update
the proposal's reflection `Status` to `applied`, `declined`, or `deferred`,
preserving its previous text in the decision log. The run summary lists each
decision and its evidence; it does not request pending approval in autonomous
mode. Interactive runs retain the present-and-ask path.

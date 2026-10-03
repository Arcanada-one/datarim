# Native Datarim integration

## One authority

The source skill is `skills/human-outcome-reporting/SKILL.md`. Every native command
entry point loads this policy through the common project preamble. The system
rule also applies it to delegated human-facing output and plugin execution.
`human-summary` retains its four-heading presentation and Stop-hook tokens;
its semantic rules delegate here. Emit one recap, not two.

## Project and task sources

Use the existing explicit project resolver before reading task state. Read the
task's original init-task brief and amendments, task-description, referenced PRD
and plan, expectations checklist, QA and customer-delivery evidence relevant to
the stage. Resolve the actual pointers; do not invent a plan path. Missing sources
are disclosed, not silently synthesized from the previous chat.

For substantive acceptance claims, map original requirements to criteria, plan
steps, outcomes and evidence in a reporting projection. Keep the original closed
frontmatter schemas unchanged. Save the projection and an explicit source snapshot
only in the task's existing authorized report area, with task/run-specific names.
Snapshotting source bytes does not prove semantic extraction completeness.

## Finalization

Run the bundled validator and gate over the reporting projection before issuing a
substantive success claim. A valid negative gate produces an honest partial report;
it does not suppress communication. Include canonical native gate results rather
than overriding them. Report actual subject revision and verification environment.
Never turn a source audit into a live service or agent-behavior success claim.

The deterministic engine is optional for small questions and short progress text;
the truthfulness and readability policy is not. Preserve exact JSON-only streams,
requested artifact-only output, installation questions and machine handoffs. The
primary agent presents delegated facts; subagents do not append chat reports to
machine records. `/dr-explain` performs reading and explanation only.

## Installation and graph

Keep Datarim's native project-local installer. It copies skill support files into
the pinned runtime and generates client entry points. Do not add global rules or
modify the consumer's shared AGENTS.md to force activation outside Datarim.
Fresh installations retain all required user choices. Test fresh install and update
in disposable consumer fixtures, not inside the framework source checkout.

Register `/dr-explain` in the command graph, then regenerate the framework graph
and both visual maps using the native generator. Do not hand-maintain a duplicate
canonical registry. A coverage audit detects commands lacking the shared policy.
Plugin human-facing output follows the same rule; protocol-only plugin streams
remain exact. Discovery is not proof that a live model followed the instructions.

## Source-binding and finalization commands

`scripts/native.py` is read-only. Supply an explicit authorized consumer project,
not the Datarim source checkout. All input file arguments below are relative to
that project. The source-selection document has exactly `sources` (an array of
`path` and `role`) and `requirement_sources` (every requirement ID mapped to one
or more selected source paths). Required roles are `task_brief`, `task_description`,
and `plan` when plan steps exist. Optional roles are `prd`, `expectations`,
`verification`, and `glossary`. A glossary cannot be the source of a requirement.

```text
python3 <skill>/scripts/native.py snapshot --project <project> --contract <contract.json> --selection <sources.json>
python3 <skill>/scripts/native.py verify --project <project> --contract <contract.json> --snapshot <source-snapshot.json>
python3 <skill>/scripts/native.py finalize --project <project> --contract <contract.json> --snapshot <source-snapshot.json> --report <report.json>
```

The first command prints a source snapshot; the caller persists it only in an
already-authorized task report area. Finalize verifies the current source bytes,
contract binding, report links, evidence and language lint. It prints a complete
human report for both a verified and a valid incomplete result. Exit codes are 0
for checks complete, 3 for valid incomplete, and 2 for invalid inputs or language
findings. Never replace the negative report with a success message. Re-reading
sources and rendering do not execute new checks. Hashes are not signatures.

## Compatible four-section presentation

QA, compliance and archive retain the four `human-summary` sections and existing
Stop-hook tokens. Their source instructions no longer impose a hard word cap.
Completeness before brevity applies to the entire recap: disclose each material
negative condition, risk, exclusion, unanswered question and verification gap.
The full renderer has no word cap either. For a large task, an explicitly short
chat view may summarize positive items only when a complete readable report is
available in an already-authorized location. Otherwise include the needed detail
in chat. Do not rewrite immutable archives or create an unauthorized report file.
One human recap replaces duplicate technical narration; native verdict records,
exact machine protocols, CTA syntax and the installed Stop hook remain intact.
A successful stage verdict alone is not proof that the product is ready.

## Release checks

Verify source coverage, reference integrity, schema and negative status cases,
source drift, re-explanation invariants, legacy recap compatibility, native graph,
and generated runtime payloads for each supported client. Preserve install
questions, permissions and JEV configuration. Run live client and cold-reader
evaluations separately and mark unavailable checks as not run. Package only the
release file allowlist; exclude credentials, private receipts, caches and logs.

For a substantive report, use `${DATARIM_RUNTIME:?}/templates/human-outcome-report-template.md`. Keep the existing archive and compliance templates for their respective stage artifacts.

# Data model, verification and trust boundaries

The portable `scripts/hr.py` tool validates a reporting projection, computes
acceptance coverage, renders Russian text and exports its task graph. It consumes
execution receipts from the authorized verification workflow; it does not run
commands or write files. Runtime dependencies are Python 3.10+ and the standard
library. The three schemas are shipped beside the script.

The contract contains task context and goal, source-attributed requirements,
criteria with verification methods, plan dependencies, questions and approval.
The report contains one run, subject revision, outcomes, checks, evidence, plan
progress, answers, blockers, risks, usage and delivery. It does not accept a
self-declared success flag as proof of completion.

`validate` checks structure and graph integrity. `gate` assesses the evidence
policy: exit 0 means checks complete over supplied data; exit 3 means incomplete;
exit 2 means invalid input. Neither exit 0 nor a hash means human acceptance.
`render` produces a readable report even for a valid negative result. `--strict-human`
adds heuristic lint; it does not measure reader comprehension.

The `prose-spacing` warning detects obvious Cyrillic word-number joins and a closed
set of English count-unit and month-year joins in prose. It excludes Markdown code,
literal blocks, links' destinations and recognizable identifier surfaces. Spacing
warnings never rewrite input, suppress the report or change the command's exit code;
other lint findings keep their existing behavior. This is a bounded heuristic, not
a grammar checker. Keep ambiguous canonical names in inline code rather than
changing their bytes to satisfy the warning.

Treat `not_run` and `skipped` as unverified. Keep contradictory active checks in
conflict. Partial verification is partial. Evidence for a different revision,
environment or run does not establish the current result. Excluded criteria need
an explicit authorization record, and exclusions do not increase success counts.
An empty denominator does not prove readiness.

A receipt binds command metadata and output hashes to a check. Hash integrity does
not authenticate the executor or prove the command meaningfully tested a criterion.
A command that simply returns zero is not a user-scenario test. Protect the
contract baseline in a trusted ledger and review test-to-criterion semantics.
Manual and research evidence also need an appropriate independent authority.

The native source snapshot binds explicit canonical source files to their bytes.
This prevents silent source drift but cannot prove that the agent extracted every
requirement correctly. Native traceability, customer-delivery gates and human
acceptance remain authoritative. Do not create a second source of project truth.

Raw logs may contain secrets. Only pass authorized, redacted evidence. The tool
rejects path escapes and symlinks but is not a security sandbox. Reporting never
relaxes process permissions, hard gates, or independent security review.

Structured text rejects terminal commands and invisible controls that can hide or
reorder a verdict, including bidi overrides and isolates. Direct rendering exposes
these bytes as visible code-point markers; lint flags unsanitized input. Normal
whitespace and natural-language joiners remain usable. These display protections
do not authenticate facts or guarantee that a model will resist every injection.

The source code's schema checker supports the vocabulary used by these bundled
schemas, not the whole JSON Schema standard. Independent schema validation and
negative tests belong in development. Live agent behavior and cold-reader studies
are separate evaluations; synthetic test success must never be relabeled as either.

# Human Outcome Reporting

Human Outcome Reporting 0.3.0 is integrated into Datarim 4.3.0 and can be installed independently. It explains the original need, the observed user-visible outcome, acceptance evidence, delivery state and material open conditions without requiring the previous conversation.

Natural prose keeps spaces between words and numbers, dates, roles and measured units. Conciseness never means removing word boundaries. The advisory `prose-spacing` lint flags obvious compression outside literal code, paths and identifiers; it never rewrites canonical names. Passing this heuristic does not prove that every report is readable.

The working relationship is goal → requirement → criterion → plan step → outcome → verification → evidence. Work performed, criterion verified, result delivered and human acceptance remain distinct. A completed plan does not establish that the user scenario works.

## Use in Datarim

The authority is [SKILL.md](../../skills/human-outcome-reporting/SKILL.md). Global framework instructions and the system skill apply it to all 29 commands and delegated human-facing output, including plugin results. Machine handoffs retain their protocols.

`/dr-explain` re-explains a result or one unfamiliar term using authorized original sources. It does not run tests, change code or a glossary, publish a product, or close a task. Acknowledging understanding is not acceptance. An incorrect previous claim is corrected explicitly. The command's read-only boundary is in its body as well as frontmatter so client wrappers preserve it.

Use the [report template](../../templates/human-outcome-report-template.md) for substantive work. `human-summary` remains the four-section presentation for QA, compliance and archive; it is not a competing reporting authority. Its hard word cap is removed so failures and unmeasured conditions cannot disappear for brevity.

## Language preferences

Reply language and generated artifact language resolve independently, with English
fallbacks. Personal preferences and shared/private project choices are read by one
[resolver](../reference/language-preferences.md), also shipped in standalone
reporting. See [configure languages](../how-to/configure-languages.md). Fixed
renderer labels use validated catalogs and disclose English fallback when a
catalog is unavailable; source prose, quotations and machine values remain intact.

## Standalone installation

Follow the [installation guide](../how-to/install-human-outcome-reporting.md) for Claude Code, Codex and Cursor. The complete skill directory includes references, schemas, scripts and portable tests. No Datarim runtime or task directory is required; use the host agent's authorized sources. Host installation affects only communication policy and skill discovery. It does not install the framework, `/dr-*`, Jev, credentials, permissions or model routing.

Instructions need no Python. Read-only tools need Python 3.10+ with no external runtime dependencies. They read explicit inputs and print results; they never execute test commands.

## Verify the portable archive

From the extracted package root:

```bash
python3 -m unittest discover -s human-outcome-reporting/tests -v
python3 human-outcome-reporting/scripts/hr.py --version
python3 human-outcome-reporting/scripts/hr.py render --contract examples/partial/contract.json --report examples/partial/report.json --evidence-root examples/partial --strict-human
```

The example is synthetic: one of two conditions has evidence; the other is unmeasured. It is not proof of a working production service.

`validate` checks structure and relationships. `gate` returns 0 when supplied records satisfy the verification policy, 3 for a valid incomplete result and 2 for invalid input. `render` communicates negative and incomplete outcomes. `--strict-human` is a text heuristic, not proof of understanding. `graph` exports the task projection, not a new canonical framework graph.

`--max-age-hours` is a finite positive freshness limit. Both the stated outcome date and execution-receipt end time are checked: a new summary cannot make an old test current. `native.py` offers `snapshot`, `verify` and `finalize` to bind explicitly selected source bytes. Hashes do not authenticate the executor or prove complete requirements extraction. Receipts must come from authorized verification, never invented JSON.

## Profiles and evaluation

The 11 profiles are feature, bugfix, refactor, research, review, planning, operations, documentation, security, release and utility. The five communication moments are progress, final, blocked, handoff and answer. Normal and re-explain are independent presentation modes. Ordinary questions, translations, code-only responses and exact JSON are not wrapped in artificial reports.

See [technical specification](TECHNICAL_SPEC.md), [research](RESEARCH.md), [evaluation protocol](EVALUATION_PLAN.json), [acceptance notes](ACCEPTANCE_REPORT.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Live model observations and blind agent reader checks must be reported separately from deterministic tests and real human studies.

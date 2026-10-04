---
task_id: {TASK-ID}
date: {YYYY-MM-DD}
verdict: {COMPLIANT|COMPLIANT_WITH_NOTES|NON-COMPLIANT}
scope: {optional one-line scope description}
---

<!-- gate:literal -->
<!-- Evidence loop: cite acceptance.json, evidence.json, the exact strict
check-live-evidence.sh --stage compliance invocation/result, tested revision,
scope and artifact hashes, independent reviewer identity, and every pending
later-stage case. STAGE_PASS is not full task delivery. Missing, stale, failed,
or mock-only required live evidence is NON-COMPLIANT, never notes. -->

<!-- Cite the immutable workflow.route and its canonical task type/complexity.
Require receipts only for the selected route; canonical L3/L4 compliance stays
mandatory, including content. Pending publication is not an accepted publish. -->
<!-- /gate:literal -->

# Compliance report: {TASK-ID} — {Title}

<!-- Generate prose and display headings in the resolved artifact language.
     Preserve markers, frontmatter, enum values, evidence and verbatim quotes.
     Chat uses the independent reply preference. -->

## Original request <!-- datarim:original-request -->

{One plain-language sentence describing the operator's request. Source:
`tasks/{TASK-ID}-init-task.md` Operator brief (verbatim), paraphrased faithfully.}

## How it was resolved <!-- datarim:resolution -->

{Single-level bullet list, one item for each operator-brief bullet in its
original order. Fold expectations into the same list with a localized
"brief clarification" marker. No tables or nested bullets. Translate status
presentation (fulfilled, partly fulfilled, unfulfilled, not applicable) while
preserving exact schema enums in technical records. Explain evidence and limits.
Apply the Russian banlist only when this artifact's prose is Russian.}

- **"{verbatim brief item 1}".** {human-readable status}. {Outcome, evidence and remaining limitation.}
- **"{verbatim brief item 2}".** {human-readable status}. {Explanation.}
- **"{expectations item}" (brief clarification).** {human-readable status}. {Explanation.}

## Task artifacts <!-- datarim:artifacts -->

{What was created, changed or confirmed; relative paths and evidence links.}

## Next steps <!-- datarim:next-steps -->

{State that all authorized work is complete only when supported; otherwise
list specific remaining conditions and authorized next actions.}

---

## Audit addendum <!-- datarim:audit -->

### Step-by-step verdicts

<!-- gate:literal -->
| Step | Verdict | Notes |
|---|---|---|
| 1. Re-validate vs PRD/task | {compliant|notes|non-compliant} | {summary} |
| 2. Simplify code | {compliant|notes|non-compliant} | {summary} |
| 3. Check references | {compliant|notes|non-compliant} | {summary} |
| 4. Coverage | {compliant|notes|non-compliant} | {summary} |
| 5. Lint | {compliant|notes|non-compliant} | {summary} |
| 6. Tests | {compliant|notes|non-compliant} | {summary} |
| 7. Final verdict | {COMPLIANT|COMPLIANT_WITH_NOTES|NON-COMPLIANT} | {summary} |
<!-- /gate:literal -->

### Remaining risks

{Risks still open after compliance; state none only when confirmed.}


### Related

- Task: `datarim/tasks/{TASK-ID}-task-description.md`
- PRD: (path or none)
- Plan: (path or none)
- QA report: (path or none)
- Archive: (path or none — filled in after `/dr-archive`)

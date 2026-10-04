---
id: {TASK-ID}
title: {short title, ≤80 chars}
status: archived
completed_date: {YYYY-MM-DD}
complexity: L{1-4}
type: {framework|infra|content|bugfix|...}
project: {project name}
related: []
archive_doc: documentation/archive/{subdir}/archive-{TASK-ID}.md
generated_by: {concrete model id that wrote this body, e.g. deepseek-v4-pro — omit the block entirely if a human wrote it}
generated_at: {YYYY-MM-DDThh:mm:ssZ}
generated_via: {optional — how the model was reached, e.g. a service route or a delegation tool}
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: false
  dogfood_window: "{window-id}"
---
<!--
generation-provenance field semantics:
- generated_by: the concrete model id, verbatim as the provider names it — not a tier.
  A tier is an intent and can be re-pointed later, which would silently rewrite what
  this artefact claims about its own past. Drop all three keys when a human wrote the body.
- generated_at: RFC 3339 / ISO 8601 timestamp of the generating call.
- generated_via: optional route (service address, command-line tool, delegation tool) for the cases where
  the same model behaves differently through different transports.
- Why record it at all: to make "the cheap tier writes weaker artefacts" a measurable
  claim. Without the model on the artefact, a re-run on a stronger model is an
  impression; with it, the two are comparable.
- This is deliberately NOT the `model:` key used on the instruction surface — that one
  selects which model to RUN, and a concrete id there is a hard validation failure.

verification_outcome field semantics:
- caught_by_verify: integer count of high/medium gaps caught BEFORE /dr-archive
- missed_by_verify: integer count of gaps that escaped /dr-verify and required post-archive followup
- false_positive: integer count of findings flagged by /dr-verify that were triaged as not real
- n_a: boolean, true when /dr-verify was NOT run; when true, the three counts above MUST be 0
- dogfood_window: active prospective-measurement window identifier; grouping key for measure-prospective-rate.sh
Canonical contract — skills/self-verification/SKILL.md § Findings Schema.
-->

# Archive: {TASK-ID} — {Title}

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

### verification_outcome

{Human-readable mirror of each verification_outcome counter and dogfood_window.}

### Acceptance Criteria

| AC | Status | Evidence |
|---|---|---|
| AC-1: {description} | {pass/fail/partial} | {link or summary} |
| AC-2: {description} | {pass/fail/partial} | {link or summary} |

### Lessons Learned

{Digest of at most three lessons; full text in `reflection-{ID}.md`.}

### Operator Handoff

{Remaining artifacts, deferred improvements or next-owner actions; state none only when confirmed.}


### Related

- Parent PRD: (path or none)
- Plan: (path or none)
- Reflection: (path or none)
- Follow-ups: (task IDs or none)

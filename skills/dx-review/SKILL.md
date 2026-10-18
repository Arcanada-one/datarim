---
name: dx-review
description: Review developer-facing journeys from installation through first accepted result and recovery.
model: inherit
current_aal: 1
target_aal: 2
---

# Developer Experience Review

Use this review for a developer-facing product surface: installation, setup,
configuration, API, CLI, SDK, documentation, upgrade, or contributor workflow.
The review records what a person must do to reach a first accepted result and
how they can recover when a step fails. It does not claim broad product quality,
market demand, or adoption.

## Applicability

Decide UI and developer-experience applicability independently for the current
change. Record `applicable` or `not-applicable` for each. A not-applicable result
must include a concrete reason. If both are not applicable, record that result
and do not invent a journey.

For an applicable developer journey, fill in the evidence contract described
below and validate it with:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
TASK_ID="example-task"
python3 "${DATARIM_RUNTIME:?}/dev-tools/check-ui-dx-evidence.py" \
  --root "$REPO_ROOT" \
  --evidence "$REPO_ROOT/datarim/qa/$TASK_ID/ui-dx-evidence.json"
```

The checker is read-only. It verifies the schema, source revision, applicability,
required state and journey fields, evidence labels, and prohibited inputs. It
does not verify that a cited observation is true; the reviewer must inspect the
referenced material and keep unsupported claims separate.

## Reviewer persona

Work as a developer trying to complete the documented task with the supplied
product and documentation. Ask what the person needs at each step, what signal
confirms progress, and what safe next action exists after failure. Keep the
review bounded to the declared product surface and journey.

Record the persona in practical terms:

- **Role:** the kind of developer who uses this surface.
- **Goal:** the first accepted outcome they need to reach.
- **Starting point:** what they have before beginning.
- **Constraints:** relevant environment, access, or prior knowledge.

Do not invent a customer interview or claim a representative population.

## Evidence labels

Every evidence reference must use one of these labels:

- `observed` — directly seen in a named run, artifact, or source path.
- `reported` — stated by an identified source but not independently observed.
- `estimated` — an explicit estimate with its basis and uncertainty.

Keep these labels distinct. Estimated or reported material cannot be described
as an observed result. Cite a stable, reviewable reference for every state or
journey claim.

## Journey trace

Review these four checkpoints in order:

1. **Install:** the person can find and complete the supported installation
   route, or see the exact prerequisite that prevents it.
2. **Configure:** the person can supply the required settings and tell whether
   they were accepted.
3. **First accepted result:** the product makes the first valid outcome
   recognizable and gives the next useful action.
4. **Recover:** after a failed step, the person receives a concrete diagnosis
   and a safe route to resume or retry. A generic link to documentation does not
   count as a recovery path unless it identifies the matching action.

Record the path to the first accepted result and the recovery path. Do not
substitute time-to-hello-world, adoption counts, or an unsupported success rate.

## Eight review passes

Review every pass or mark it not applicable with a reason:

1. Getting started and prerequisites.
2. API, CLI, or SDK entry points.
3. Error messages and recovery actions.
4. Task-focused documentation and examples.
5. Upgrade and compatibility path.
6. Local development environment and feedback loop.
7. Community support and contribution route.
8. Measurement plan, including what evidence would support a future claim.

These passes organize review coverage; a completed pass is not evidence of a
successful user outcome by itself.

## Review modes

Choose one mode and record why it fits the change:

- `expansion` — a new capability or audience path is being added.
- `polish` — an existing path is being clarified or made easier to complete.
- `triage` — a known journey failure is being localized and routed for repair.

## Structured evidence contract

Write one UTF-8 JSON object using schema `DatarimUiDxEvidence/v1`. It binds to
the reviewed source `HEAD` with a full 40- or 64-character Git commit ID. Keep all evidence
under the repository's task QA area. The object has these top-level members:

- `schema`, `source_revision`.
- `ui`: `applicability: {status, reason?}` and `features`.
- `dx`: `applicability: {status, reason?}`, `mode`, `persona`, `stages`, and
  `passes` when applicable. For a not-applicable DX result, only
  `applicability` is present.
- `inputs`: typed evidence sources used by the review.
- `retained_material`: any retained third-party wording, with section, source,
  license, notice path, and a `modified` boolean.

Use `applicable` or `not_applicable` for applicability status. When UI is
applicable, each feature has an identifier and all five states:
`loading`, `empty`, `error`, `success`, and `partial`. A present state records
its `status`, trigger, feedback, next action, evidence type/path/digest, and
rubric score. A missing state records a reason and evidence, then scores zero.
A not-applicable state gives a reason. Evidence has exactly a `type` (`observed`,
`reported`, or `estimated`), a repository-relative artifact `path`, and its
SHA-256 digest. Artifacts live in the same task's immutable
`datarim/qa/<task-id>/run-<UTC>/` directory as the review. A present error state
must name its recovery action in `action`.

When developer experience is applicable, `stages` contains exactly one entry
for `install`, `configure`, `first-accepted-result`, and `recover`, in that
order. A present entry records `does` and a typed, digest-bound artifact
reference. A missing entry gives a reason and evidence. The first accepted
result names its `acceptance_signal`; the recovery entry also names
`recovery_action`. `passes`
records these exact eight names in order: `getting-started`, `api-cli-sdk`,
`errors`, `documentation`, `upgrade`, `development-environment`, `community`,
and `measurement`. Each is `reviewed` with typed evidence or `not_applicable`
with a reason.

`inputs` contains `{kind, reference}` records. Supported kinds are
`design-source`, `observed-run`, `reported-source`, and `estimate-basis`.
Input kinds `adoption-statistic` and `designer-binary` are prohibited and make
validation fail. `retained_material` contains `{section, source, license,
notice, modified}` records; every field is required and `modified` is boolean.
Use an empty array when no third-party wording is retained. An unattributed
entry is rejected; do not retain material whose source or license cannot be
established. Project source and attribution records are maintained in the
applicable `THIRD_PARTY_NOTICES.md`.

The UI rubric uses three levels: `0` absent or contradictory, `1` named but too
vague to verify, `2` specific and testable. Report the lowest applicable cell
score without averaging. This is a design-review rubric only; it is not a
measured UX result.

## Limits

A passing structural check proves that the submitted evidence follows this
contract at the pinned source revision. It does not prove that the evidence is
true, that users succeeded, that usability improved, or that the product is
adopted. Keep those claims `not-measured` until independently supported.

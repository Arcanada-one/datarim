# UI/DX Evidence Validation Summary

`dev-tools/check-ui-dx-evidence.py` validates the existing task-scoped UI/DX
evidence. Add `--summary-json` to emit one deterministic JSON object on stdout
instead of the default text output:

```sh
python3 dev-tools/check-ui-dx-evidence.py \
  --root /path/to/project \
  --evidence /path/to/project/datarim/qa/example/ui-dx-evidence.json \
  --summary-json
```

The option invokes the same validation path once. A valid `PASS` or
`NOT_APPLICABLE` result exits `0`; a validation refusal exits `1`. Without the
option, the existing text output, stderr detail and exit behavior are
unchanged. Argument-parsing errors occur before validation and retain argparse's
normal usage output and exit status.

## Portable JSON Schema

The machine-readable [Draft 2020-12 schema](schemas/ui-dx-evidence-summary.v1.schema.json) describes the exact summary field shape, fixed values and diagnostic-code domain. It requires all eight fields, rejects additional properties, and preserves `NOT_MEASURED` values as JSON `null`. It also describes the emitted result/exit/diagnostic relationships.

The schema checks structure only. It cannot establish that a revision or digest is truthful, that evidence is authentic, or that the validator's conclusions are semantically correct. It does not establish UX quality, adoption, runtime behavior, task acceptance, or permission to change a gate.

## Schema

The JSON line has exactly these top-level fields:

| Field | Meaning |
|-------|---------|
| `schema` | `UIDXEvidenceValidationSummary/v1`. |
| `result` | `PASS`, `NOT_APPLICABLE`, or `FAIL`. |
| `exit_code` | Numeric validator status: `0` for a valid result, `1` for refusal. |
| `diagnostic_codes` | Empty for a valid result; otherwise one fixed validator code. |
| `source_revision` | Availability/value object for the validated repository revision. |
| `evidence_sha256` | Availability/value object for the validated evidence bytes. |
| `lowest_rubric_score` | Availability/value object for the lowest validated UI score. |
| `notes_count` | Availability/value object for the count of validated structural notes. |

Availability/value objects have exactly `availability` and `value`. A measured
value uses `availability: "MEASURED"`; a value not established by completed
validation uses `availability: "NOT_MEASURED"` and `value: null`. In
particular, refusal does not fabricate zero scores or counts. A valid
`NOT_APPLICABLE` result has no rubric score, so its score is also
`NOT_MEASURED`/`null`; its validated note count is measured.

The summary contains no evidence paths, report or note text, exception details,
arguments, environment values, or secrets. Refusal codes are fixed identifiers
from the validator, including `invalid_json`, `invalid_shape`,
`missing_evidence`, `stale_source_revision`, `unsafe_evidence_path`, and the
existing UI/DX structural refusal codes. Unknown internal codes are reduced to
`validation_error`.

This read-only summary reports the validator's structural result only. It does
not establish evidence authenticity, UX quality, adoption, runtime behavior,
task acceptance, or permission to change tests or gates.

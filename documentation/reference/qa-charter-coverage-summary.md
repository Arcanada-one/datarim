# QA Charter Coverage Summary

`dev-tools/check-qa-charter-coverage.py` validates a QA charter against its
immutable run evidence. Add `--summary-json` to emit one JSON object on standard
output instead of the default human-readable line:

```sh
python3 dev-tools/check-qa-charter-coverage.py \
  --root /path/to/task-repository \
  --charter datarim/qa/example/qa-charter.md \
  --evidence datarim/qa/example/run-20261018T120000Z/evidence.json \
  --summary-json
```

The JSON mode uses the same validation and exit status as the default mode. It
does not write to the charter, evidence, or repository. Without `--summary-json`,
the existing text output and exit behavior are unchanged.

## Object fields

The top-level object has exactly these fields:

| Field | Values |
|-------|--------|
| `schema` | `DatarimQaCharterCoverageSummary/v1` |
| `verdict` | `PASS` or `FAIL` |
| `exit_code` | Numeric process status: `0` for pass, `1` for validator refusal. |
| `exit_code_meaning` | `pass` or `refusal`, matching `exit_code`. |
| `diagnostic_codes` | Empty on pass; one fixed validator diagnostic code on refusal. |
| `counts` | Named counts, each represented by `available` and `value`. |
| `checkpoint_linkage` | `PASS`, `FAIL`, or `NOT_MEASURED`. |

Each count value is either an integer with `available: true` or `null` with
`available: false`. A count is unavailable until the validator has enough fully
validated input to compute it. In particular, malformed or unreadable evidence
does not produce zero counts. The available counts are:

| Count | Meaning |
|-------|---------|
| `declared_probes` | Probes declared by a successfully parsed charter. |
| `required_probes` | Required probes in that charter. |
| `recorded_probes` | Evidence entries, available after the entire evidence list validates. |
| `missing_required_probes` | Required probes without evidence, computed after that list validates. |
| `optional_unrecorded_probes` | Optional probes without evidence, computed after that list validates. |
| `checkpoint_transitions` | Validated transitions in the checkpoint chains. |

`checkpoint_linkage` is `PASS` only after declared chains validate. It is
`FAIL` when chain validation refuses the supplied linkage, and
`NOT_MEASURED` when the evidence has no required chain or validation stops
before linkage is measured. A `NOT_MEASURED` value is not a pass.

## Diagnostic codes

The JSON contains only fixed diagnostic identifiers, never exception messages,
report values, or paths. Current codes are:

`artifact_digest_mismatch`, `checkpoint_cycle`, `checkpoint_probe_not_pass`,
`dangling_checkpoint_probe`, `dirty_source_tree`, `duplicate_checkpoint`,
`duplicate_key`, `duplicate_probe`, `invalid_charter`,
`invalid_checkpoint_chain`, `invalid_checkpoint_hypothesis`,
`invalid_checkpoint_relation`, `invalid_evidence`, `invalid_outcome`,
`invalid_root`, `missing_artifact`, `missing_charter`, `missing_evidence`,
`missing_checkpoint_chain`, `missing_required_probe`, `mutable_baseline_path`,
`out_of_order_checkpoint`, `required_probe_not_pass`,
`source_or_path_error`, `source_revision_unavailable`,
`source_tree_unavailable`, `stale_charter`, `stale_checkpoint_artifact`,
`stale_checkpoint_observation`, `stale_source_revision`, `unknown_probe`,
`unsafe_artifact`, `unsafe_charter`, and `unsafe_evidence`.

Invalid command-line usage is handled by `argparse` before validation and keeps
its standard usage output and exit status `2`; it does not emit a summary
object. The summary reports validator outcomes only and does not claim task
acceptance, runtime execution, or checkpoint linkage that was not measured.

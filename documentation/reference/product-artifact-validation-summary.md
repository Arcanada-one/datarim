# ProductArtifact validation summary

`dev-tools/check-product-artifact.py --summary-json` emits one compact JSON line for the selected `--artifact`, `--files`, or `--bundle` input. It uses the existing validation run and does not change artifact selection or acceptance policy. Without `--summary-json`, the checker retains its existing text output.

## Schema

The summary uses `DatarimProductArtifactValidationSummary/v1` with exactly these top-level fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimProductArtifactValidationSummary/v1` | Schema identifier. |
| `selection_mode` | `artifact`, `files`, `bundle` | Selected input form; input names are omitted. |
| `result` | `PASS`, `FAIL`, `NOT_MEASURED` | Structural validation result. |
| `exit_code` | `0`, `1`, `2` | Existing checker exit code. |
| `diagnostics` | Object below | Fixed diagnostic counts or explicit unavailability. |

`diagnostics` has exactly `availability` and `value`. After the checker validates the selected files, `availability` is `MEASURED` and `value` contains `count` plus `counts_by_code`. The count is the number of unique path-and-code diagnostics; paths are not serialized. A measured pass is an explicit known zero: `{"count":0,"counts_by_code":{}}`.

If a parsed root/input guard or empty-bundle check exits before validation, the summary reports `result: NOT_MEASURED`, `availability: NOT_MEASURED`, and `value: null`, while preserving the existing exit code. An unexpected diagnostic code also produces `FAIL` with `NOT_MEASURED` diagnostics; unknown codes and paths are withheld.

## Machine-readable schema

Consumers may validate this output shape with the local [Draft 2020-12 JSON Schema](schemas/product-artifact-summary.v1.schema.json). It captures the emitted field types, fixed diagnostic-code domain, and result/exit/diagnostic-availability branches. It cannot verify that `count` equals the sum of `counts_by_code`, recover redacted path/code pair uniqueness, or require lexical map-key ordering; it also makes no claim about artifact truth, acceptance, or runtime behavior.

## Diagnostic codes

Only these source-defined codes can appear in `counts_by_code`:

```text
E_ACCEPTANCE_INVALID E_ACTORS_INVALID E_AUTHORITY_INVALID E_AUTHORITY_REF_INVALID
E_AUTHORITY_REF_REQUIRED E_BUDGET_INVALID E_CLAIM_DERIVATION E_CLAIM_INVALID
E_CLAIM_RATIONALE E_CLAIM_UNKNOWN_REASON E_CONFLICT_COUNTEREVIDENCE_REQUIRED
E_CONFLICT_GROUP_INVALID E_CONFLICT_LINK E_COUNTEREVIDENCE_DUPLICATE
E_COUNTEREVIDENCE_REQUIRED E_DATA_FENCE E_DRAFT_OBSERVED_CLAIM
E_DUPLICATE_GROUP_INVALID E_DUPLICATE_GROUP_REQUIRED E_EVIDENCE_ACCEPTANCE_INVALID
E_FIELD_REQUIRED E_FIELD_TYPE E_FILE_READ E_FRONTMATTER E_ID_DUPLICATE E_ID_INVALID
E_INPUT_NOT_READY E_INPUT_SUPERSEDED E_KC_SELF_LABEL E_KEY_UNKNOWN
E_LEDGER_EMPTY_SEARCH E_LOCATOR_INVALID E_NO_MATCH_INCOMPLETE
E_OBSERVED_PROVENANCE_MISMATCH E_OBSERVED_RAW_REQUIRED
E_OPTION_DISPOSITION_REQUIRED E_OPTION_INVALID E_OPTION_REQUIRED E_OPTION_SELECTION
E_OUTCOME_INVALID E_PATH_SYMLINK E_PROVENANCE_INVALID
E_PUBLISHED_AT_BASIS_INVALID E_RANDOMIZATION_INVALID E_RECOMMENDATION_INVALID
E_REF_DIGEST_MISMATCH E_REF_INVALID E_REF_MISSING E_REVISION_INVALID
E_ROLEPLAY_AS_OBSERVED E_SCHEMA_VERSION E_SCOPE_DELTA_INVALID
E_SOURCE_DIGEST_INVALID E_SOURCE_DIGEST_MISMATCH E_SOURCE_ENTRY_INVALID
E_SOURCE_FAMILY_INVALID E_SOURCE_GROUP_INVALID E_SOURCE_UNAVAILABLE_INVALID
E_STATUS_INVALID E_SUPERSEDES_INVALID E_TEXT_FORMAT E_TIMESTAMP_INVALID
E_TYPE_INVALID E_USER_REPORTED_AS_OBSERVED E_YAML_INVALID
```

The summary contains no root or input paths, artifact names, IDs, content, repository URLs, arbitrary exceptions, environment values, or secrets. Argument-parser failures, `--help`, PyYAML import failures, and uncaught exceptions occur outside the JSON guarantee and retain their existing behavior. The summary describes structural checks only; it does not establish artifact truth, acceptance, demand, or runtime behavior.

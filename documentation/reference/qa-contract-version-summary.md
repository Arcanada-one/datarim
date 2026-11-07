# QA Contract-Version Summary

The contract-version checker can emit a fixed JSON result for the same validation it already performs. The output is opt-in and does not change the checker's acceptance rule.

## Invocation

```text
python3 dev-tools/check-qa-contract-version.py --contract <contract.json> --charter <charter.md> --summary-json
```

The checker reads each input once. Without `--summary-json`, it retains its existing human-readable output and exit status.

## Summary object

The object has exactly five keys:

| Key | Value |
|------|-------|
| `schema` | `DatarimQaContractVersionSummary/v1` |
| `result` | `PASS` or `FAIL` |
| `exit_code` | `0` for a successful existing check; `1` for a caught validation refusal |
| `version_binding` | `MATCHED`, `NOT_REQUIRED`, or `NOT_MEASURED` |
| `diagnostic_codes` | Empty on success; one fixed code for a refusal |

`MATCHED` means the checker's existing truthy `supersedes_version` comparison succeeded. `NOT_REQUIRED` means no supersession comparison was required because `supersedes_version` was absent or null. A caught refusal reports `NOT_MEASURED`; it does not claim a binding result.

The fixed diagnostic codes identify only source-defined branches:

| Code | Meaning |
|------|---------|
| `CONTRACT_READ_FAILED` | The contract file could not be read, including a read-time path `ValueError`. |
| `CHARTER_READ_FAILED` | The charter file could not be read, including a read-time path `ValueError`. |
| `INPUT_ENCODING_INVALID` | An input could not be decoded as UTF-8. |
| `CONTRACT_JSON_INVALID` | The contract text was read, but its JSON could not be parsed. |
| `CHARTER_BLOCK_COUNT_INVALID` | The charter did not contain exactly one `qa-charter-json` block. |
| `CHARTER_JSON_INVALID` | The JSON in the charter block could not be parsed. |
| `CONTRACT_VERSION_INVALID` | `contract_version` was not a nonempty string. |
| `SUPERSEDES_VERSION_INVALID` | A non-null `supersedes_version` was not a nonempty string. |
| `CHARTER_VERSION_MISMATCH` | A superseding contract and its charter had different version strings. |
| `STRUCTURE_INVALID` | A parsed JSON root did not support the checker's existing object access. |
| `VALIDATION_REFUSED` | A caught source-defined validation error had no more specific fixed code. |

Summary JSON contains no input paths, supplied version values, contract or charter content, exception detail, or argv. It reports only the existing version-binding check; it does not establish broader QA acceptance, evidence truth, or runtime behavior.

## Argument parsing limits

Argparse processes help and usage before validation. `--help` retains exit `0`; missing or invalid arguments retain exit `2`. These pre-dispatch outcomes do not emit the five-key summary. Process launch failures, signal termination, and errors outside the checker's caught validation exceptions are not represented by this output contract.

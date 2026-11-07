# Init-task validation summary

`dev-tools/check-init-task-presence.sh --task <TASK-ID> --summary-json` emits a fixed JSON object for the checker's existing single-task validation result. It uses the same validation decision and error counter as the ordinary command; it does not add validation rules. The option is not available with `--all`.

## Fields and outcomes

Every emitted object has exactly these six fields:

| Field | Contract |
|---|---|
| `schema` | `DatarimInitTaskValidationSummary/v1` |
| `result` | `VALID`, `INVALID`, or `INPUT_UNAVAILABLE` |
| `exit_code` | `0` for `VALID`; `1` for the two failure outcomes |
| `diagnostic_codes` | Empty for `VALID`; one fixed code for either failure outcome |
| `error_count` | Existing positive validation error count, `0` when valid, or `null` when the target is unavailable before validation |
| `error_count_status` | `MEASURED` for completed validation; `NOT_MEASURED` when the target is unavailable before validation |

`VALID` pairs with exit `0`, no diagnostic codes, count `0`, and `MEASURED`. `INVALID` pairs with exit `1`, `INIT_TASK_INVALID`, the checker's measured positive error count, and `MEASURED`. `INPUT_UNAVAILABLE` pairs with exit `1`, `INIT_TASK_FILE_UNAVAILABLE`, a `null` count, and `NOT_MEASURED`. The count is the checker's number of validation findings, not a count of unique diagnostic codes.

The summary contains no task ID, path, field value, argument, exception text, validation prose, or report detail. `--report` does not add prose when the summary option is selected. Without `--summary-json`, the existing human-readable behavior is retained.

## Example

```json
{
  "schema": "DatarimInitTaskValidationSummary/v1",
  "result": "INVALID",
  "exit_code": 1,
  "diagnostic_codes": ["INIT_TASK_INVALID"],
  "error_count": 2,
  "error_count_status": "MEASURED"
}
```

The summary reports the validator's structural result only. It does not establish that the brief is truthful, complete, semantically correct, admitted by KC2, or used by a later runtime. The validator currently reads the artifact in multiple existing validation operations; the summary does not claim single-pass input processing.

Argument parsing, help, version, `--all`, root resolution, signals, missing tools, and unhandled process failures are outside the JSON result contract and retain their command behavior. Missing `--task`, `--root`, or `--today` values and malformed task IDs/date syntax are usage errors; usage errors are not converted into a JSON validation result. A failed Q&A validator process exits `2` without a JSON result. Explicit root paths may contain spaces, tabs, and printable Unicode characters.

## Tool failures and rollback

The validator distinguishes a normal no-match from a failed command. A required heading search that returns `1` is a measured missing-heading finding and keeps the ordinary `INVALID` result. A heading search, frontmatter extraction, or validation-finding count operation that returns an execution error exits `2`; summary mode emits no JSON for that run. This preserves the distinction between a completed invalid artifact and a check that could not complete.

If this change causes an incompatibility after merge, use the repository's ordinary follow-up pull request path to revert the exact change commit (for example, with `git revert <change-commit>`), run the required checks on that revert branch, and merge the reviewed revert PR. Do not rewrite or force-push the protected branch. The revert restores the prior checker, tests, and reference together.

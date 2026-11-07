# QA run FAIL-lines validation summary

`dev-tools/check-qa-run-fail-lines.py --summary-json` emits one compact JSON line after the existing QA run FAIL-lines check. It uses the check's single result and does not execute commands described by the manifest. Without `--summary-json`, the checker retains its existing text output and exit codes.

## Output

The summary uses `DatarimQaRunFailLinesValidationSummary/v1` with exactly these top-level fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimQaRunFailLinesValidationSummary/v1` | Summary format identifier. |
| `result` | `PASS`, `FAIL` | Whether the existing checker accepted or refused the recorded FAIL-line mapping. |
| `exit_code` | `0`, `1` | Existing checker result: accepted or refused. |
| `diagnostic_codes` | Fixed string array | Empty for `PASS`; `RUN_VALIDATION_FAILED` for a refusal caught by the existing checker. |

Example accepted summary:

```text
{"schema":"DatarimQaRunFailLinesValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[]}
```

Example refusal summary:

```text
{"schema":"DatarimQaRunFailLinesValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["RUN_VALIDATION_FAILED"]}
```

## Limits

- The summary omits exception text, paths, log lines, manifest values, case identifiers, digests, arguments, and arbitrary diagnostics.
- The summary does not add counters or distinguish refusal causes. `FAIL` means only that the existing checker raised an exception in its current caught domain.
- `PASS` means the existing checker found no unexplained FAIL lines under its current rules. A manifest entry for a `failing_case` does not mean that the underlying case passed. A `harness_fixed` entry checks recorded response bytes against recorded reevaluation JSON; this command does not run a replay command.
- Argument parsing, `--help`, required-argument checks, path resolution, initial path-existence checks, imports, uncaught exceptions, signals, process-launch failures, and broken output pipes remain outside the JSON guarantee and keep their existing behavior.
- This is a privacy-preserving opt-in summary for this checker. It does not authenticate log evidence or establish QA, CI, task, or runtime acceptance.

Run summary mode with:

```sh
python3 dev-tools/check-qa-run-fail-lines.py --run-dir <run-directory> --manifest <manifest-path> --summary-json
```

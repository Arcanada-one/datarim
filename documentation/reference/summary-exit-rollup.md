# Captured Summary Exit Rollup

`aggregate-summary-exits.py` reads one bounded JSON array from standard input and reports the declared exit codes of its summary objects. It does not run a checker or validate the complete summary schema. Use it only after the summaries have been independently produced and validated by their own producer.

## Input

Pass a UTF-8 JSON array containing at most 256 objects. Standard input is limited to 64 KiB; the command reads at most one additional byte to detect an oversized input. Each object must have:

- `schema`: an ASCII identifier no longer than 128 characters, matching `Datarim` followed by one or more letters or digits, then `/v` and a positive version number;
- `exit_code`: the JSON number `0`, `1`, or `2`. An integer-valued decimal such as `1.0` is accepted exactly. Booleans and strings are not exit codes.

Other fields are opaque: they are not interpreted, copied to output, or used to invoke commands. Duplicate keys anywhere, non-finite numbers, malformed UTF-8 or JSON, non-object array entries, and invalid declarations refuse the complete input. No partial counts are returned.

## Invocation

The input must already be saved as one JSON array. This example builds a small local array file, then invokes the rollup without rerunning either checker:

```bash
set -euo pipefail
IFS=$'\n\t'
capture_dir="$(mktemp -d)"
trap 'rm -f "$capture_dir/summaries.json"; rmdir "$capture_dir"' EXIT
printf '%s\n' '[{"schema":"DatarimExample/v1","exit_code":0},{"schema":"DatarimExample/v1","exit_code":1}]' >"$capture_dir/summaries.json"
python3 dev-tools/aggregate-summary-exits.py <"$capture_dir/summaries.json"
```

The example data is illustrative only. In use, the array should contain the previously saved summaries whose independent producer checks have already completed. Do not substitute raw checker output or treat this command as a producer, validator, or acceptance gate.

## Output and process status

The command writes exactly one compact JSON object followed by a newline to stdout. The object has exactly seven fields: `schema`, `result`, `exit_code`, `diagnostic_codes`, `summary_count`, `summary_count_status`, and `exit_counts`.

| Result | Process status | Diagnostic codes | Counts |
|---|---:|---|---|
| `CLEAN` | 0 | `[]` | Measured; all declarations are zero. An empty array is a measured zero-count `CLEAN` result. |
| `FINDINGS` | 1 | `SUMMARY_FINDINGS_PRESENT` | Measured; at least one declaration is 1 and none is 2. |
| `ERROR` | 2 | `SUMMARY_ERROR_PRESENT` | Measured; at least one declaration is 2. This takes precedence when both 1 and 2 occur. |
| `INPUT_REFUSED` | 2 | `SUMMARY_EXIT_ROLLUP_REFUSED` | `summary_count` and `exit_counts` are `null`; `summary_count_status` is `NOT_MEASURED`. |

For measured results, `summary_count` is the array length, `summary_count_status` is `MEASURED`, and `exit_counts` contains exactly the string keys `0`, `1`, and `2`. The refusal object does not reveal a partial count or input value. On the handled input path, output is fixed JSON and stderr is empty. Argument parsing, help, and stdout I/O failures are outside this input-refusal contract.

## Scope and recovery

This is a declarative rollup of exit codes, not evidence that a checker ran, that a summary is truthful, or that a task was accepted. Keep the original producer results and validation evidence separately. In particular, a relay or producer with an unaccepted, undelivered, or review-changes result does not become accepted because its declared exit code was aggregated.

Changes should use a reviewed follow-up branch and pull request. If a released change must be reversed, preserve its evidence and submit a reviewed revert; do not edit a protected branch directly.

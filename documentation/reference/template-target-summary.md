# Template Target Validation Summary

The template target checker can emit a machine-readable summary with the opt-in `--summary-json` flag:

```sh
python3 dev-tools/check-template-targets.py --summary-json
```

The default output remains the text diagnostic list followed by `template targets: checked=N missing=M`. With the flag,
the command emits one JSON object and does not print individual diagnostics. Both modes use the same checker invocation
and preserve the existing exit codes: `0` means at least one eligible target was checked and all targets resolved;
`1` means at least one target was missing; `2` means no eligible targets were found.

## Completed-check object

Every completed check uses schema `DatarimTemplateTargetValidationSummary/v1` with these fields:

| Field | Meaning |
| --- | --- |
| `schema` | Fixed schema identifier. |
| `result` | `VALID`, `MISSING_TARGETS`, or `NO_TARGETS`. |
| `exit_code` | The process outcome for the completed check: `0`, `1`, or `2`. |
| `checked_count` | Number of eligible literal targets examined. |
| `missing_count` | Number of unresolved eligible targets. |
| `diagnostic_codes` | Empty for `VALID`, `MISSING_TEMPLATE_TARGETS` for `MISSING_TARGETS`, or `NO_TEMPLATE_TARGETS` for `NO_TARGETS`. |

Counts are nonnegative integers, including zero. A missing target makes the result `MISSING_TARGETS` even when other
targets resolved. No eligible targets produces `NO_TARGETS`, not `VALID`.

## Privacy and limits

The summary contains no target names, source paths or filenames, line numbers, source or manifest text, raw exceptions,
or command-line arguments. Use the default text mode when maintainers need the detailed diagnostics. The summary covers
completed checks only. Argument parsing, help, launch/import/dependency failures, signals, unsupported exceptions, and
broken output streams retain their existing process behavior and are not represented by this object. Input-read failures
are not normalized into a summary; the existing exception behavior is retained.

The summary describes literal target-reference validation. It does not establish that a template is semantically
correct, executable, selected at runtime, or accepted by a task or runtime admission system.

# Clean fixture — process-only prose

Runtime rules describe behaviour without naming historical incidents. This file
contains no task-ID provenance and should pass the gate cleanly.

## Workflow rule example

When parsing a CLI subprocess output, prefer machine-readable formats (`--json`,
`--output-format stream-json`) over regex-on-human-text. Documentation drifts;
structural fields are stable.

## Numeric tokens that are NOT task IDs

The gate must not false-positive on bare numbers like 25055434967 (CI run id),
0o600 (file mode), or 1.21.0 (version). Task IDs require letters-hyphen-four-digits.
The string AB-1 has too few digits. FOO-12345 has too many.

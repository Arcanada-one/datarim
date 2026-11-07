# Read a saved input-verification result

`dev-tools/format-input-verification.py` turns one saved
`DatarimCliInputManifestVerification/v1` JSON object into bounded, deterministic
text. It reads only standard input. It does not rerun the verifier, open any
path named in the report, call a producer, start another process, use a network
or model, or establish that the report is truthful.

## Use

Save the verifier's JSON output, then pass those bytes to the formatter:

```bash
set -euo pipefail
IFS=$'\n\t'
report_file="/path/to/saved-verification.json"
if python3 dev-tools/format-input-verification.py < "$report_file"; then
    format_exit=0
else
    format_exit=$?
fi
printf 'formatter exit: %s\n' "$format_exit"
```

The input file is supplied as quoted shell data; the formatter itself accepts no
path argument and never opens a report path. Treat both the printed text and
every value in the saved JSON as untrusted data.

## Result profiles

The formatter accepts exactly the seven fields in the verifier's result
contract: `schema`, `result`, `exit_code`, `diagnostic_codes`, `file_count`,
`file_count_status`, and `changed_paths`.

| Saved result | Formatter exit | Count | Changed paths |
| --- | ---: | --- | --- |
| `MATCHED` | 0 | Measured, integer 1–64 | Empty |
| `CHANGED` | 1 | Measured, integer 1–64 | One or more unique, sorted canonical relative paths |
| `INPUT_REFUSED` | 2 | `null` with `NOT_MEASURED` | Empty |

`INPUT_REFUSED` is a valid verifier result. Its unavailable count is displayed
as `NOT_MEASURED (unavailable)`, never as zero. The formatter does not expose
fields beyond this fixed contract. Integral decimal notation for the measured
count is checked with `Decimal` and accepted only when its exact value is an
integer in range; booleans and rounded values are not counts.

Changed paths are printed as one ASCII JSON string literal per line. Escaping
keeps control characters and embedded newlines from creating extra report
lines. This is syntax-safe display only: it does not make path text safe to
trust, interpret as a command, or forward into model context.

## Bounds and refusals

The formatter reads at most 2 MiB plus one byte to detect an oversized input.
It requires strict UTF-8, unique JSON keys, finite JSON numbers, an object with
the exact schema and profile correlations, and paths matching the verifier's
canonical-relative-path rules. Parser recursion exhaustion is refused.

It builds the complete output in memory under a 64 KiB cap before writing any
report bytes. If the input is malformed, inconsistent, too large, too deeply
nested, or cannot be rendered within the cap, it exits 2, writes no standard
output, and writes only the fixed diagnostic `INPUT_VERIFICATION_FORMAT_REFUSED`
to standard error. This formatter refusal is distinct from a valid saved
`INPUT_REFUSED` verifier result, which is rendered to standard output with its
declared exit code and empty standard error.

## Scope and follow-up

This is a standalone, opt-in presentation tool. Its output summarizes a saved
verifier result; it is not a new verification, source-review or delivery claim, semantic
truth, or delivery claim. It does not add a workflow, dependency, schema, or
integration with the verifier. If formatting is refused, preserve the saved
source report and inspect it through the owning verification process; do not
rewrite the report to make it pass. Reversing a later shipped change follows
the repository's ordinary reviewed rollback process.

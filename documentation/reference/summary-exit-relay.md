# Summary Exit Relay Reference

`relay-summary-exit.py` returns the `exit_code` declared by one bounded JSON summary after an independent validator has accepted that summary. It does not run the validator and does not decide what the declared status means.

## Invocation

```text
python3 dev-tools/relay-summary-exit.py --expected-schema <schema-id> < summary.json
```

`--expected-schema` is required. Supply the exact versioned identifier used by the independent schema validator. The identifier must be a bounded ASCII token beginning with `Datarim` or `datarim` and ending in `/v` followed by a positive version number. Schema comparison is exact and case-sensitive after the identifier passes that syntax check.

For example, when a validator has already accepted the summary against the existing skill-frontmatter summary contract, a consumer can relay that contract's declared status:

```bash
SUMMARY_FILE="/path/to/summary.json"
EXPECTED_SCHEMA="DatarimSkillFrontmatterValidationSummary/v1"

INDEPENDENT_SCHEMA_VALIDATOR --schema "$EXPECTED_SCHEMA" --input "$SUMMARY_FILE" && \
  python3 dev-tools/relay-summary-exit.py \
    --expected-schema "$EXPECTED_SCHEMA" < "$SUMMARY_FILE"
```

Replace `INDEPENDENT_SCHEMA_VALIDATOR` with the validator that actually checks the summary. The `&&` makes the relay conditional on that validator succeeding. Do not pipe a validator's output into the relay in place of the saved summary, and do not use the relay as a substitute for validation.

## Input contract

The utility reads standard input once, retaining at most 64 KiB plus one byte to detect overflow. The accepted input is exactly one strict UTF-8 JSON value whose top level is an object. It rejects duplicate object keys, invalid UTF-8 or JSON, trailing JSON values, `NaN`, infinities, and inputs larger than 64 KiB.

The object must contain:

- `schema`: a string exactly equal to `--expected-schema`;
- `exit_code`: a JSON integer or integer-valued decimal mathematically equal to `0`, `1`, or `2`.

Booleans and strings are not numeric exit values. For example, `1.0` is accepted and `true` is rejected. Other object fields are not interpreted or validated; they do not change the relayed status.

## Output and process status

| Outcome | Process status | Output |
|---|---:|---|
| Accepted summary | The declared `0`, `1`, or `2` | No stdout or stderr output |
| Missing, unknown, or malformed option | `2` | `ERROR: USAGE_ERROR` on stderr |
| Invalid expected schema identifier | `2` | `ERROR: INVALID_EXPECTED_SCHEMA` on stderr |
| Malformed, oversized, mismatched, or unsupported summary | `2` | `ERROR: INVALID_SUMMARY` on stderr |
| `--help` | `0` | Fixed command help on stdout |

Error output contains no input body, summary value, exception text, argument value, or filesystem path. The utility does not echo or execute summary fields. A caller should retain the upstream validator result separately from this process status.

## Scope and safety limits

This is a status relay, not a schema validator, checker, policy engine, or proof that any checker ran. It compares only the exact schema identifier and the allowed numeric `exit_code`. It does not enforce relationships among result, counts, diagnostics, or arbitrary extra fields. A successful relay means only that the supplied object had the accepted core envelope and that its declared status was returned.

Use the validator's documented input and output contract to establish that the summary was successfully validated before calling this utility. Preserve the validator's original status and evidence separately. Do not pass untrusted values through a shell command or use summary fields to construct commands.

## Change and recovery

Changes to the utility or this reference should use the repository's normal reviewed branch and pull-request path. If a released change needs reversal, preserve the failing evidence and submit a reviewed revert through that same path; do not edit a protected branch directly.

# Role-registry validation summary

Add `--summary-json` to `dev-tools/check-role-registry.sh` to emit a fixed summary of the existing single schema and cross-field validation pass.

The exact six fields are `schema` (`DatarimRoleRegistrySummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `validation_error_count`, and `validation_error_count_status`.

| Result | Exit | Diagnostic | Count |
|---|---:|---|---|
| `VALID` | 0 | `[]` | measured zero errors |
| `INVALID` | 1 | `ROLE_REGISTRY_INVALID` | measured positive error count |
| `INPUT_UNAVAILABLE` | 1 | `ROLE_INPUT_UNAVAILABLE` or `ROLE_VALIDATOR_UNAVAILABLE` | `null`, `NOT_MEASURED` |

Unavailable means that the roles input/schema or the existing `jsonschema` validator is unavailable. The summary does not include role IDs, YAML values, skill paths, arguments, exception text, or schema diagnostics. It does not change registry policy or validation rules. YAML/JSON/I/O and other unhandled failures, help, and parser errors retain their existing behavior and are not converted into summaries. A valid summary is not a claim of runtime authorization or agent quality.

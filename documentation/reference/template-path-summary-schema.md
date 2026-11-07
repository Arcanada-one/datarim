# Template-path summary schema

Use the local [Draft 2020-12 schema](schemas/template-path-summary.v1.schema.json) to validate the structure of a saved `DatarimTemplatePathConventionSummary/v1` object without running or installing the checker.

The exact six fields are `schema`, `result`, `exit_code`, `diagnostic_codes`, `offences_present`, and `offences_present_status`. The schema permits only `PASS`/exit 0/empty diagnostics/`false`/`MEASURED` and `FAIL`/exit 1/`TEMPLATE_PATH_CONVENTION_INVALID`/`true`/`MEASURED`. A scan with no files is a measured false result, not an unavailable result.

This is a structural consumer contract, not a path-policy engine or proof that a particular scan ran. It cannot establish input provenance or producer truth. The schema has no public identifier, remote references, custom vocabulary, or dependency on checker code.

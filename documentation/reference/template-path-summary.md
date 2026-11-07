# Template-path summary

Use `dev-tools/check-template-path-convention.sh --summary-json [--root <runtime-path>]` to emit one fixed result from the existing template-path scan. When combined with `--quiet`, summary JSON takes precedence. An omitted or empty root keeps the existing script-relative default.

The six fields are `schema` (`DatarimTemplatePathConventionSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `offences_present`, and `offences_present_status`. `PASS` is exit 0 with `false` and `MEASURED`; `FAIL` is exit 1 with `TEMPLATE_PATH_CONVENTION_INVALID`, `true`, and `MEASURED`. A completed scan of zero files is a measured false result.

The summary reuses the existing file collection and offence-output-file check. It does not count or parse rendered diagnostic lines, add a second scan, or widen the path rules. Summary output contains no absolute path, filename, or matched token. Missing roots, parser errors, help, and unhandled I/O/tool failures retain their existing non-JSON behavior. Enabling strict shell error propagation is documented only for those unhandled failures; no broader equivalence claim is made.

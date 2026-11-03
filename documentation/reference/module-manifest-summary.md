# Module-manifest summary

Use `dev-tools/check-module-manifest.sh --summary-json <path-to-module.yaml>` for one fixed summary of the validator's existing structural pass. A leading `--summary-json` selects JSON output; `--` may precede a positional path that starts with a dash.

The producer emits the existing `DatarimModuleManifestSummary/v1` contract. Its portable field definitions, result/count profiles, and limitations are documented in the [module-manifest summary schema reference](module-manifest-summary-schema.md), which links the already-shipped Draft 2020-12 schema.

The JSON object contains exactly eight fields: `schema`, `result`, `exit_code`, `diagnostic_codes`, `skill_count`, `skill_count_status`, `warning_count`, and `warning_count_status`. `VALID` is exit 0 with measured counts; `INVALID` is exit 1 with measured counts; a missing manifest is `INPUT_UNAVAILABLE`, exit 2, with both counts `null` and `NOT_MEASURED`. Warnings are counted only at existing warning sites and do not change a valid result.

Summary mode suppresses handled human diagnostics and emits no manifest identifiers, skill names, versions, paths, dependency names, or raw text. It uses the same shell/awk approximation and does not parse full YAML, resolve cross-plugin dependencies, or add a validation pass. Without the option, the supported positional invocation keeps its existing text and exit behavior. Parser, help, signal, tool, and unhandled failures are outside the JSON guarantee.

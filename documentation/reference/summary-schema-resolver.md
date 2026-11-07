# Resolve a declared summary schema

Use dev-tools/resolve-summary-schema.py to select a schema entry from a saved DatarimSummarySchemaCatalog/v1 document. Supply the catalog path with --catalog and one JSON summary on standard input:

    set -euo pipefail
    IFS=$'\n\t'
    python3 dev-tools/resolve-summary-schema.py --catalog saved-catalog.json <<'JSON'
    {"schema":"DatarimSkillFrontmatterValidationSummary/v1"}
    JSON

The resolver reads the summary's top-level schema string and matches it only against each catalog entry's literal summary_schema value. The identifier must match the ASCII pattern `^[A-Za-z][A-Za-z0-9._-]{0,127}/v[1-9][0-9]{0,3}$`. Other summary fields are ignored. It never picks the first match and does not infer identifiers from title, $ref, or allOf.

## Input limits

- The catalog must be an explicitly named regular file, no larger than 2 MiB. The final path component is opened without following a symlink and in nonblocking mode; if the platform lacks either required open flag, the resolver returns a refusal.
- Standard input is one UTF-8 JSON object, at most 64 KiB. Duplicate object keys and non-finite JSON numbers are refused.
- The catalog must have exactly the seven fields emitted by the catalog format, declare COMPLETE, exit code 0, no diagnostics, and a measured entry count from 0 through 256 that equals the entries array length.
- Each entry must contain exactly relative_path, sha256, title, dialect, and summary_schema. Paths must use the single-file namespace documentation/reference/schemas/<basename>.schema.json; paths must be unique. Digests must be lowercase SHA-256 strings. Optional metadata is a string of at most 256 characters or null.

A complete empty catalog is a measured catalog with zero entries. It produces NOT_FOUND for any valid identifier. A missing, refused, incomplete, malformed, or inconsistent catalog produces INPUT_REFUSED with unavailable match count.

## Result profiles

The JSON result has exactly seven top-level fields: schema, result, exit_code, diagnostic_codes, match_count, match_count_status, and selection.

| Result | Exit | Diagnostic codes | Match count | Status | Selection |
|---|---:|---|---:|---|---|
| MATCHED | 0 | [] | 1 | MEASURED | The exact five fields of the unique matching entry |
| NOT_FOUND | 1 | [SUMMARY_SCHEMA_NOT_FOUND] | 0 | MEASURED | null |
| AMBIGUOUS | 1 | [SUMMARY_SCHEMA_AMBIGUOUS] | Two or more | MEASURED | null |
| INPUT_REFUSED | 2 | [SUMMARY_SCHEMA_RESOLUTION_REFUSED] | null | NOT_MEASURED | null |

The fixed result schema identifier is DatarimSummarySchemaResolution/v1. Refusal output does not include raw paths, arguments, parser messages, or exception text. On a successful match, the declared relative path and catalog metadata are intentionally returned as data.

## Limits of this lookup

The resolver does not validate the summary against a JSON Schema, open or hash the selected schema file, establish that a digest matches any file, or prove that catalog metadata is semantically true. It reads only the caller-selected catalog file; it does not scan directories, access the network, start subprocesses, invoke a schema engine, or run a catalog producer.

The catalog producer is a separate staged change and remains unaccepted and unmerged. This consumer reads a saved catalog supplied by its caller and makes no claim that a producer command is installed or accepted. Parser/help failures and other process failures outside the handled JSON result path retain ordinary command-line behavior and are not normalized into a result profile.

# Summary schema catalog

`dev-tools/list-summary-schemas.py` lists the public JSON Schema files installed in a repository checkout. Use the relative paths to open a schema and its SHA-256 digest to identify the exact bytes in that checkout:

```sh
python3 dev-tools/list-summary-schemas.py
python3 dev-tools/list-summary-schemas.py --root /path/to/checkout
```

The default root is the repository parent of the script. The catalog reads only immediate `*.schema.json` entries in `documentation/reference/schemas/`. It does not recurse, follow symlinked schema directories or files, access network references, or invoke a schema validator.

## Output

The command writes one JSON object with exactly seven top-level fields:

| Field | Meaning |
|---|---|
| `schema` | Fixed format identifier `DatarimSummarySchemaCatalog/v1`. |
| `result` | `COMPLETE` or `INPUT_REFUSED`. |
| `exit_code` | `0` for a complete catalog or `2` for an input refusal. |
| `diagnostic_codes` | Empty for completion, or one fixed refusal code. |
| `entry_count` | Number of catalog entries, or `null` when not measured. |
| `entry_count_status` | `MEASURED` or `NOT_MEASURED`. |
| `entries` | Sorted schema entries; empty on refusal. |

Each complete entry has exactly `relative_path`, `sha256`, `title`, `dialect`, and `summary_schema`. The digest is computed from the bytes read for that entry. `title` comes from the top-level `title`, `dialect` from `$schema`, and `summary_schema` only from the literal `properties.schema.const` string. Missing, non-string, or overlong optional metadata is `null`; the command does not resolve `$ref`, `$id`, or `allOf` to infer values.

For example, a complete entry may look like:

```json
{
  "relative_path": "documentation/reference/schemas/security-finding-labels-summary.v1.schema.json",
  "sha256": "<digest of the loaded schema bytes>",
  "title": "DatarimSecurityFindingLabelsValidationSummary/v1",
  "dialect": "https://json-schema.org/draft/2020-12/schema",
  "summary_schema": "DatarimSecurityFindingLabelsValidationSummary/v1"
}
```

`SCHEMA_DIRECTORY_UNAVAILABLE` means the fixed directory is absent, inaccessible, or a symlink and the catalog count is unavailable. `SCHEMA_INPUT_REFUSED` means a matched entry is not a readable regular file or its bytes are not supported UTF-8 JSON. `SCHEMA_CATALOG_LIMIT` means more than 256 matching entries or an entry larger than 1 MiB. A refusal emits no partial entries, uses a `null` count with `NOT_MEASURED`, and exits `2`. A present empty directory is instead a complete measured catalog with count `0` and exit `0`.

JSON object and Boolean schema documents can be cataloged. The output is discovery metadata: it does not establish Draft conformance, validate any summary, prove producer readiness, or establish semantic truth. JSON string escaping preserves metadata as data but is not a semantic or security certificate; these public fields are intentionally disclosed. Parser/help failures and uncaught process failures remain outside the JSON result contract.

## Follow-up and rollback

If a catalog discrepancy is found, inspect the referenced checkout bytes and use the repository's ordinary reviewed pull-request route to correct the relevant source. To roll back this feature, use the ordinary follow-up pull-request route to revert the catalog script, its focused tests, and this reference together; previously accepted schema files are independent and remain unchanged.

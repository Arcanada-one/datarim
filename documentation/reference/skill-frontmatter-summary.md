# Skill frontmatter summary schema

The [`DatarimSkillFrontmatterValidationSummary/v1` JSON Schema](schemas/skill-frontmatter-summary.v1.schema.json) describes the fixed JSON object emitted by `dev-tools/check-skill-frontmatter.sh --summary-json` for an ordinary completed scan. It lets another tool validate the output shape with a standard Draft 2020-12 JSON Schema engine. The checker remains the source of validation behavior.

## Contract

Every summary has exactly these eight fields. Additional fields are rejected.

| Field | Contract |
|---|---|
| `schema` | `DatarimSkillFrontmatterValidationSummary/v1` |
| `result` | `PASS` or `FAIL` |
| `exit_code` | Integer `0` or `1`, correlated with `result` |
| `diagnostic_codes` | Empty for `PASS`; exactly `SKILL_FRONTMATTER_INVALID` for `FAIL` |
| `checked_count` | Non-negative integer measured by the completed scan |
| `checked_count_status` | `MEASURED`, including for an empty scan |
| `warning_count` | Non-negative integer measured by the completed scan |
| `warning_count_status` | `MEASURED`, including when there are no warnings |

`PASS` requires exit code `0` and no diagnostic codes. `FAIL` requires exit code `1` and the single fixed code `SKILL_FRONTMATTER_INVALID`. A legacy top-level `runtime:` warning does not change the result: it remains `PASS` with exit code `0`, while `warning_count` records the warning.

The schema checks field names, types, fixed values, and the result/exit/code profiles. It does not enforce arbitrary arithmetic between counts, such as `warning_count <= checked_count`. Draft 2020-12 treats a JSON number with an integer mathematical value (for example, `1.0`) as an integer; this schema does not make a lexical-format claim about number spelling.

## Example

```json
{
  "schema": "DatarimSkillFrontmatterValidationSummary/v1",
  "result": "PASS",
  "exit_code": 0,
  "diagnostic_codes": [],
  "checked_count": 1,
  "checked_count_status": "MEASURED",
  "warning_count": 1,
  "warning_count_status": "MEASURED"
}
```

The JSON summary contains no skill names, paths, frontmatter values, or human-readable diagnostics. Its counts describe the checker's structural scan; they do not establish skill quality, safety, authority, admission, or runtime behavior.

The schema covers an ordinary completed scan. Argument parsing, help, root-directory changes, signals, missing tools, and other failures outside that path retain their existing behavior and are not normalized into this JSON contract.

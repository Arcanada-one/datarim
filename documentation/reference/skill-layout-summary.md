# Skill layout validation summary

The skill-layout checker accepts `--summary-json` to emit one fixed JSON object for a completed scan or a missing skills root. Without the option, its existing human-readable output is unchanged.

```bash
./dev-tools/check-skill-layout.sh --summary-json
./dev-tools/check-skill-layout.sh --root /path/to/project --summary-json
./dev-tools/check-skill-layout.sh --root /path/to/project --allow-flat-coexistence --summary-json
```

The summary is one JSON object on standard output. It contains exactly six fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimSkillLayoutValidationSummary/v1` | Versioned output shape. |
| `result` | `PASS`, `FAIL`, `INPUT_UNAVAILABLE` | Existing structural scan outcome or the missing-skills-root condition. |
| `exit_code` | `0`, `1`, `2` | Corresponding checker result. |
| `diagnostic_codes` | Fixed codes below | No paths, names, frontmatter, or dynamic diagnostics. |
| `checked_count` | Non-negative integer or `null` | Number of non-reserved skill directories visited, or unavailable before the scan. |
| `checked_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the directory scan completed. |

## Outcomes

A completed scan with no layout violations reports `PASS`, exit code `0`, an empty diagnostic-code list, the measured count, and `MEASURED`:

```json
{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":2,"checked_count_status":"MEASURED"}
```

A completed scan with one or more existing layout violations reports `FAIL`, exit code `1`, the fixed code `SKILL_LAYOUT_INVALID`, the measured count, and `MEASURED`:

```json
{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_LAYOUT_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}
```

If the selected root has no `skills/` directory, the checker reports `INPUT_UNAVAILABLE`, exit code `2`, the fixed code `SKILLS_ROOT_UNAVAILABLE`, a `null` count, and `NOT_MEASURED`:

```json
{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":2,"diagnostic_codes":["SKILLS_ROOT_UNAVAILABLE"],"checked_count":null,"checked_count_status":"NOT_MEASURED"}
```

## Count and validation scope

The count is the existing scan counter: child directories visited under `skills/`, excluding the reserved `.system/` namespace. A directory is counted before its name and contents are checked, so a directory that fails validation is included. An existing empty `skills/` directory produces a measured count of zero.

The summary reuses the checker's existing scan and predicates. `PASS` means only that this structural checker found no layout violation under its current rules. It does not establish skill quality, safety, authority, knowledge admission, runtime enforcement, or any broader acceptance.

In summary mode, handled scan outcomes do not print skill names, paths, frontmatter values, or human scan diagnostics. The output is built from fixed literals and the counter already computed by the scan; the checker does not scan twice or serialize arbitrary input.

## Existing limits

The JSON guarantee does not cover argument-parser responses such as `--help`, unknown arguments, or a missing option value. It also does not normalize signals, process-launch failures, shell/runtime errors, or other failures outside the checker's existing result branches. These retain their existing behavior and are not represented as a universal JSON response.

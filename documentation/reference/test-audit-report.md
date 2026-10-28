# Test Audit Report

For the separate opt-in machine summary of one card's structural validation, see [Test Value Card Validation Summary](test-value-card-summary.md).

The report builder summarizes only an explicit selection and its cited retained JSON receipts. It is read-only and structural: it does not execute tests, discover files, evaluate semantic overlap, choose an action, or authorize changing a test plan.

## Run it

From the repository root, provide a root-relative selection file:

```bash
python3 dev-tools/build-test-audit-report.py --root . --selection path/to/selection.json
```

The selection file must be inside the root. A successful run writes one `datarim.test-audit-report/v1` JSON object to stdout and nothing to a report file. A refusal writes one fixed `ERROR CODE` line to stderr, leaves stdout empty, and exits 2. The command accepts no output or publication option.

## Selection schema

The JSON object has exactly `schema_version` and `tests`. `schema_version` is the integer `1`; `tests` contains 1–20 unique entries. Each entry has exactly:

The file in `templates/test-audit-selection.json` is a fill-in template, not a runnable selection. Replace its example paths, card text and action with the maintainer's explicit choices before running the builder.

| Field | Meaning |
|---|---|
| `test_path` | Root-relative path to the explicitly selected regular test source. Globs, absolute paths, traversal and symlink components are refused. |
| `card` | The five existing Test Value Card strings: `protects`, `fails_when`, `why_new`, `seam`, `no_claim`; each is non-empty and at most 160 UTF-8 bytes. |
| `proposed_action` | One of `retain`, `merge`, `refactor`, `retire`. This is a proposal, not an automated decision. |
| `rationale`, `limits` | Bounded single-line declarative text, each at most 512 UTF-8 bytes. These fields are not executed. Obvious absolute paths, URI forms, control characters and common secret-shaped values are refused. |
| `overlap_with` | Zero or more root-relative paths, each naming a different test in this same explicit selection. The tool does not decide whether the tests overlap. |
| `evidence_refs` | Zero or more explicitly named retained JSON receipts. Each reference has exactly `path`, `sha256`, and `cost_pointers`; pointer keys may be `wall_time_ms` and/or `flaky_attempts`. |

An evidence reference is:

```json
{
  "path": "qa/retained-run.json",
  "sha256": "<64 lowercase hexadecimal characters>",
  "cost_pointers": {
    "wall_time_ms": "/tests/0/wall_time_ms",
    "flaky_attempts": "/tests/0/flaky_attempts"
  }
}
```

Omit a cost pointer when no retained observation is supplied. A cited pointer must resolve in the receipt to a nonnegative finite JSON number representable by the report's numeric output; booleans, strings, null, negative numbers, nonzero decimals that underflow to zero, missing pointers, malformed JSON and digest mismatches are refused. `flaky_attempts` is reported as the cited number without rounding. The tool does not determine whether the receipt is authentic or causally representative.

## Bounds and input handling

- Selection JSON: at most 64 KiB.
- Each selected test source: at most 256 KiB.
- Each explicitly cited receipt: at most 64 KiB; at most 20 distinct receipt files.
- Aggregate bytes read across selection, test sources and receipts: at most 2 MiB.
- Inputs must be readable root-contained regular files. Absolute/traversal paths, globs, symlinks, common credential directories/files, duplicate JSON keys, malformed schemas and unknown fields are refused. The builder opens only selection-listed test and receipt paths; it parses only those bounded JSON files and emits no receipt body, only explicitly pointed-to numeric cost values.
- The builder opens inputs read-only and emits their SHA-256 bindings. These defensive limits do not make reads race-proof against another process with the same account.

The output contains the selection path/hash; the selected test paths and source hashes; the five card strings; proposed action, rationale, limits and explicit overlap paths; cited receipt paths/hashes/pointers; and the two cost fields. A cost is `OBSERVED_IN_RECEIPT` only when its cited pointer resolves to a valid number. Otherwise it is `NOT_MEASURED`, `null`, with reason `NO_CITED_OBSERVATION`. No suite total, savings, risk score or performance estimate is computed. Receipt content other than the two pointed-to numeric values is not copied into the report.

## Fixed diagnostics

Every refusal uses a fixed code without echoing a path, exception text or user argument. Common codes include `CLI_USAGE`, `ROOT_INVALID`, `SELECTION_INVALID`, `SELECTION_COUNT_INVALID`, `SELECTION_DUPLICATE_TEST`, `TEST_PATH_INVALID`, `INPUT_SYMLINK`, `INPUT_NOT_REGULAR`, `INPUT_UNREADABLE`, `TEST_TOO_LARGE`, `EVIDENCE_INVALID`, `EVIDENCE_DIGEST_MISMATCH`, `EVIDENCE_POINTER_INVALID`, `EVIDENCE_VALUE_INVALID`, `EVIDENCE_COUNT_LIMIT`, `AGGREGATE_READ_LIMIT`, and `REPORT_FAILED`. All refusals have a nonzero exit; none produces a successful empty report.

## Review boundary

Use the report to support human review, not to make it. Running, removing or rewriting tests, changing gate thresholds, and publishing a report are separate authorized reviewed actions. A structural report does not establish runtime compliance or acceptance.

# Consume validator JSON summaries in CI

Use the existing JSON summary options when CI needs to read validator results without parsing human-readable output. The QA charter coverage validator and Test Value Card validator are read-only; summary mode keeps each validator's existing validation and process exit behavior.

The runtime tool root and the checked-out project are separate paths:

- `DATARIM_RUNTIME` points to the existing Datarim runtime tree that contains `dev-tools/`.
- `PROJECT_ROOT` is the checked-out repository being validated. QA charter and run evidence paths are relative to this root; the card path is passed separately.
- `SUMMARY_DIR` below is a new temporary output directory. The commands write summaries there, not into the project or its input files.

Set `DATARIM_RUNTIME` and `PROJECT_ROOT` using the paths already provided by your CI environment. Replace the example input paths with files from the checkout.

```bash
: "${DATARIM_RUNTIME:?Set DATARIM_RUNTIME to the existing Datarim runtime tree}"
: "${PROJECT_ROOT:?Set PROJECT_ROOT to the checked-out project root}"

if ! SUMMARY_DIR="$(mktemp -d)" || [ -z "$SUMMARY_DIR" ]; then
  printf 'ERROR: could not create summary output directory\n' >&2
  exit 1
fi
QA_CHARTER="datarim/qa/example/qa-charter.md"
QA_EVIDENCE="datarim/qa/example/run-20261018T120000Z/evidence.json"
TEST_VALUE_CARD="$PROJECT_ROOT/path/to/test-value-card.md"

cd "$PROJECT_ROOT"

if python3 "$DATARIM_RUNTIME/dev-tools/check-qa-charter-coverage.py" \
  --root "$PROJECT_ROOT" \
  --charter "$QA_CHARTER" \
  --evidence "$QA_EVIDENCE" \
  --summary-json > "$SUMMARY_DIR/qa-charter.json"; then
  qa_exit=0
else
  qa_exit=$?
fi

if python3 "$DATARIM_RUNTIME/dev-tools/check-test-value-card.py" \
  --card "$TEST_VALUE_CARD" \
  --summary-json > "$SUMMARY_DIR/test-value-card.json"; then
  card_exit=0
else
  card_exit=$?
fi
```

The runtime-qualified script paths locate the tools; `--root`, `--charter`, `--evidence`, and `--card` identify the project and its inputs. Both commands emit one compact JSON object when summary mode reaches validation. Keep `qa_exit` and `card_exit` separately: their numeric meanings differ.

## Read the summaries

Use a JSON parser rather than matching output text. This small consumer reads one object from each fresh output file and checks that the reported exit value agrees with the process exit captured above:

```bash
python3 - "$SUMMARY_DIR/qa-charter.json" "$SUMMARY_DIR/test-value-card.json" \
  "$qa_exit" "$card_exit" <<'PY'
import json
import sys
from pathlib import Path

def read_summary(path):
    text = Path(path).read_text(encoding="utf-8")
    if not text.strip():
        raise SystemExit(f"no summary object in {path}; check CLI usage and stderr")
    return json.loads(text)

qa = read_summary(sys.argv[1])
card = read_summary(sys.argv[2])
qa_exit, card_exit = map(int, sys.argv[3:5])

assert qa["schema"] == "DatarimQaCharterCoverageSummary/v1"
assert card["schema"] == "TestValueCardValidationSummary/v1"
assert qa["exit_code"] == qa_exit
assert card["exit_code"] == card_exit

print("QA charter:", qa["verdict"], qa_exit, qa["diagnostic_codes"])
print("Test Value Card:", card["status"], card_exit, card["diagnostic_codes"])
PY
```

This parser example reports the two results; it does not define a new CI gate or combine their exit policies. Apply the consuming job's existing policy to the separately recorded process statuses.

## Interpret availability and refusals

- QA charter coverage uses exit `0` for `PASS`, `1` for a validator refusal, and `2` for command-line usage errors. A usage error occurs before validation and does not emit the summary object.
- Each QA count has an `available` flag and a `value`. `available: true` with `value: 0` is a measured zero. `available: false` with `value: null` means the count was not measured; do not coerce it to zero. `checkpoint_linkage: NOT_MEASURED` is not a pass.
- Test Value Card uses exit `0` for a valid card, `1` for an invalid card, and `2` when the card is unreadable. In summary mode an unreadable card produces `status: unreadable`, `CARD_UNREADABLE`, and `validation_error_count: null` with `validation_error_count_status: NOT_MEASURED`. A measured `validation_error_count: 0` is different.
- Test Value Card command-line usage errors also return `2`, but happen before validation and emit no summary object. Check for one valid object and its `schema`/`status` instead of interpreting exit `2` alone as an unreadable card.
- Both summaries contain fixed diagnostic identifiers rather than paths, card contents, exception text, or other user-supplied details. Keep automation decisions tied to the documented schemas and process statuses.

These summaries describe only the existing validators' results. QA coverage does not prove that a test was executed or that a task was accepted. Test Value Card validation checks the card's structure; it does not establish test value, truth, demand, safety, runtime admission, or authority to change a test plan. See the [QA Charter Coverage Summary reference](../reference/qa-charter-coverage-summary.md) and [Test Value Card Validation Summary reference](../reference/test-value-card-summary.md) for their full fields and diagnostic codes.


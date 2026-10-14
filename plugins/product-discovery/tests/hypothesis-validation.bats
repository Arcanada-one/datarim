#!/usr/bin/env bats

FIXTURES="$BATS_TEST_DIRNAME/fixtures/hypothesis-validation"
ANALYZER="$BATS_TEST_DIRNAME/hypothesis_validation_reference.py"
CHECKER="$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.sh"

@test "complete synthetic fixture bytes and published raw counts agree" {
  python3 - "$ANALYZER" "$FIXTURES/observations-complete.json" "$FIXTURES/observations-complete.jsonl" "$FIXTURES/protocol-frozen-v1.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from hypothesis_validation_reference import analyze_bundle
d = json.loads(Path(sys.argv[2]).read_text())
assert d["hypothesis_at_protocol"]["status"] == "test_ready"
assert d["hypothesis_at_analysis"]["status"] == "under_test"
result = analyze_bundle(d, Path(sys.argv[3]).read_bytes(), Path(sys.argv[4]).read_bytes())
assert result == {
    "counts": {
        "A": {"successes": 1, "failures": 3, "missing": 0, "observed": 4, "expected": 4},
        "B": {"successes": 3, "failures": 1, "missing": 0, "observed": 4, "expected": 4},
    },
    "expected_total": 8, "received_total": 8, "missing_total": 0,
    "status": "supported", "limits": "fixed synthetic guide scenarios only",
}
PY
}

@test "missing synthetic observation is inconclusive even when observed B rows all succeed" {
  python3 - "$ANALYZER" "$FIXTURES/observations-missing.json" "$FIXTURES/observations-missing.jsonl" "$FIXTURES/protocol-frozen-v1.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from hypothesis_validation_reference import analyze_bundle
d = json.loads(Path(sys.argv[2]).read_text())
result = analyze_bundle(d, Path(sys.argv[3]).read_bytes(), Path(sys.argv[4]).read_bytes())
assert result == {
    "counts": {
        "A": {"successes": 1, "failures": 3, "missing": 0, "observed": 4, "expected": 4},
        "B": {"successes": 3, "failures": 0, "missing": 1, "observed": 3, "expected": 4},
    },
    "expected_total": 8, "received_total": 7, "missing_total": 1,
    "status": "inconclusive", "limits": "fixed synthetic guide scenarios only",
}
PY
}

@test "payload cannot lower the frozen sample size to turn missing rows into supported" {
  python3 - "$ANALYZER" "$FIXTURES/observations-missing.json" "$FIXTURES/observations-missing.jsonl" "$FIXTURES/protocol-frozen-v1.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from hypothesis_validation_reference import analyze_bundle
d = json.loads(Path(sys.argv[2]).read_text())
d["sample_rule"]["expected_per_variant"] = 3
d["observations"] = [row for row in d["observations"] if row["id"] != "HV-A-004"]
d["raw_observation_refs"] = [ref for ref in d["raw_observation_refs"] if ref["id"] != "raw:HV-A-004"]
raw = b"".join(line for line in Path(sys.argv[3]).read_bytes().splitlines(keepends=True)
               if json.loads(line)["id"] != "HV-A-004")
result = analyze_bundle(d, raw, Path(sys.argv[4]).read_bytes())
assert result == {"status": "rejected", "reason": "payload analysis rules do not match the frozen protocol"}
PY
}

@test "unreferenced synthetic analysis is rejected by the deterministic reference parser" {
  python3 - "$ANALYZER" "$FIXTURES/unreferenced-analysis.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from hypothesis_validation_reference import analyze_bundle
d = json.loads(Path(sys.argv[2]).read_text())
result = analyze_bundle(d, None, None)
assert result == {"status": "rejected", "reason": "no raw observation references"}
PY
}

@test "a protocol amendment is a new exact revision and the v1 analysis rejects v2 bytes" {
  python3 - "$ANALYZER" "$FIXTURES/observations-complete.json" "$FIXTURES/observations-complete.jsonl" "$FIXTURES/protocol-frozen-v1.json" "$FIXTURES/protocol-amended-v2.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
from hypothesis_validation_reference import analyze_bundle
d = json.loads(Path(sys.argv[2]).read_text())
raw = Path(sys.argv[3]).read_bytes()
before_bytes, after_bytes = Path(sys.argv[4]).read_bytes(), Path(sys.argv[5]).read_bytes()
before, after = json.loads(before_bytes), json.loads(after_bytes)
assert before["status"] == after["status"] == "protocol_frozen"
assert before["revision"] == 1 and after["revision"] == 2
assert after["supersedes"] == {
    "id": before["id"], "revision": before["revision"],
    "digest": "sha256:" + hashlib.sha256(before_bytes).hexdigest(),
}
assert before["sample_rule"] != after["sample_rule"]
assert before["side_effect_grant"] == after["side_effect_grant"] == "none"
assert before["grant_ref"] is after["grant_ref"] is None
assert analyze_bundle(d, raw, after_bytes) == {
    "status": "rejected", "reason": "frozen protocol digest or status does not match supplied bytes"
}
PY
}

@test "decision-record digest reference makes a silent frozen-protocol edit fail the real checker" {
  local tmp
  tmp=$(mktemp -d "$BATS_TEST_TMPDIR/hypothesis-freeze.XXXXXX")
  cp -R "$FIXTURES/product-artifact-freeze/." "$tmp/"
  run "$CHECKER" --root "$tmp" --bundle .
  [ "$status" -eq 0 ]
  python3 - "$tmp/protocol.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
old = "sample_rule: Exactly one simulator path per variant; descriptive only, no statistical inference."
new = "sample_rule: Silently changed after freeze to six paths per variant."
assert old in text
p.write_text(text.replace(old, new))
PY
  run "$CHECKER" --root "$tmp" --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_REF_MISSING"* ]]
}

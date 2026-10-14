#!/usr/bin/env bats

FIXTURES="$BATS_TEST_DIRNAME/fixtures/hypothesis-validation"

@test "complete synthetic fixture bytes and published raw counts agree" {
  python3 - "$FIXTURES/observations-complete.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
assert d["synthetic"] is True
protocol_path = Path(sys.argv[1]).with_name("protocol-frozen-v1.json")
protocol_bytes = protocol_path.read_bytes()
protocol_doc = json.loads(protocol_bytes)
assert {k:d["protocol"][k] for k in ("id", "revision", "status")} == {k:protocol_doc[k] for k in ("id", "revision", "status")}
assert d["protocol"]["digest"] == "sha256:" + hashlib.sha256(protocol_bytes).hexdigest()
assert d["protocol"]["status"] == "protocol_frozen"
assert d["hypothesis_at_protocol"]["status"] == "test_ready"
assert d["hypothesis_at_protocol"]["acceptance_state"] == "accepted"
assert d["hypothesis_at_analysis"]["status"] == "under_test"
assert d["hypothesis_at_analysis"]["acceptance_state"] == "accepted"
assert d["hypothesis_at_analysis"]["protocol_ref"] == {k:d["protocol"][k] for k in ("id", "revision", "digest")}
assert len(d["raw_observation_refs"]) == 8
rows = d["observations"]
raw_rows = [json.loads(line) for line in Path(sys.argv[1]).with_suffix(".jsonl").read_text().splitlines()]
assert raw_rows == rows
assert len(rows) == 8 and len({r["id"] for r in rows}) == 8
refs = {ref["id"]: ref for ref in d["raw_observation_refs"]}
assert set(refs) == {"raw:" + r["id"] for r in rows}
for row, raw_line in zip(rows, Path(sys.argv[1]).with_suffix(".jsonl").read_bytes().splitlines(keepends=True)):
    raw = raw_line
    assert refs["raw:" + row["id"]] == {"id": "raw:" + row["id"], "revision": 1, "digest": "sha256:" + hashlib.sha256(raw).hexdigest()}
counts = {v: {"successes": sum(r["outcome"] for r in rows if r["variant"] == v),
              "failures": sum(1-r["outcome"] for r in rows if r["variant"] == v),
              "missing": 0,
              "n": sum(r["variant"] == v for r in rows)} for v in ("A", "B")}
assert counts == {"A": {"successes": 1, "failures": 3, "missing": 0, "n": 4},
                  "B": {"successes": 3, "failures": 1, "missing": 0, "n": 4}}
assert counts == {key: d["expected_analysis"][key] for key in ("A", "B")}
assert {"a_rate": "1/4 = 25%", "b_rate": "3/4 = 75%", "difference_percentage_points": 50,
        "state": "supported", "limits": "fixed synthetic guide scenarios only"} == {
            key: d["expected_analysis"][key] for key in
            ("a_rate", "b_rate", "difference_percentage_points", "state", "limits")}
assert d["expected_hypothesis_state"] == "supported"
PY
}

@test "missing synthetic observation is inconclusive even when observed B rows all succeed" {
  python3 - "$FIXTURES/observations-missing.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
assert d["synthetic"] is True
protocol_path = Path(sys.argv[1]).with_name("protocol-frozen-v1.json")
protocol_bytes = protocol_path.read_bytes()
protocol_doc = json.loads(protocol_bytes)
assert {k:d["protocol"][k] for k in ("id", "revision", "status")} == {k:protocol_doc[k] for k in ("id", "revision", "status")}
assert d["protocol"]["digest"] == "sha256:" + hashlib.sha256(protocol_bytes).hexdigest()
assert d["protocol"]["status"] == "protocol_frozen"
assert d["hypothesis_at_protocol"]["status"] == "test_ready"
assert d["hypothesis_at_protocol"]["acceptance_state"] == "accepted"
assert d["hypothesis_at_analysis"]["status"] == "under_test"
assert d["hypothesis_at_analysis"]["protocol_ref"] == {k:d["protocol"][k] for k in ("id", "revision", "digest")}
raw_rows = [json.loads(line) for line in Path(sys.argv[1]).with_suffix(".jsonl").read_text().splitlines()]
assert raw_rows == d["observations"]
refs = {ref["id"]: ref for ref in d["raw_observation_refs"]}
assert set(refs) == {"raw:" + r["id"] for r in d["observations"]}
for row, raw_line in zip(d["observations"], Path(sys.argv[1]).with_suffix(".jsonl").read_bytes().splitlines(keepends=True)):
    raw = raw_line
    assert refs["raw:" + row["id"]] == {"id": "raw:" + row["id"], "revision": 1, "digest": "sha256:" + hashlib.sha256(raw).hexdigest()}
expected = d["sample_rule"]["expected_per_variant"] * 2
received = len(d["observations"])
missing = expected - received
counts = {v: {"successes": sum(r["outcome"] for r in d["observations"] if r["variant"] == v),
              "failures": sum(1-r["outcome"] for r in d["observations"] if r["variant"] == v),
              "missing": d["sample_rule"]["expected_per_variant"] - sum(r["variant"] == v for r in d["observations"]),
              "n": d["sample_rule"]["expected_per_variant"]} for v in ("A", "B")}
assert expected == d["expected_analysis"]["expected"] == 8
assert received == d["expected_analysis"]["received"] == 7
assert missing == d["expected_analysis"]["missing_total"] == 1
assert counts == {"A": {"successes": 1, "failures": 3, "missing": 0, "n": 4},
                  "B": {"successes": 3, "failures": 0, "missing": 1, "n": 4}}
assert counts == {key: d["expected_analysis"][key] for key in ("A", "B")}
assert d["expected_analysis"]["state"] == d["expected_hypothesis_state"] == "inconclusive"
PY
}

@test "unreferenced-analysis fixture is explicitly marked as an unsupported claim" {
  python3 - "$FIXTURES/unreferenced-analysis.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
assert d["raw_observation_refs"] == []
assert d["claimed_state"] == "supported"
assert d["expected_disposition"].startswith("rejected:")
PY
}

@test "protocol fixtures record a byte-pinned amendment as a superseding revision" {
  python3 - "$FIXTURES/protocol-frozen-v1.json" "$FIXTURES/protocol-amended-v2.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
digest = hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()
assert before["status"] == after["status"] == "protocol_frozen"
assert before["revision"] == 1 and after["revision"] == before["revision"] + 1
assert after["supersedes"] == {"id": before["id"], "revision": before["revision"], "digest": "sha256:" + digest}
assert before["sample_rule"] != after["sample_rule"]
assert before["side_effect_grant"] == after["side_effect_grant"] == "none"
assert before["grant_ref"] is after["grant_ref"] is None
PY
}

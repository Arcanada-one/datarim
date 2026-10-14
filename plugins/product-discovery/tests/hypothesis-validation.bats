#!/usr/bin/env bats

FIXTURES="$BATS_TEST_DIRNAME/fixtures/hypothesis-validation"

@test "complete synthetic observations replay to the published raw counts and supported state" {
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
rule = d["decision_rule"]
complete = (counts["B"]["successes"] >= rule["b_min_successes"]
    and counts["A"]["successes"] <= rule["a_max_successes"]
    and sum(r["critical_error"] for r in rows) <= rule["max_new_critical_errors"]
    and all(counts[v]["n"] == d["sample_rule"]["expected_per_variant"] for v in counts))
state = "supported" if complete else "inconclusive"
assert counts == {key: d["expected_analysis"][key] for key in ("A", "B")}
assert {"a_rate": "1/4 = 25%", "b_rate": "3/4 = 75%", "difference_percentage_points": 50, "state": state, "limits": "fixed synthetic guide scenarios only"} == {key: d["expected_analysis"][key] for key in ("a_rate", "b_rate", "difference_percentage_points", "state", "limits")}
assert state == d["expected_analysis"]["state"]
assert state == d["expected_hypothesis_state"] == "supported"
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
state = "inconclusive" if missing or len(d["raw_observation_refs"]) != expected else "supported"
assert expected == d["expected_analysis"]["expected"] == 8
assert received == d["expected_analysis"]["received"] == 7
assert missing == d["expected_analysis"]["missing_total"] == 1
assert counts == {"A": {"successes": 1, "failures": 3, "missing": 0, "n": 4}, "B": {"successes": 3, "failures": 0, "missing": 1, "n": 4}}
assert state == d["expected_analysis"]["state"] == "inconclusive"
assert state == d["expected_hypothesis_state"]
PY
}

@test "synthetic analysis without raw observation references is rejected" {
  python3 - "$FIXTURES/unreferenced-analysis.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
valid = bool(d.get("raw_observation_refs")) and d.get("claimed_state") in {"supported", "refuted", "inconclusive"}
assert not valid
assert d["expected_disposition"].startswith("rejected:")
PY
}

@test "editing a frozen synthetic protocol creates a superseding revision" {
  python3 - "$FIXTURES/protocol-frozen-v1.json" "$FIXTURES/protocol-amended-v2.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
before, after = (json.loads(Path(p).read_text()) for p in sys.argv[1:])
digest = hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()
silent = dict(before, sample_rule="six rows per variant")
silent_is_valid = (silent == before or (silent.get("revision") == before["revision"] + 1
    and silent.get("supersedes", {}).get("digest") == "sha256:" + digest))
assert before["status"] == after["status"] == "protocol_frozen"
assert not silent_is_valid
assert before["revision"] == 1 and after["revision"] == before["revision"] + 1
assert after["supersedes"] == {"id": before["id"], "revision": before["revision"], "digest": "sha256:" + digest}
assert before["sample_rule"] != after["sample_rule"]
assert before["side_effect_grant"] == after["side_effect_grant"] == "none"
assert before["grant_ref"] is after["grant_ref"] is None
PY
}

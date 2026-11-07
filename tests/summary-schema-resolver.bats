#!/usr/bin/env bats

@test "resolves saved catalog profiles with bounded direct process evidence" {
  run python3 - "$BATS_TEST_DIRNAME/.." "$BATS_TEST_NUMBER" <<'PY'
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1]).resolve()
case_number = sys.argv[2]
script = root / "dev-tools/resolve-summary-schema.py"
test_source = root / "tests/summary-schema-resolver.bats"
catalog_source = os.environ.get("D5_RESOLVER_CATALOG_SOURCE")
case_filter = {value for value in os.environ.get("D5_RESOLVER_CASE_FILTER", "").split(",") if value}
ran_cases = []
evidence_env = os.environ.get("D5_RESOLVER_EVIDENCE_DIR")
if evidence_env:
    evidence_root = Path(evidence_env).resolve()
    evidence_root.mkdir(parents=True, exist_ok=True, mode=0o700)
else:
    evidence_root = Path(os.environ["BATS_TEST_TMPDIR"]) / "evidence"
    evidence_root.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(evidence_root, 0o700)
run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + str(os.getpid())

base_entries = [
    {
        "relative_path": "documentation/reference/schemas/live-evidence-summary.v1.schema.json",
        "sha256": "289c11d3e5f59dd0f6be41ca665bc24ebd49b5a4f6a0a96beb660578d0220c15",
        "title": "Datarim live-evidence summary v1",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": None,
    },
    {
        "relative_path": "documentation/reference/schemas/product-artifact-summary.v1.schema.json",
        "sha256": "55f98bfdf476daca3fad5572b9dd183daa8a0b94444e866eabc406b757a53444",
        "title": "DatarimProductArtifactValidationSummary/v1",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": "DatarimProductArtifactValidationSummary/v1",
    },
    {
        "relative_path": "documentation/reference/schemas/qa-charter-summary.v1.schema.json",
        "sha256": "5e525653a08c39466b231d78f816f172c0bcabc3d1629e88a5992d594864d970",
        "title": "Datarim QA Charter Coverage Summary",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": "DatarimQaCharterCoverageSummary/v1",
    },
    {
        "relative_path": "documentation/reference/schemas/security-finding-labels-summary.v1.schema.json",
        "sha256": "0e10b75df21acc1af741fb5a98745d4992dd81ce9715de8a28fda93f6ed939ad",
        "title": "DatarimSecurityFindingLabelsValidationSummary/v1",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": "DatarimSecurityFindingLabelsValidationSummary/v1",
    },
    {
        "relative_path": "documentation/reference/schemas/skill-frontmatter-summary.v1.schema.json",
        "sha256": "eecf814e8356705309654e5928d20613fc05e89679ca113ef4111450b282d45a",
        "title": "Skill Frontmatter Validation Summary",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": "DatarimSkillFrontmatterValidationSummary/v1",
    },
    {
        "relative_path": "documentation/reference/schemas/test-value-card-summary.v1.schema.json",
        "sha256": "a370c270ebe5a4b73e3812befd8c420e3b76f5f913bf5bd6ffd5160c80a9ac55",
        "title": "Test Value Card Validation Summary",
        "dialect": "https://json-schema.org/draft/2020-12/schema",
        "summary_schema": "TestValueCardValidationSummary/v1",
    },
]
base_catalog = {
    "schema": "DatarimSummarySchemaCatalog/v1",
    "result": "COMPLETE",
    "exit_code": 0,
    "diagnostic_codes": [],
    "entry_count": len(base_entries),
    "entry_count_status": "MEASURED",
    "entries": base_entries,
}
python_bin = shutil.which("python3")
if not python_bin:
    raise SystemExit("python3 is unavailable")

def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        os.close(fd)
    os.chmod(path, 0o600)

def expect_profile(raw, result, exit_code, code=None, count=None, status=None, selected=None, title=None):
    value = json.loads(raw.decode("utf-8"))
    assert set(value) == {
        "schema", "result", "exit_code", "diagnostic_codes",
        "match_count", "match_count_status", "selection",
    }
    assert value["schema"] == "DatarimSummarySchemaResolution/v1"
    assert value["result"] == result
    assert type(value["exit_code"]) is int and value["exit_code"] == exit_code
    assert value["diagnostic_codes"] == ([] if code is None else [code])
    assert value["match_count"] == count
    assert value["match_count_status"] == status
    if selected is None:
        assert value["selection"] is None
    else:
        assert set(value["selection"]) == {
            "relative_path", "sha256", "title", "dialect", "summary_schema",
        }
        assert value["selection"]["relative_path"] == selected[0]
        assert value["selection"]["sha256"] == selected[1]
        if title is not None:
            assert value["selection"]["title"] == title

def run_case(name, query_bytes, expected_result, expected_exit, *, code=None, count=None,
             status=None, selected=None, mutation=None, raw_catalog=None, missing_catalog=False,
             hostile_title=None, symlink_catalog=False):
    if case_filter and name not in case_filter:
        return
    case_dir = evidence_root / ("run-" + run_id + "-case-" + case_number + "-" + name)
    case_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(case_dir, 0o700)
    catalog_path = case_dir / "catalog.json"
    query_path = case_dir / "query.json"
    stdout_path = case_dir / "stdout.raw"
    stderr_path = case_dir / "stderr.raw"
    receipt_path = case_dir / "process.json"

    if raw_catalog is not None:
        catalog_bytes = raw_catalog
    elif catalog_source:
        catalog_bytes = Path(catalog_source).read_bytes()
    else:
        catalog_bytes = json.dumps(base_catalog, ensure_ascii=True, separators=(",", ":")).encode()
    if mutation:
        value = json.loads(catalog_bytes.decode("utf-8"))
        entries = value.get("entries", [])
        if mutation == "duplicate-id":
            duplicate = dict(entries[4])
            duplicate["relative_path"] = "documentation/reference/schemas/second-skill.schema.json"
            entries.append(duplicate)
            value["entry_count"] += 1
        elif mutation == "count-mismatch":
            value["entry_count"] += 1
        elif mutation == "invalid-sha":
            entries[0]["sha256"] = "A" * 64
        elif mutation == "invalid-path":
            entries[0]["relative_path"] = "documentation/reference/schemas/../escape.schema.json"
        elif mutation == "duplicate-path":
            entries[1]["relative_path"] = entries[0]["relative_path"]
        elif mutation == "boolean-count":
            value["entry_count"] = True
        elif mutation == "refused-profile":
            value.update(
                result="INPUT_REFUSED",
                exit_code=2,
                diagnostic_codes=["SCHEMA_DIRECTORY_UNAVAILABLE"],
                entry_count=None,
                entry_count_status="NOT_MEASURED",
                entries=[],
            )
        elif mutation == "empty":
            value["entry_count"] = 0
            value["entries"] = []
        elif mutation == "non-finite":
            encoded = json.dumps(value, ensure_ascii=True, separators=(",", ":"))
            encoded = encoded.replace('"title":"Datarim live-evidence summary v1"', '"title":1e999', 1)
            catalog_bytes = encoded.encode("utf-8")
        elif mutation == "hostile-title":
            entries[4]["title"] = hostile_title
        elif mutation == "title-only":
            entries[0]["title"] = "DatarimTitleOnlySummary/v1"
        else:
            raise AssertionError("unknown fixture mutation")
        if mutation != "non-finite":
            catalog_bytes = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
    if not missing_catalog and symlink_catalog:
        target_path = case_dir / "catalog-target.json"
        write_private(target_path, catalog_bytes)
        os.symlink(target_path, catalog_path)
    elif not missing_catalog:
        write_private(catalog_path, catalog_bytes)
    write_private(query_path, query_bytes)
    selected_catalog = case_dir / "missing-catalog.json" if missing_catalog else catalog_path
    source_hash = digest(Path(catalog_source)) if catalog_source else None

    stdout_fd = os.open(stdout_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    stderr_fd = os.open(stderr_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(stdout_fd)
    os.close(stderr_fd)
    tracked = [script, test_source, query_path]
    if catalog_source:
        tracked.append(Path(catalog_source))
    if not missing_catalog:
        tracked.append(catalog_path)
        if symlink_catalog:
            tracked.append(target_path)
    before = {str(path): digest(path) for path in tracked}
    start = utc_now()
    argv = [python_bin, str(script), "--catalog", str(selected_catalog)]
    with open(query_path, "rb") as query_stream, open(stdout_path, "wb") as stdout_stream, open(stderr_path, "wb") as stderr_stream:
        process = subprocess.Popen(
            argv,
            cwd=str(root),
            stdin=query_stream,
            stdout=stdout_stream,
            stderr=stderr_stream,
            close_fds=True,
        )
        pid = process.pid
        exit_code = process.wait()
    end = utc_now()
    after = {str(path): digest(path) for path in tracked}
    receipt = {
        "pid": pid,
        "started_utc": start,
        "ended_utc": end,
        "argv": argv,
        "cwd": str(root),
        "exit_code": exit_code,
        "source_catalog_path": catalog_source,
        "source_catalog_sha256": source_hash,
        "sha256_before": before,
        "sha256_after": after,
        "stdout_raw": str(stdout_path),
        "stderr_raw": str(stderr_path),
    }
    write_private(receipt_path, (json.dumps(receipt, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode())
    ran_cases.append(name)
    assert before == after
    assert stat.S_IMODE(stdout_path.stat().st_mode) == 0o600
    assert stat.S_IMODE(stderr_path.stat().st_mode) == 0o600
    assert stat.S_IMODE(receipt_path.stat().st_mode) == 0o600
    stdout = stdout_path.read_bytes()
    stderr = stderr_path.read_bytes()
    assert not stderr
    assert stdout.endswith(b"\n") and stdout.count(b"\n") == 1
    assert exit_code == expected_exit
    expect_profile(stdout, expected_result, expected_exit, code, count, status, selected, hostile_title)

skill_id = "DatarimSkillFrontmatterValidationSummary/v1"
security_id = "DatarimSecurityFindingLabelsValidationSummary/v1"
skill_path = "documentation/reference/schemas/skill-frontmatter-summary.v1.schema.json"
skill_sha = "eecf814e8356705309654e5928d20613fc05e89679ca113ef4111450b282d45a"
security_path = "documentation/reference/schemas/security-finding-labels-summary.v1.schema.json"
security_sha = "0e10b75df21acc1af741fb5a98745d4992dd81ce9715de8a28fda93f6ed939ad"
refused = ("INPUT_REFUSED", 2, "SUMMARY_SCHEMA_RESOLUTION_REFUSED", None, "NOT_MEASURED", None)

run_case("match-skill", json.dumps({"schema": skill_id, "ignored": {"name": "not inspected"}}).encode(), "MATCHED", 0, count=1, status="MEASURED", selected=(skill_path, skill_sha))
run_case("match-security", json.dumps({"schema": security_id}).encode(), "MATCHED", 0, count=1, status="MEASURED", selected=(security_path, security_sha))
run_case("not-found", b'{"schema":"DatarimUnknownSummary/v1"}', "NOT_FOUND", 1, code="SUMMARY_SCHEMA_NOT_FOUND", count=0, status="MEASURED")
run_case("title-only", b'{"schema":"DatarimTitleOnlySummary/v1"}', "NOT_FOUND", 1, code="SUMMARY_SCHEMA_NOT_FOUND", count=0, status="MEASURED", mutation="title-only")
run_case("ambiguous", json.dumps({"schema": skill_id}).encode(), "AMBIGUOUS", 1, code="SUMMARY_SCHEMA_AMBIGUOUS", count=2, status="MEASURED", mutation="duplicate-id")
run_case("missing-catalog", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], missing_catalog=True)
run_case("symlink-catalog", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], symlink_catalog=True)
run_case("refused-profile", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="refused-profile")
run_case("count-mismatch", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="count-mismatch")
run_case("invalid-sha", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="invalid-sha")
run_case("invalid-path", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="invalid-path")
run_case("duplicate-path", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="duplicate-path")
run_case("boolean-count", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="boolean-count")
run_case("boolean-query", b'{"schema":true}', *refused[:2], code=refused[2], count=refused[3], status=refused[4])
run_case("duplicate-query-key", b'{"schema":"' + skill_id.encode() + b'","schema":"DatarimUnknownSummary/v1"}', *refused[:2], code=refused[2], count=refused[3], status=refused[4])
run_case("duplicate-catalog-key", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], raw_catalog=b'{"schema":"DatarimSummarySchemaCatalog/v1","schema":"DatarimSummarySchemaCatalog/v1"}')
run_case("oversized-query", b" " * (64 * 1024 + 1), *refused[:2], code=refused[2], count=refused[3], status=refused[4])
run_case("oversized-catalog", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], raw_catalog=b" " * (2 * 1024 * 1024 + 1))
run_case("non-finite-query", b'{"schema":"' + skill_id.encode() + b'","value":NaN}', *refused[:2], code=refused[2], count=refused[3], status=refused[4])
run_case("non-finite-catalog", json.dumps({"schema": skill_id}).encode(), *refused[:2], code=refused[2], count=refused[3], status=refused[4], mutation="non-finite")
run_case("empty-catalog", json.dumps({"schema": skill_id}).encode(), "NOT_FOUND", 1, code="SUMMARY_SCHEMA_NOT_FOUND", count=0, status="MEASURED", mutation="empty")
sentinel = evidence_root / ("case-" + case_number + "-hostile-executed")
hostile = "$(touch " + str(sentinel) + ")"
run_case("hostile-literal", json.dumps({"schema": skill_id, "note": "$(touch ignored)"}).encode(), "MATCHED", 0, count=1, status="MEASURED", selected=(skill_path, skill_sha), mutation="hostile-title", hostile_title=hostile)
assert not sentinel.exists()
if case_filter:
    assert set(ran_cases) == case_filter, (sorted(ran_cases), sorted(case_filter))
PY
  [ "$status" -eq 0 ]
}

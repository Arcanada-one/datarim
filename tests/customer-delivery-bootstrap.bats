#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  BOOTSTRAP="$REPO_ROOT/scripts/customer-delivery-bootstrap.py"
  WIRE_SCHEMA="$REPO_ROOT/config/customer-delivery-bootstrap-wire-v1.schema.json"
  FIXTURE_DIR="$BATS_TEST_TMPDIR/bootstrap"
  mkdir -p "$FIXTURE_DIR"
}

require_bootstrap_source() {
  if [[ ! -f "$BOOTSTRAP" ]]; then
    skip "bootstrap executable intentionally absent at bootstrap RED"
  fi
}

@test "bootstrap executable exists only after the authorized RED commit" {
  if [[ ! -f "$BOOTSTRAP" ]]; then
    echo "BOOTSTRAP_RED: missing authorized executable scripts/customer-delivery-bootstrap.py"
    false
  fi
}

@test "wire schema is canonical, closed, and contains every pre-trust fragment" {
  require_bootstrap_source
  run python3 - "$WIRE_SCHEMA" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = path.read_bytes()
def _closed(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key: {key}")
        result[key] = value
    return result

schema = json.loads(raw, object_pairs_hook=_closed)
canonical = (json.dumps(schema, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()
assert raw == canonical, "wire schema is not canonical JSON plus LF"
assert set(schema) == {"$defs", "$id", "$schema"}
expected = {
    "activate_key_request", "activate_key_result", "append_receipt_request",
    "append_receipt_result", "authority_signature_envelope",
    "authorization_result", "authorize_and_sign_request",
    "bootstrap_authorization", "bootstrap_policy", "bootstrap_provider_registration",
    "bootstrap_review", "caller_signature_envelope", "caller_sign_request",
    "caller_sign_result", "canonicalize_request", "canonicalize_result",
    "common_control", "genesis_attest_request", "genesis_attest_result",
    "genesis_bundle_request", "genesis_bundle_result", "genesis_input_invocation",
    "genesis_input_request", "genesis_input_result", "genesis_plan_request",
    "genesis_plan_result", "genesis_prepare_request", "genesis_prepare_result",
    "genesis_trust_invocation", "genesis_trust_request", "genesis_trust_result",
    "lookup_provider_operation_request", "lookup_provider_operation_result",
    "provider_registration_manifest", "publish_blob_request", "publish_blob_result",
    "receipt_lookup_request", "receipt_lookup_result", "registry_cas_request",
    "registry_cas_result", "resolve_blob_request", "resolve_blob_result",
    "resolve_receipt_request", "resolve_receipt_result"
}
assert set(schema["$defs"]) == expected, (set(schema["$defs"]) ^ expected)

def walk(node, pointer="#"):
    if isinstance(node, dict):
        if node.get("type") == "object":
            assert node.get("additionalProperties") is False, f"open object at {pointer}"
            assert set(node.get("required", ())) == set(node.get("properties", {})), pointer
        for key, value in node.items():
            walk(value, f"{pointer}/{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk(value, f"{pointer}/{index}")

walk(schema)
print("WIRE_SCHEMA_OK")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "WIRE_SCHEMA_OK" ]
}

@test "bootstrap validates every wire fragment and rejects unknown fields" {
  require_bootstrap_source
  run python3 "$BOOTSTRAP" --wire-schema "$WIRE_SCHEMA" --self-test-schema
  [ "$status" -eq 0 ]
  [ "$output" = "BOOTSTRAP_WIRE_SCHEMA_OK fragments=44" ]

  printf '{"input_locator":"fixture.json","input_sha256":"%064d","operation":"canonicalize","profile":"datarim-canonical-json-v1","schema_version":1,"unknown":true}\n' 0 >"$FIXTURE_DIR/unknown.json"
  run python3 "$BOOTSTRAP" --wire-schema "$WIRE_SCHEMA" --schema-pointer '/$defs/canonicalize_request' --validate-only "$FIXTURE_DIR/unknown.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown field: unknown"* ]]
}

@test "canonicalization rejects duplicate keys and produces exact canonical bytes" {
  require_bootstrap_source
  printf '{"z":1,"a":"é","z":2}\n' >"$FIXTURE_DIR/duplicate.json"
  run python3 "$BOOTSTRAP" --wire-schema "$WIRE_SCHEMA" --canonicalize-only "$FIXTURE_DIR/duplicate.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate key: z"* ]]

  printf '{"z":1,"a":"é","line":"x\\ny"}\n' >"$FIXTURE_DIR/input.json"
  run python3 "$BOOTSTRAP" --wire-schema "$WIRE_SCHEMA" --canonicalize-only "$FIXTURE_DIR/input.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"a":"é","line":"x\ny","z":1}' ]
}

@test "bootstrap imports only the Python standard library and never invokes a shell" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" <<'PY'
import ast
import pathlib
import sys

tree = ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
imports = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        imports.update(alias.name.split(".")[0] for alias in node.names)
    elif isinstance(node, ast.ImportFrom) and node.module:
        imports.add(node.module.split(".")[0])
stdlib = set(sys.stdlib_module_names)
assert imports <= stdlib, sorted(imports - stdlib)
for node in ast.walk(tree):
    if isinstance(node, ast.keyword) and node.arg == "shell":
        assert isinstance(node.value, ast.Constant) and node.value.value is False
print("BOOTSTRAP_TCB_STATIC_OK")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "BOOTSTRAP_TCB_STATIC_OK" ]
}

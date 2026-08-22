#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  BOOTSTRAP="$REPO_ROOT/scripts/customer-delivery-bootstrap.py"
  WIRE_SCHEMA_SOURCE="$REPO_ROOT/config/customer-delivery-bootstrap-wire-v1.schema.json"
  FIXTURE_DIR="$BATS_TEST_TMPDIR/bootstrap"
  mkdir -p "$FIXTURE_DIR"
  cp "$WIRE_SCHEMA_SOURCE" "$FIXTURE_DIR/wire.schema.json"
  WIRE_SCHEMA="wire.schema.json"
}

require_bootstrap_source() {
  if [[ ! -f "$BOOTSTRAP" ]]; then
    skip "bootstrap executable intentionally absent at bootstrap RED"
  fi
}

fail_test() {
  echo "$*" >&2
  return 1
}

bootstrap() {
  (cd "$FIXTURE_DIR" && python3 "$BOOTSTRAP" --wire-schema "$WIRE_SCHEMA" "$@")
}

@test "bootstrap executable exists only after the authorized RED commit" {
  if [[ ! -f "$BOOTSTRAP" ]]; then
    echo "BOOTSTRAP_RED: missing authorized executable scripts/customer-delivery-bootstrap.py"
    false
  fi
}

@test "wire schema is canonical, closed, and contains every pre-trust fragment" {
  require_bootstrap_source
  run python3 - "$WIRE_SCHEMA_SOURCE" <<'PY'
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
    "activation", "activation_acceptance", "activation_finalize_result",
    "activation_journal", "activation_prepare_result", "activation_rebind_result",
    "activation_response", "activation_supersession",
    "authorization_result", "authorize_and_sign_request",
    "authorization_pointer_request",
    "bootstrap_authorization", "bootstrap_policy", "bootstrap_provider_registration",
    "bootstrap_review", "caller_signature_envelope", "caller_sign_request", "caller_spec",
    "caller_sign_result", "canonicalize_request", "canonicalize_result",
    "catalog_parameters", "common_control", "genesis_attest_request", "genesis_attest_result",
    "genesis_bundle_request", "genesis_bundle_result", "genesis_input_invocation",
    "genesis_input_request", "genesis_input_result", "genesis_plan_request",
    "genesis_plan_result", "genesis_prepare_request", "genesis_prepare_result",
    "genesis_invocation_authorization", "genesis_lookup", "genesis_transition_journal",
    "genesis_trust_invocation", "genesis_trust_request", "genesis_trust_result",
    "identity_state", "immutable_authorization_request",
    "lookup_provider_operation_request", "lookup_provider_operation_result",
    "policy_spec", "provider_registration_manifest", "provider_spec",
    "publish_blob_request", "publish_blob_result", "recovery_cas_authorization",
    "recovery_spec", "registry_cas_activation_prepare_ref", "registry_cas_inner_request",
    "registry_parameters",
    "receipt_lookup_request", "receipt_lookup_result", "registry_cas_request",
    "registry_cas_result", "resolve_blob_request", "resolve_blob_result",
    "resolve_receipt_request", "resolve_receipt_result", "signer_spec", "source_revision"
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
  run bootstrap --self-test-schema
  [[ "$status" -eq 0 ]] || fail_test "self-test failed: $output"
  [[ "$output" = "BOOTSTRAP_WIRE_SCHEMA_OK fragments=69" ]] || fail_test "unexpected self-test output: $output"

  printf '{"input_locator":"fixture.json","input_sha256":"%064d","operation":"canonicalize","profile":"datarim-canonical-json-v1","schema_version":1,"unknown":true}\n' 0 >"$FIXTURE_DIR/unknown.json"
  run bootstrap --schema-pointer '/$defs/canonicalize_request' --validate-only unknown.json
  [[ "$status" -eq 2 ]] || fail_test "unknown field was accepted: $output"
  [[ "$output" == *"unknown field: unknown"* ]] || fail_test "wrong unknown-field diagnostic: $output"
}

@test "canonicalization rejects duplicate keys and produces exact canonical bytes" {
  require_bootstrap_source
  printf '{"z":1,"a":"é","z":2}\n' >"$FIXTURE_DIR/duplicate.json"
  run bootstrap --canonicalize-only duplicate.json
  [[ "$status" -eq 2 ]] || fail_test "duplicate key was accepted: $output"
  [[ "$output" == *"duplicate key: z"* ]] || fail_test "wrong duplicate-key diagnostic: $output"

  printf '{"z":1,"a":"é","line":"x\\ny"}\n' >"$FIXTURE_DIR/input.json"
  run bootstrap --canonicalize-only input.json
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

@test "all seventeen registered operations have real dispatch" {
  require_bootstrap_source
  operations=(
    canonicalize caller-sign activate-key genesis-trust genesis-input
    genesis-plan genesis-prepare genesis-attest genesis-bundle
    authorize-and-sign publish-blob resolve-blob lookup-provider-operation
    append-receipt lookup-receipt resolve-receipt registry-cas
  )
  printf '{}\n' >"$FIXTURE_DIR/request.json"
  missing=()
  for operation in "${operations[@]}"; do
    run bootstrap \
      --operation "$operation" \
      --request request.json
    if [[ "$output" == *"unrecognized arguments"* ]] || [[ "$output" == *"invalid choice"* ]] || [[ "$output" == *"one of the arguments --self-test-schema"* ]]; then
      missing+=("$operation")
    fi
  done
  if ((${#missing[@]})); then
    fail_test "MISSING_OPERATION_DISPATCH: ${missing[*]}"
  fi
  run python3 - "$BOOTSTRAP" <<'PY'
import ast,pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
for forbidden in ("not yet authorized", "not implemented", "pending-integration"):
    if forbidden in source:
        raise SystemExit("DEFERRED_OPERATION_HANDLER: "+forbidden)
tree=ast.parse(source)
handlers={node.name for node in ast.walk(tree) if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef)) and node.name.startswith("handle_")}
expected={"handle_"+name.replace("-","_") for name in (
 "canonicalize caller-sign activate-key genesis-trust genesis-input genesis-plan genesis-prepare genesis-attest genesis-bundle authorize-and-sign publish-blob resolve-blob lookup-provider-operation append-receipt lookup-receipt resolve-receipt registry-cas"
).split()}
missing=sorted(expected-handlers)
if missing: raise SystemExit("MISSING_OPERATION_HANDLERS: "+" ".join(missing))
print("OPERATION_HANDLERS_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "$output"
  [[ "$output" = "OPERATION_HANDLERS_OK" ]] || fail_test "unexpected handler inventory: $output"
}

@test "permissive and obsolete wire shapes are rejected" {
  require_bootstrap_source
  zero="$(printf '%064d' 0)"
  forty="$(printf '%040d' 0)"

  printf '{"bootstrap_authorization_locator":"a","bootstrap_authorization_sha256":"%s","bootstrap_review_locator":"b","bootstrap_review_sha256":"%s","caller_specs":[null],"catalog_parameters":null,"operation":"genesis-trust","policy_specs":[null],"provider_specs":[null],"recorded_at":"2026-08-22T00:00:00Z","recovery_specs":[null],"registry_parameters":null,"result_output":"r","result_signature_output":"s","reviewed_pair_commit":"%s","schema_version":1,"signer_specs":[null]}\n' "$zero" "$zero" "$forty" >"$FIXTURE_DIR/open-trust.json"
  run bootstrap --schema-pointer '/$defs/genesis_trust_request' --validate-only open-trust.json
  [[ "$status" -eq 2 ]] || fail_test "OPEN_SCHEMA_ACCEPTED: genesis_trust_request"

  printf '{"action":"lookup","activation_nonce":"nonce","authority_bundle_locator":"a","authority_bundle_sha256":"%s","expected_active_key_id":"old","expected_slot_generation":0,"identity_id":"identity","identity_kind":"signer","mode":"normal","operation":"activate-key","original_prepare_request_sha256":null,"output_proof":"proof","output_result":"result","provider_id":"provider","replacement_key_id":"new","replacement_principal":"principal","replacement_public_key":"ssh-ed25519 AAAA","replacement_secret_store_ref":"state/key","schema_version":1}\n' "$zero" >"$FIXTURE_DIR/obsolete-activation.json"
  run bootstrap --schema-pointer '/$defs/activate_key_request' --validate-only obsolete-activation.json
  [[ "$status" -eq 2 ]] || fail_test "OBSOLETE_ACTION_ACCEPTED: activate-key lookup"

  python3 - "$WIRE_SCHEMA_SOURCE" "$FIXTURE_DIR/open-acceptance.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
fragment=s["$defs"]["lookup_provider_operation_result"]
lookup={key: None for key in fragment["properties"]["lookup"]["properties"]}
lookup.update({
  "activation_acceptances":[None], "idempotency_key":"0"*64,
  "observed_provider_head":"0"*64, "provider_id":"provider",
  "schema_version":1, "status":"absent", "target_operation":"append-receipt"
})
sig={"algorithm":"ssh-ed25519","key_id":"key","namespace":"datarim-provider-lookup-result-v1","payload_sha256":"0"*64,"principal":"p","schema_version":1,"signer_id":"signer","sshsig_b64":"AAAA"}
open(sys.argv[2],"w").write(json.dumps({"lookup":lookup,"signature":sig},sort_keys=True,separators=(",",":"))+"\n")
PY
  run bootstrap --schema-pointer '/$defs/lookup_provider_operation_result' --validate-only open-acceptance.json
  [[ "$status" -eq 2 ]] || fail_test "OPEN_SCHEMA_ACCEPTED: activation_acceptances null"
}

@test "every actual CLI path is root-confined" {
  require_bootstrap_source
  run bootstrap --canonicalize-only /proc/sys/kernel/pid_max
  [[ "$status" -eq 2 ]] || fail_test "PATH_ESCAPE_ACCEPTED: absolute /proc/sys/kernel/pid_max"

  run python3 - "$BOOTSTRAP" "$FIXTURE_DIR" <<'PY'
import importlib.util,pathlib,sys
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2]); (root/"a").mkdir(); (root/"a"/"value").write_text("x")
bad=("a//value","a/./value","../value")
accepted=[]
for value in bad:
    try: m.confined_path(root,value)
    except m.BootstrapError: pass
    else: accepted.append(value)
if accepted: raise SystemExit("non-normal path accepted: "+",".join(accepted))
(root/"outside").mkdir(); (root/"link").symlink_to(root/"outside",target_is_directory=True)
try: m.confined_path(root,"link/value",must_exist=False)
except m.BootstrapError: pass
else: raise SystemExit("symlink parent accepted")
print("ROOT_CONFINEMENT_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "PATH_CONFINEMENT_GAPS: $output"
}

@test "durable writes are create-or-verify and never overwrite conflict bytes" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" "$FIXTURE_DIR" <<'PY'
import importlib.util,pathlib,sys
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2]); target=root/"result.json"; target.write_bytes(b"first\n")
try: m.atomic_write(target,b"different\n")
except m.BootstrapError: print("CREATE_OR_VERIFY_CONFLICT_OK")
else: raise SystemExit("existing conflicting bytes were overwritten")
assert target.read_bytes()==b"first\n"
PY
  [[ "$status" -eq 0 ]] || fail_test "DURABILITY_CONFLICT_GAP: $output"
  [[ "$output" = "CREATE_OR_VERIFY_CONFLICT_OK" ]] || fail_test "wrong durability output: $output"
}

@test "bounded subprocess evidence retains wait status and enforces output cap" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" "$FIXTURE_DIR" <<'PY'
import importlib.util,pathlib,sys
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2])
normal=m.run_bounded([sys.executable,"-c","raise SystemExit(7)"],1,cwd=root,env={"PATH":"/usr/bin:/bin"},output_cap_bytes=1024)
if normal.result_exit_code!=7 or normal.raw_wait_status!=(7<<8) or normal.timed_out:
    raise SystemExit(f"normal wait status invalid: {normal}")
try:
    m.run_bounded([sys.executable,"-c","print('x'*2048)"],1,cwd=root,env={"PATH":"/usr/bin:/bin"},output_cap_bytes=128)
except m.BootstrapError: pass
else: raise SystemExit("output cap overflow accepted")
print("BOUNDED_PROCESS_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "BOUNDED_PROCESS_GAPS: $output"
  [[ "$output" = "BOUNDED_PROCESS_OK" ]] || fail_test "wrong bounded-process output: $output"
}

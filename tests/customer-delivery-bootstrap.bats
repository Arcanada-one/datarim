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
    "activation", "activation_acceptance", "activation_authority_bundle", "activation_finalize_result",
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
    "key_possession_envelope", "lookup_provider_operation_request", "lookup_provider_operation_result",
    "policy_spec", "provider_registration_manifest", "provider_spec",
    "publish_blob_request", "publish_blob_result", "recovery_cas_authorization",
    "recovery_spec", "registry_cas_activation_prepare_ref", "registry_cas_inner_request",
    "registry_parameters",
    "registry_cas_request",
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
  [[ "$status" -eq 0 ]] || fail_test "wire-schema inventory failed: $output"
  [[ "$output" = "WIRE_SCHEMA_OK" ]] || fail_test "wrong wire-schema inventory output: $output"
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
  [[ "$status" -eq 0 ]] || fail_test "canonicalization failed: $output"
  [[ "$output" = '{"a":"é","line":"x\ny","z":1}' ]] || fail_test "wrong canonical bytes: $output"
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
  [[ "$status" -eq 0 ]] || fail_test "TCB static check failed: $output"
  [[ "$output" = "BOOTSTRAP_TCB_STATIC_OK" ]] || fail_test "wrong TCB static output: $output"
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

@test "one-minute timeout kills the full process group and preserves exit 143 evidence" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" "$FIXTURE_DIR" <<'PY'
import importlib.util,pathlib,sys
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2]); env={"PATH":"/usr/bin:/bin"}
grandchild="import time; time.sleep(600)"
child="import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',%r]); time.sleep(600)"%grandchild
normal="import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',%r]); time.sleep(600)"%child
e=m.run_bounded([sys.executable,"-c",normal],1,cwd=root,env=env,output_cap_bytes=4096)
if (e.result_exit_code,e.raw_wait_status,e.timed_out,e.termination_signal,e.forced_kill,e.descendants_survived)!=(143,15,True,15,False,False):
    raise SystemExit(f"SIGTERM evidence mismatch: {e}")
resistant_child="import signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); subprocess.Popen([sys.executable,'-c',%r]); time.sleep(600)"%("import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(600)")
resistant="import signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); subprocess.Popen([sys.executable,'-c',%r]); time.sleep(600)"%resistant_child
e=m.run_bounded([sys.executable,"-c",resistant],1,cwd=root,env=env,output_cap_bytes=4096)
if (e.result_exit_code,e.raw_wait_status,e.timed_out,e.termination_signal,e.forced_kill,e.descendants_survived)!=(143,9,True,15,True,False):
    raise SystemExit(f"SIGKILL evidence mismatch: {e}")
try: m.run_bounded([sys.executable,"-c","raise SystemExit(143)"],1,cwd=root,env=env,output_cap_bytes=4096)
except m.BootstrapError: pass
else: raise SystemExit("ordinary exit 143 was accepted")
print("TIMEOUT_PROCESS_GROUP_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "TIMEOUT_PROCESS_GROUP_GAP: $output"
  [[ "$output" = "TIMEOUT_PROCESS_GROUP_OK" ]] || fail_test "wrong timeout output: $output"
}

@test "git protected provider uses real fast-forward commits and remote readback authority" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" "$FIXTURE_DIR" <<'PY'
import hashlib,importlib.util,pathlib,shutil,subprocess,sys,tempfile
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
root=pathlib.Path(sys.argv[2]); state=root/"provider-private"; state.mkdir()
git=pathlib.Path(shutil.which("git") or "").resolve()
remote=root/"provider.git"; subprocess.run([str(git),"init","--bare","-q",str(remote)],check=True)
registration={"environment_allowlist":[],"git_executable":str(git),"git_sha256":hashlib.sha256(git.read_bytes()).hexdigest()}
context=m.RuntimeContext(root=root,schema={},registration=registration,private_root=state)
provider={"provider_id":"provider:receipts","protected_ref":"refs/heads/datarim/customer-delivery-receipts-v1","remote_url":str(remote)}
m.sign_provider_result=lambda _c,_r,_p,payload,namespace: {"namespace":namespace,"payload_sha256":m.digest_bytes(m.canonical_bytes(payload)),"schema_version":1}
def build(sequence,previous,head,request_sha):
    return {"operation":"append-receipt","provider_sequence":sequence,"previous_provider_head":previous,"result_provider_head":head,"request_sha256":request_sha,"schema_version":1}
request={"operation":"append-receipt","value":"one"}; auth_a=b"authority-a"
wire=m.provider_compare_append(context,{},provider,"append-receipt","a"*64,request,auth_a,[],build,"result-v1")
remote_oid=subprocess.run([str(git),"--git-dir",str(remote),"rev-parse",provider["protected_ref"]],check=True,capture_output=True,text=True).stdout.strip()
if wire["provider_commit_oid"]!=remote_oid: raise SystemExit("provider returned a fabricated or unrefetched commit OID")
result_path=state/"provider-state"/provider["provider_id"]/"results"/"append-receipt"/("a"*64+".json")
if result_path.exists(): result_path.unlink()
found=m.provider_lookup_bytes(context,provider,"append-receipt","a"*64)
if found is None or found[2]!=remote_oid or found[0]!=m.canonical_bytes(wire["result"]): raise SystemExit("response-loss lookup did not resolve exact remote bytes")
retry=m.provider_compare_append(context,{},provider,"append-receipt","a"*64,request,auth_a,[],build,"result-v1")
if retry!=wire: raise SystemExit("identical retry did not return byte-identical protected result")
try: m.provider_compare_append(context,{},provider,"append-receipt","a"*64,request,b"authority-b",[],build,"result-v1")
except m.BootstrapError: pass
else: raise SystemExit("changed authorization under one idempotency key was accepted")
try: m.provider_compare_append(context,{},provider,"append-receipt","a"*64,request,auth_a,[{"kind":"receipt","locator":"foreign.json","sha256":"d"*64}],build,"result-v1")
except m.BootstrapError: pass
else: raise SystemExit("changed object references under one idempotency key were accepted")
wire2=m.provider_compare_append(context,{},provider,"append-receipt","b"*64,{"operation":"append-receipt","value":"two"},auth_a,[],build,"result-v1")
parent=subprocess.run([str(git),"--git-dir",str(remote),"rev-parse",wire2["provider_commit_oid"]+"^"],check=True,capture_output=True,text=True).stdout.strip()
if parent!=remote_oid: raise SystemExit("second protected provider mutation was not a direct fast-forward")
snapshot=m.fetch_provider_snapshot(context,provider)
if snapshot.remote_commit_oid!=wire2["provider_commit_oid"] or snapshot.provider_sequence!=1: raise SystemExit("remote snapshot head/sequence mismatch")

foreign=root/"foreign.git"; subprocess.run([str(git),"init","--bare","-q",str(foreign)],check=True)
with tempfile.TemporaryDirectory(dir=root) as td:
    work=pathlib.Path(td); subprocess.run([str(git),"-C",str(work),"init","-q"],check=True)
    subprocess.run([str(git),"-C",str(work),"config","user.name","fixture"],check=True); subprocess.run([str(git),"-C",str(work),"config","user.email","fixture@example.invalid"],check=True)
    conflict=work/"providers"/"provider:foreign"/"requests"/"append-receipt"/("c"*64+".json"); conflict.parent.mkdir(parents=True); conflict.write_text("foreign\n")
    subprocess.run([str(git),"-C",str(work),"add","."],check=True); subprocess.run([str(git),"-C",str(work),"commit","-q","-m","foreign"],check=True)
    subprocess.run([str(git),"-C",str(work),"push","-q",str(foreign),"HEAD:"+provider["protected_ref"]],check=True)
foreign_provider={**provider,"provider_id":"provider:foreign","remote_url":str(foreign)}
try: m.fetch_provider_snapshot(context,foreign_provider)
except m.BootstrapError: pass
else: raise SystemExit("foreign incomplete protected provider tree was accepted")
print("GIT_PROVIDER_AUTHORITY_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "GIT_PROVIDER_AUTHORITY_GAP: $output"
  [[ "$output" = "GIT_PROVIDER_AUTHORITY_OK" ]] || fail_test "wrong Git-provider output: $output"
}

@test "activate-key replays slot crash, recovery rebind, and accepted-CAS finalize" {
  require_bootstrap_source
  run python3 - "$BOOTSTRAP" "$WIRE_SCHEMA_SOURCE" "$FIXTURE_DIR" <<'PY'
import hashlib,importlib.util,json,pathlib,shutil,subprocess,sys,types
spec=importlib.util.spec_from_file_location("bootstrap",sys.argv[1]); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
schema=json.loads(pathlib.Path(sys.argv[2]).read_text()); root=pathlib.Path(sys.argv[3]); private=root/"activation-private"; private.mkdir()
ssh=pathlib.Path(shutil.which("ssh-keygen") or "").resolve()
old=private/"keys"/"old"; new=private/"keys"/"new"; recovery=private/"keys"/"recovery"; old.parent.mkdir()
for handle in (old,new,recovery): subprocess.run([str(ssh),"-q","-t","ed25519","-N","","-f",str(handle)],check=True)
fingerprint=subprocess.run([str(ssh),"-lf",str(new)+".pub"],check=True,capture_output=True,text=True).stdout.split()[1]
registration={"environment_allowlist":[],"ssh_keygen_executable":str(ssh),"ssh_keygen_sha256":hashlib.sha256(ssh.read_bytes()).hexdigest()}
context=m.RuntimeContext(root=root,schema=schema,registration=registration,private_root=private)
m.initialize_identity(context,"signer","signer-one","provider-one","key-old","secret-store:"+str(old))
activation={"activation_nonce":"nonce-one","identity_id":"signer-one","identity_kind":"signer","old_key_id":"key-old","provider_id":"provider-one","replacement_fingerprint":fingerprint,"replacement_key_id":"key-new","replacement_principal":"signer-one","replacement_public_key":pathlib.Path(str(new)+".pub").read_text().strip(),"replacement_secret_store_ref":"secret-store:"+str(new)}
continuity_record={**activation,"issued_at":"2026-08-22T00:00:00Z","previous_registry_sha256":"1"*64,"replacement_registry_sha256":"2"*64,"schema_version":1}; continuity_raw=m.canonical_bytes(continuity_record)
continuity={"record":continuity_record,"old_signature":m.sign_envelope(context,continuity_raw,"secret-store:"+str(old),"datarim-key-continuity-v1",identity_kind="signer",identity_id="signer-one",key_id="key-old",principal="signer-one"),"new_signature":m.sign_envelope(context,continuity_raw,"secret-store:"+str(new),"datarim-key-continuity-v1",identity_kind="signer",identity_id="signer-one",key_id="key-new",principal="signer-one")}
(root/"continuity.json").write_bytes(m.canonical_bytes(continuity))
recovery_record={"adopted_pending_activation_nonces":["nonce-one"],"compromised_governance_key_id":None,"compromised_key_ids":["key-old"],"issued_at":"2026-08-22T00:00:01Z","key_activations":[activation],"previous_registry_sha256":"1"*64,"reason":"fixture recovery","recovery_id":"recovery-one","replacement_governance_key":None,"replacement_key_ids":["key-new"],"replacement_registry_preimage_sha256":"3"*64,"schema_version":1}; recovery_raw=m.canonical_bytes(recovery_record)
recovery_signature=m.sign_envelope(context,recovery_raw,"secret-store:"+str(recovery),"datarim-recovery-v1",signer_id="recovery-signer",key_id="recovery-key",principal="recovery-signer")
(root/"recovery.json").write_bytes(m.canonical_bytes({"record":recovery_record,"signatures":[recovery_signature]}))
catalog={"recovery_policy":{"quorum":1,"record_namespace":"datarim-recovery-v1","recovery_signers":[{"key_id":"recovery-key","principal":"recovery-signer","public_key":pathlib.Path(str(recovery)+".pub").read_text().strip(),"signer_id":"recovery-signer"}]}}
(root/"catalog.json").write_bytes(m.canonical_bytes(catalog)); args=types.SimpleNamespace(trust_catalog="catalog.json")
def request(action,mode,result_out,proof_out,authority_locator,cas=None):
    authority_raw=(root/authority_locator).read_bytes()
    value={"action":action,"activation":activation,"authority_bundle_locator":authority_locator,"authority_bundle_sha256":m.digest_bytes(authority_raw),"authorization_mode":mode,"cas_result_locator":None,"cas_result_sha256":None,"cas_result_signature_locator":None,"cas_result_signature_sha256":None,"idempotency_key":"0"*64,"operation":"activate-key","prepare_proof_output":proof_out,"prepare_result_output":result_out,"previous_registry_locator":"previous.json","previous_registry_sha256":"1"*64,"replacement_registry_locator":"replacement.json","replacement_registry_sha256":"2"*64,"schema_version":1,"supersession":None}
    if cas: value.update(cas)
    subject=dict(value); subject.pop("idempotency_key"); value["idempotency_key"]=m.digest_bytes(m.canonical_bytes(subject)); return value
prepare=request("prepare","continuity","prepare-result.json","prepare-proof.json","continuity.json")
first=m.handle_activate_key(context,prepare,args)
state=m.load_identity_state(context,"signer","signer-one")
if state["active_key_id"]!="key-old" or state["pending_key_id"]!="key-new": raise SystemExit("prepare activated early or failed to install pending slot")
journal_path=m.activation_journal_path(context,"nonce-one"); journal=m.load_json_bytes(journal_path.read_bytes())
crashed=dict(journal); crashed.update({"pending_slot_generation":None,"prepare_result_locator":None,"prepare_result_sha256":None,"prepare_proof_locator":None,"prepare_proof_sha256":None,"state":"prepared"})
m.atomic_compare_replace(journal_path,journal_path.read_bytes(),m.canonical_file_bytes(crashed),root=private)
if m.handle_activate_key(context,prepare,args)!=first: raise SystemExit("prepare response-loss replay changed result bytes")
rebind=request("rebind","recovery","rebind-result.json","rebind-proof.json","recovery.json")
rebound=m.handle_activate_key(context,rebind,args)
if m.handle_activate_key(context,rebind,args)!=rebound: raise SystemExit("rebind retry changed result bytes")
cas_result={"operation":"registry-cas","previous_registry_sha256":"1"*64,"result_registry_sha256":"2"*64}
(root/"cas.json").write_bytes(m.canonical_bytes(cas_result)); (root/"cas.sig").write_bytes(b"signed")
cas={"cas_result_locator":"cas.json","cas_result_sha256":m.digest_bytes(m.canonical_bytes(cas_result)),"cas_result_signature_locator":"cas.sig","cas_result_signature_sha256":m.digest_bytes(b"signed")}
finalize=request("finalize","recovery","unused-result.json","unused-proof.json","recovery.json",cas)
finished=m.handle_activate_key(context,finalize,args)
if m.handle_activate_key(context,finalize,args)!=finished: raise SystemExit("finalize retry changed result bytes")
state=m.load_identity_state(context,"signer","signer-one")
if state["active_key_id"]!="key-new" or any(state[k] is not None for k in ("pending_key_id","pending_handle_ref","pending_activation_nonce","pending_slot_generation")): raise SystemExit("accepted CAS did not atomically finalize the stable slot")
journal=m.load_json_bytes(journal_path.read_bytes()); m.validate_schema(journal,schema["$defs"]["activation_journal"],schema)
if journal["state"]!="complete": raise SystemExit("activation journal did not reach complete")
print("ACTIVATION_REPLAY_OK")
PY
  [[ "$status" -eq 0 ]] || fail_test "ACTIVATION_REPLAY_GAP: $output"
  [[ "$output" = "ACTIVATION_REPLAY_OK" ]] || fail_test "wrong activation output: $output"
}

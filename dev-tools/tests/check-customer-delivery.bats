#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE:-${REPO_ROOT}/dev-tools/check-customer-delivery.sh}"
    VALIDATOR_PYTHON="${CUSTOMER_DELIVERY_PYTHON:-/usr/bin/python3}"
    PYTHON="${CUSTOMER_DELIVERY_TEST_PYTHON:-$VALIDATOR_PYTHON}"
    CRYPTO_HELPER="${REPO_ROOT}/tests/customer-delivery-ed25519.py"
    TASK_ID="WEB-0001"
    ROOT="${BATS_TEST_TMPDIR}/consumer"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    SITE_CLEANUP_PATH=''
    SITE_CLEANUP_BACKUP=''
    SITE_IDENTITY_CLEANUP_SITE=''
    SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    mkdir -p "${ROOT}/datarim/tasks" "${ROOT}/datarim/receipts"

    if ! command -v yq >/dev/null 2>&1; then
        echo "ERROR: yq is required for customer-delivery tests" >&2
        return 1
    fi
    if [[ "$PYTHON" != /* || ! -x "$PYTHON" || -d "$PYTHON" \
        || "$VALIDATOR_PYTHON" != /* || ! -x "$VALIDATOR_PYTHON" || -d "$VALIDATOR_PYTHON" ]]; then
        echo "ERROR: test and validator Python paths must be absolute executables" >&2
        return 1
    fi
    if [[ ! -f "$CRYPTO_HELPER" ]] || ! "$PYTHON" -c 'import cryptography, jsonschema, yaml' >/dev/null 2>&1; then
        echo "ERROR: required Python test dependencies unavailable: cryptography, jsonschema, and PyYAML" >&2
        return 1
    fi

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"

    yq -i ".requirements.req-0001.acceptance.implementation.code_revision = \"${SHA}\" |
        .requirements.req-0001.acceptance.implementation.content_revision = \"${SHA}\" |
        .requirements.req-0001.acceptance.disposition = \"accepted\"" "$REQUIREMENTS"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.name test
    git -C "$ROOT" config user.email test@example.invalid
    git -C "$ROOT" add datarim
    git -C "$ROOT" commit -q -m baseline
    assert_darwin_dependency_site_integrity
}

clear_site_cleanup() {
    SITE_CLEANUP_PATH=''
    SITE_CLEANUP_BACKUP=''
}

cleanup_site_fixture() {
    [[ -n "${SITE_CLEANUP_PATH:-}" ]] || return 0
    if [[ -L "$SITE_CLEANUP_PATH" ]]; then
        /bin/unlink -- "$SITE_CLEANUP_PATH" || return 1
    elif [[ -d "$SITE_CLEANUP_PATH" ]]; then
        /bin/rmdir -- "$SITE_CLEANUP_PATH" || return 1
    elif [[ -e "$SITE_CLEANUP_PATH" ]]; then
        /bin/rm -f -- "$SITE_CLEANUP_PATH" || return 1
    fi
    if [[ -n "${SITE_CLEANUP_BACKUP:-}" && -e "$SITE_CLEANUP_BACKUP" ]]; then
        /bin/mv -- "$SITE_CLEANUP_BACKUP" "$SITE_CLEANUP_PATH" || return 1
    fi
    clear_site_cleanup
}

cleanup_metadata_identity_fixture() {
    local original metadata replacement
    [[ -n "${SITE_IDENTITY_CLEANUP_SITE:-}" ]] || return 0
    for original in "$SITE_IDENTITY_CLEANUP_SITE"/*.dist-info/METADATA.original-a2; do
        [[ -e "$original" ]] || continue
        metadata="${original%/METADATA.original-a2}/METADATA"
        replacement="${BATS_TEST_TMPDIR}/$(basename "${original%/METADATA.original-a2}")-METADATA-replacement"
        [[ ! -e "$metadata" ]] || /bin/mv -- "$metadata" "$replacement" || return 1
        /bin/mv -- "$original" "$metadata" || return 1
    done
    SITE_IDENTITY_CLEANUP_SITE=''
}

assert_darwin_dependency_site_integrity() {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
    /usr/bin/env -i LC_ALL=C \
        "${CUSTOMER_TEST_PYTHON_RUNTIME:?missing CUSTOMER_TEST_PYTHON_RUNTIME}" \
        -I -S -c 'import email.parser,os,re,stat,sys
site=sys.argv[1]
manifest=sys.argv[2]
expected=(("jsonschema","4.23.0"),("rfc3339-validator","0.1.4"),("PyYAML","6.0.2"))
observed=[]
normalize=lambda value: re.sub(r"[-_.]+","_",value).lower()
for name,version in expected:
 matches=[entry for entry in os.listdir(site) if normalize(entry)==normalize(name+"-"+version+".dist-info")]
 if len(matches)!=1: raise SystemExit("dependency_dist_info_inventory:"+name)
 dist_path=os.path.join(site,matches[0])
 dist_entry=os.lstat(dist_path)
 if not stat.S_ISDIR(dist_entry.st_mode): raise SystemExit("dependency_dist_info_not_directory:"+dist_path)
 path=os.path.join(dist_path,"METADATA")
 entry=os.lstat(path)
 if not stat.S_ISREG(entry.st_mode): raise SystemExit("dependency_metadata_not_regular:"+path)
 with open(path,encoding="utf-8") as handle: parsed=email.parser.Parser().parse(handle)
 if [normalize(value) for value in parsed.get_all("Name",[])] != [normalize(name)] or parsed.get_all("Version") != [version]:
  raise SystemExit("dependency_metadata_mismatch:"+path)
 observed.append(f"{normalize(name)}:{dist_entry.st_dev}:{dist_entry.st_ino}:{entry.st_dev}:{entry.st_ino}")
snapshot="\n".join(observed)+"\n"
try:
 fd=os.open(manifest,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_CLOEXEC,0o600)
except FileExistsError:
 with open(manifest,encoding="ascii") as handle: prior=handle.read()
 if prior!=snapshot: raise SystemExit("dependency_site_identity_changed")
else:
 with os.fdopen(fd,"w",encoding="ascii") as handle: handle.write(snapshot)
' "${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}" \
        "${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}.integrity"
}

teardown() {
    cleanup_metadata_identity_fixture || return 1
    cleanup_site_fixture || return 1
    assert_darwin_dependency_site_integrity
}

test_seed() {
    "$PYTHON" "$CRYPTO_HELPER" seed
}

test_public_key() {
    "$PYTHON" "$CRYPTO_HELPER" keypair-from-seed | sed -n '1p'
}

test_private_key() {
    "$PYTHON" "$CRYPTO_HELPER" keypair-from-seed | sed -n '2p'
}

test_signature() {
    "$PYTHON" "$CRYPTO_HELPER" sign
}

run_validator() {
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format text
}

run_validator_json() {
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
}

run_validator_json_bounded() {
    local validator="$1" seconds="${2:-2}"
    run "$PYTHON" - "$validator" "$VALIDATOR_PYTHON" "$ROOT" "$TASK_ID" "$seconds" <<'PY'
import os
import signal
import subprocess
import sys

validator, python_bin, root, task, seconds = sys.argv[1:]
environment = os.environ.copy()
environment["CUSTOMER_DELIVERY_PYTHON"] = python_bin
process = subprocess.Popen(
    [validator, "--root", root, "--task", task, "--stage", "qa", "--format", "json"],
    env=environment,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    start_new_session=True,
    text=True,
)
try:
    output, _ = process.communicate(timeout=float(seconds))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    output, _ = process.communicate()
    sys.stdout.write(output)
    raise SystemExit(124)
sys.stdout.write(output)
raise SystemExit(process.returncode)
PY
}

commit_invalid_historical_requirements() {
    local kind="$1"
    local valid_copy="${BATS_TEST_TMPDIR}/valid-${kind}.yaml"
    local invalid_commit
    cp "$REQUIREMENTS" "$valid_copy" || return 1
    "$PYTHON" - "$REQUIREMENTS" "$kind" <<'PY' || return 1
import sys

import yaml

path, kind = sys.argv[1:]
payloads = {
    "null": b"null\n",
    "list": b"[]\n",
    "null-source-remarks": b"source_remarks: null\n",
    "invalid-utf8": b"source_remarks:\n  - source_id: source-0001\n    source_digest: \xff\n",
}
if kind in {"invalid-record", "legacy-schema-version"}:
    with open(path, encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    if kind == "invalid-record":
        document["source_remarks"][0]["source_digest"] = []
    else:
        document["schema_version"] = 0
        document["legacy_metadata"] = {"schema_family": "pre-canon"}
    with open(path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
else:
    with open(path, "wb") as handle:
        handle.write(payloads[kind])
PY
    git -C "$ROOT" add "datarim/tasks/${TASK_ID}-customer-requirements.yaml" || return 1
    git -C "$ROOT" commit -q -m "historical-${kind}" || return 1
    invalid_commit="$(git -C "$ROOT" rev-parse HEAD)" || return 1
    cp "$valid_copy" "$REQUIREMENTS" || return 1
    git -C "$ROOT" add "datarim/tasks/${TASK_ID}-customer-requirements.yaml" || return 1
    git -C "$ROOT" commit -q -m "restore-valid-after-${kind}" || return 1
    printf '%s\n' "$invalid_commit"
}

assert_source_history_parse_result() {
    local commit="$1"
    local result="$2"
    "$PYTHON" - "$commit" "$result" <<'PY'
import json
import sys

commit, raw = sys.argv[1:]
document = json.loads(raw)
assert document["decision"] == "NOT_MET"
assert document["status"] == "NOT_MET"
assert document["findings"] == [f"source_history_parse:{commit}"]
PY
}

build_test_framework() {
    local name="$1"
    TEST_FRAMEWORK="${BATS_TEST_TMPDIR}/framework-${name}"
    TEST_SCRIPT="${TEST_FRAMEWORK}/dev-tools/check-customer-delivery.sh"
    mkdir -p "${TEST_FRAMEWORK}/dev-tools" "${TEST_FRAMEWORK}/config"
    cp "$SCRIPT" "$TEST_SCRIPT" || return 1
    cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
        "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
        "${REPO_ROOT}/config/review-evolution.schema.json" \
        "${TEST_FRAMEWORK}/config/" || return 1
    chmod +x "$TEST_SCRIPT"
}

run_test_framework_json() {
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$TEST_SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
}

replace_test_script_literal() {
    local old="$1"
    local new="$2"
    "$PYTHON" - "$TEST_SCRIPT" "$old" "$new" <<'PY'
import sys

path, old, new = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
if old == 'PINNED_GIT = "/usr/bin/git"':
    old = 'PINNED_GIT = "/usr/bin/git" if PLATFORM == "Linux" else PINNED_DARWIN_GIT'
    trust = "    if not git_path_trusted:\n"
    if source.count(trust) != 1:
        raise SystemExit("test Git trust seam missing or ambiguous")
    source = source.replace(trust, "    if False:  # MUTATED:test_git_trust\n", 1)
if source.count(old) != 1:
    raise SystemExit(f"mutation seam missing or ambiguous: {old!r}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source.replace(old, new))
PY
}

rebind_test_openssl() {
    local executable="$1"
    local schema="${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    replace_test_script_literal \
        'PINNED_OPENSSL = sys.argv[12]' \
        "PINNED_OPENSSL = \"${executable}\"" || return 1
    replace_test_script_literal \
        '"Linux": "/usr/bin/openssl",' \
        "\"Linux\": \"${executable}\"," || return 1
    replace_test_script_literal \
        '({0} if PLATFORM == "Linux" else {0, os.geteuid()})' \
        '{0, os.geteuid()}' || return 1
    "$PYTHON" - "$TEST_SCRIPT" "$schema" "$executable" <<'PY' || return 1
import hashlib
import json
import sys

script_path, schema_path, executable = sys.argv[1:]
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
contract = schema["x-datarim-crypto-verifier-contract"]
old_digest = hashlib.sha256(
    json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
contract["platform_executables"]["Linux"] = executable
new_digest = hashlib.sha256(
    json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
with open(script_path, encoding="utf-8") as handle:
    source = handle.read()
if source.count(old_digest) != 1:
    raise SystemExit("CRYPTO_CONTRACT_DIGEST_MUTATION_SEAM_MISSING")
with open(script_path, "w", encoding="utf-8") as handle:
    handle.write(source.replace(old_digest, new_digest))
with open(schema_path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

authenticate_test_registry() {
    local expression="$1"
    local requirement_schema="${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    local receipt_schema="${TEST_FRAMEWORK}/config/customer-delivery-receipt.schema.json"
    local review_schema="${TEST_FRAMEWORK}/config/review-evolution.schema.json"
    local seed public_key secret_key fingerprint digest signature
    seed="$(test_seed)"
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    fingerprint="$($PYTHON -c 'import base64,hashlib,sys; print("sha256:"+hashlib.sha256(base64.b64decode(sys.argv[1])).hexdigest())' "$public_key")"
    yq -i "$expression" "$requirement_schema" || return 1
    digest="$($PYTHON - "$TEST_SCRIPT" "$requirement_schema" "$receipt_schema" "$review_schema" "$public_key" "$fingerprint" <<'PY'
import base64
import hashlib
import json
import sys

script_path, requirement_path, receipt_path, review_path, public_key, fingerprint = sys.argv[1:]
with open(script_path, encoding="utf-8") as handle:
    script = handle.read()
script = script.replace(
    'PINNED_REGISTRY_PUBLIC_KEY = "3hzCOohIkBiCEu9V2qNl8r0zc9iCZE/MbLFabv6/o18="',
    f'PINNED_REGISTRY_PUBLIC_KEY = "{public_key}"',
).replace(
    '"sha256:dfae487eaca4758d5b0e0ffc372d4594032dc59534ff1124a5b8351f2c923ccf"',
    f'"{fingerprint}"',
)
with open(script_path, "w", encoding="utf-8") as handle:
    handle.write(script)
with open(requirement_path, encoding="utf-8") as handle:
    schema = json.load(handle)
resolution = schema["x-datarim-signature-contract"]["key_resolution"]
anchor = resolution["registry_owner"]["trust_anchor"]
anchor["public_key"] = public_key
anchor["fingerprint"] = fingerprint
registry = resolution["bundled_registry"]
payload = {field: registry[field] for field in ("registry_id", "revision", "entries")}
digest = "sha256:" + hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
registry["digest"] = digest
with open(requirement_path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
with open(receipt_path, encoding="utf-8") as handle:
    receipt_schema = json.load(handle)
receipt_schema["x-datarim-trusted-authority-key-registry-ref"]["registry_digest"] = digest
with open(receipt_path, "w", encoding="utf-8") as handle:
    json.dump(receipt_schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
with open(review_path, encoding="utf-8") as handle:
    review_schema = json.load(handle)
review_schema["x-datarim-trusted-authority-key-registry-ref"]["registry_digest"] = digest
with open(review_path, "w", encoding="utf-8") as handle:
    json.dump(review_schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(digest)
PY
)" || return 1
    signature="$(printf '%s\n%s\n' "$secret_key" "$digest" | test_signature)"
    yq -i ".\"x-datarim-signature-contract\".key_resolution.bundled_registry.registry_signature = \"${signature}\"" "$requirement_schema"
}

reseal_and_sign_review() {
    local secret_key="$1"
    local digest signature
    digest="$($PYTHON - "$REVIEW" <<'PY'
import hashlib
import json
import sys

import yaml

APPROVAL_FIELDS = (
    "approved_digest", "authority_id", "authority_role", "approved_at",
    "evidence_ref", "algorithm", "key_id",
)


def digest(payload):
    canonical = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    review = yaml.safe_load(handle)
origin = review["originating_review"]
origin["review_digest"] = digest({
    "review_id": review["review_id"],
    "requirement_id": review["requirement_id"],
    "delivery_receipt_id": review["delivery_receipt_id"],
    "reviewer": review["reviewer"],
    "review_ref": origin["review_ref"],
    "state": origin["state"],
    "observed_at": origin["observed_at"],
    "evidence_ref": origin["evidence_ref"],
})
approval = origin["authority_approval"]
approval["approved_digest"] = origin["review_digest"]
approval["approval_payload_digest"] = digest({
    field: approval[field] for field in APPROVAL_FIELDS
})
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(review, handle, allow_unicode=True, sort_keys=False)
print(approval["approval_payload_digest"])
PY
)" || return 1
    signature="$(printf '%s\n%s\n' "$secret_key" "$digest" | test_signature)" || return 1
    yq -i ".originating_review.authority_approval.signature = \"${signature}\"" "$REVIEW"
}

reseal_and_sign_disposition() {
    local secret_key="$1"
    local digest signature
    digest="$($PYTHON - "$RECEIPT" <<'PY'
import hashlib
import json
import sys

import yaml

APPROVAL_FIELDS = (
    "approved_digest", "authority_id", "authority_role", "approved_at",
    "evidence_ref", "algorithm", "key_id",
)


def digest(payload):
    canonical = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    receipt = yaml.safe_load(handle)
chain = receipt["requirements"]["req-0001"]["coverage_chain"]
disposition = chain["customer_disposition"]
disposition["coverage_chain_digest"] = digest({
    field: value for field, value in chain.items()
    if field != "customer_disposition"
})
payload_fields = (
    "receipt_id", "requirement_set_id", "requirement_id",
    "coverage_chain_digest", "status", "recorded_at", "evidence_ref",
)
payload = {field: disposition[field] for field in payload_fields}
for optional in ("note", "superseded_by"):
    if optional in disposition:
        payload[optional] = disposition[optional]
disposition["disposition_digest"] = digest(payload)
approval = disposition["authority_approval"]
approval["approved_digest"] = disposition["disposition_digest"]
approval["approval_payload_digest"] = digest({
    field: approval[field] for field in APPROVAL_FIELDS
})
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(receipt, handle, allow_unicode=True, sort_keys=False)
print(approval["approval_payload_digest"])
PY
)" || return 1
    signature="$(printf '%s\n%s\n' "$secret_key" "$digest" | test_signature)" || return 1
    yq -i ".requirements.req-0001.coverage_chain.customer_disposition.authority_approval.signature = \"${signature}\"" "$RECEIPT"
}

sign_test_digest() {
    local secret_key="$1" digest="$2"
    printf '%s\n%s\n' "$secret_key" "$digest" | test_signature
}

prepare_two_requirement_fixture() {
    local second_state="${1:-APPROVED}" seed public_key secret_key digests_raw digest_value
    local -a digests
    local source_signature assertion_signature disposition_signature review_signature
    seed="$(test_seed)"
    # shellcheck disable=SC2016
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    # shellcheck disable=SC2016
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework two-requirements || return 1
    env TWO_REQUIREMENT_PUBLIC_KEY="$public_key" yq -i \
        '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
          "key_id":"key-two-requirements-0001",
          "authority_id":"authority-two-requirements-0001",
          "allowed_roles":["CUSTOMER","OPERATOR"],
          "public_key":strenv(TWO_REQUIREMENT_PUBLIC_KEY),
          "status":"ACTIVE",
          "valid_from":"2026-01-01T00:00:00Z",
          "valid_until":"2036-01-01T00:00:00Z"
        }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1
    "$PYTHON" - "$TEST_SCRIPT" "${TEST_FRAMEWORK}/config/review-evolution.schema.json" "$public_key" <<'PY' || return 1
import base64
import hashlib
import json
import re
import sys
script_path, schema_path, public_key = sys.argv[1:]
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
authority = schema["x-datarim-originating-review-contract"]["inventory_authority"]
authority.update({
    "authority_id": "authority-two-requirements-0001",
    "key_id": "key-two-requirements-0001",
    "public_key": public_key,
    "fingerprint": "sha256:" + hashlib.sha256(base64.b64decode(public_key)).hexdigest(),
})
contract_digest = hashlib.sha256(json.dumps(
    schema["x-datarim-originating-review-contract"], ensure_ascii=False,
    sort_keys=True, separators=(",", ":")
).encode("utf-8")).hexdigest()
with open(schema_path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
with open(script_path, encoding="utf-8") as handle:
    source = handle.read()
source, count = re.subn(
    r'("review:x-datarim-originating-review-contract": ")[0-9a-f]{64}("[,])',
    rf'\g<1>{contract_digest}\g<2>', source,
)
if count != 1:
    raise SystemExit("review contract digest seam missing")
with open(script_path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    digests_raw="$("$PYTHON" - "$REQUIREMENTS" "$RECEIPT" "$REVIEW" "$second_state" <<'PY'
import copy
import hashlib
import json
import sys

import yaml

requirements_path, receipt_path, review_path, second_state = sys.argv[1:]
with open(requirements_path, encoding="utf-8") as handle:
    requirements = yaml.safe_load(handle)
with open(receipt_path, encoding="utf-8") as handle:
    receipt = yaml.safe_load(handle)
with open(review_path, encoding="utf-8") as handle:
    review = yaml.safe_load(handle)


def replace(value):
    if isinstance(value, str):
        return value.replace("req-0001", "req-0002").replace(
            "source-0001", "source-0002"
        ).replace("assertion-0001", "assertion-0002").replace(
            "review-0001", "review-0002"
        )
    if isinstance(value, list):
        return [replace(item) for item in value]
    if isinstance(value, dict):
        return {replace(key): replace(item) for key, item in value.items()}
    return value


def digest(payload):
    encoded = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


approval_fields = (
    "approved_digest", "authority_id", "authority_role", "approved_at",
    "evidence_ref", "algorithm", "key_id",
)
source = replace(copy.deepcopy(requirements["source_remarks"][0]))
source["authority_approval"].update({
    "authority_id": "authority-two-requirements-0001",
    "authority_role": "CUSTOMER",
    "key_id": "key-two-requirements-0001",
})
source_payload = {
    field: source[field]
    for field in (
        "source_id", "revision", "source_tier", "verbatim_quote", "captured_at",
        "requirement_ids", "prework_assignments",
    )
}
for optional in ("locale", "source_ref", "supersedes_source_digest"):
    if optional in source:
        source_payload[optional] = source[optional]
source_payload["requirement_ids"] = sorted(source_payload["requirement_ids"])
source_payload["prework_assignments"] = sorted(
    source_payload["prework_assignments"],
    key=lambda item: (item["requirement_id"], item["task_id"], item["epic_id"]),
)
source["source_digest"] = digest(source_payload)
source_approval = source["authority_approval"]
source_approval["approved_digest"] = source["source_digest"]
source_approval["approval_payload_digest"] = digest({
    field: source_approval[field] for field in approval_fields
})
assertion = source["tier1_assertions"][0]
assertion["source_digest"] = source["source_digest"]
assertion["authority_approval"].update({
    "authority_id": "authority-two-requirements-0001",
    "authority_role": "CUSTOMER",
    "key_id": "key-two-requirements-0001",
})
assertion["assertion_digest"] = digest({
    key: value for key, value in assertion.items()
    if key not in {"assertion_digest", "authority_approval"}
})
assertion_approval = assertion["authority_approval"]
assertion_approval["approved_digest"] = assertion["assertion_digest"]
assertion_approval["approval_payload_digest"] = digest({
    field: assertion_approval[field] for field in approval_fields
})
requirements["source_remarks"].append(source)
requirements["requirements"]["req-0002"] = replace(
    copy.deepcopy(requirements["requirements"]["req-0001"])
)

delivery = replace(copy.deepcopy(receipt["requirements"]["req-0001"]))
chain = delivery["coverage_chain"]
disposition = chain["customer_disposition"]
disposition["authority_approval"].update({
    "authority_id": "authority-two-requirements-0001",
    "authority_role": "OPERATOR",
    "key_id": "key-two-requirements-0001",
})
disposition["coverage_chain_digest"] = digest({
    key: value for key, value in chain.items() if key != "customer_disposition"
})
disposition_payload = {
    field: disposition[field]
    for field in (
        "receipt_id", "requirement_set_id", "requirement_id",
        "coverage_chain_digest", "status", "recorded_at", "evidence_ref",
    )
}
for optional in ("note", "superseded_by"):
    if optional in disposition:
        disposition_payload[optional] = disposition[optional]
disposition["disposition_digest"] = digest(disposition_payload)
disposition_approval = disposition["authority_approval"]
disposition_approval["approved_digest"] = disposition["disposition_digest"]
disposition_approval["approval_payload_digest"] = digest({
    field: disposition_approval[field] for field in approval_fields
})
receipt["requirements"]["req-0002"] = delivery

review_digest = ""
manifest_digest = ""
if "originating_review_inventory" in review:
    item = replace(copy.deepcopy(review["originating_review_inventory"][0]))
    item["authority_approval"].update({
        "authority_id": "authority-two-requirements-0001",
        "authority_role": "OPERATOR",
        "key_id": "key-two-requirements-0001",
    })
    item["state"] = second_state
    item["review_digest"] = digest({
        field: item[field]
        for field in (
            "review_id", "requirement_id", "delivery_receipt_id", "reviewer",
            "review_ref", "state", "observed_at", "evidence_ref",
        )
    })
    item_approval = item["authority_approval"]
    item_approval["approved_digest"] = item["review_digest"]
    item_approval["approval_payload_digest"] = digest({
        field: item_approval[field] for field in approval_fields
    })
    review["originating_review_inventory"].append(item)
    review_digest = item_approval["approval_payload_digest"]
    manifest = review["originating_review_inventory_manifest"]
    manifest["review_pairs"].append({
        "review_id": item["review_id"],
        "requirement_id": item["requirement_id"],
    })
    manifest["review_pairs"] = sorted(
        manifest["review_pairs"],
        key=lambda pair: (pair["review_id"], pair["requirement_id"]),
    )
    manifest["inventory_digest"] = digest({
        "delivery_receipt_id": manifest["delivery_receipt_id"],
        "review_pairs": manifest["review_pairs"],
    })
    manifest_approval = manifest["authority_approval"]
    manifest_approval.update({
        "approved_digest": manifest["inventory_digest"],
        "authority_id": "authority-two-requirements-0001",
        "authority_role": "OPERATOR",
        "key_id": "key-two-requirements-0001",
    })
    manifest_approval["approval_payload_digest"] = digest({
        field: manifest_approval[field] for field in approval_fields
    })
    manifest_digest = manifest_approval["approval_payload_digest"]

with open(requirements_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(requirements, handle, allow_unicode=True, sort_keys=False)
with open(receipt_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(receipt, handle, allow_unicode=True, sort_keys=False)
with open(review_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(review, handle, allow_unicode=True, sort_keys=False)
print(source_approval["approval_payload_digest"])
print(assertion_approval["approval_payload_digest"])
print(disposition_approval["approval_payload_digest"])
print(review_digest)
print(manifest_digest)
PY
)" || return 1
    while IFS= read -r digest_value; do
        digests[${#digests[@]}]="$digest_value"
    done <<<"$digests_raw"
    [[ "${#digests[@]}" -eq 5 ]] || {
        printf 'two_requirement_digest_inventory=%s raw=%s\n' "${#digests[@]}" "$digests_raw"
        return 1
    }
    source_signature="$(sign_test_digest "$secret_key" "${digests[0]}")" || return 1
    assertion_signature="$(sign_test_digest "$secret_key" "${digests[1]}")" || return 1
    disposition_signature="$(sign_test_digest "$secret_key" "${digests[2]}")" || return 1
    yq -i ".source_remarks[1].authority_approval.signature = \"${source_signature}\" |
        .source_remarks[1].tier1_assertions[0].authority_approval.signature = \"${assertion_signature}\"" \
        "$REQUIREMENTS" || return 1
    yq -i ".requirements.req-0002.coverage_chain.customer_disposition.authority_approval.signature = \"${disposition_signature}\"" \
        "$RECEIPT" || return 1
    if [[ -n "${digests[3]}" ]]; then
        review_signature="$(sign_test_digest "$secret_key" "${digests[3]}")" || return 1
        yq -i ".originating_review_inventory[1].authority_approval.signature = \"${review_signature}\"" \
            "$REVIEW" || return 1
    fi
    if [[ -n "${digests[4]}" ]]; then
        review_signature="$(sign_test_digest "$secret_key" "${digests[4]}")" || return 1
        yq -i ".originating_review_inventory_manifest.authority_approval.signature = \"${review_signature}\"" \
            "$REVIEW" || return 1
    fi
}

prepare_authenticated_prework_fixture() {
    local expression="$1"
    local seed public_key secret_key digests source_digest assertion_digest
    seed="$(test_seed)"
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework authenticated-prework || return 1
    env PREWORK_PUBLIC_KEY="$public_key" yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
      "key_id":"key-prework-test-0001",
      "authority_id":"authority-prework-test-0001",
      "allowed_roles":["CUSTOMER"],
      "public_key":strenv(PREWORK_PUBLIC_KEY),
      "status":"ACTIVE",
      "valid_from":"2026-01-01T00:00:00Z",
      "valid_until":"2036-01-01T00:00:00Z"
    }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1
    yq -i '.source_remarks[0].authority_approval.authority_id = "authority-prework-test-0001" |
        .source_remarks[0].authority_approval.key_id = "key-prework-test-0001" |
        .source_remarks[0].tier1_assertions[0].authority_approval.authority_id = "authority-prework-test-0001" |
        .source_remarks[0].tier1_assertions[0].authority_approval.key_id = "key-prework-test-0001"' "$REQUIREMENTS" || return 1
    yq -i "$expression" "$REQUIREMENTS" || return 1
    digests="$($PYTHON - "$REQUIREMENTS" <<'PY'
import hashlib
import json
import sys

import yaml

APPROVAL_FIELDS = (
    "approved_digest", "authority_id", "authority_role", "approved_at",
    "evidence_ref", "algorithm", "key_id",
)


def digest(payload):
    canonical = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
source = document["source_remarks"][0]
source_payload = {
    "source_id": source["source_id"],
    "revision": source["revision"],
    "source_tier": source["source_tier"],
    "verbatim_quote": source["verbatim_quote"],
    "captured_at": source["captured_at"],
    "requirement_ids": sorted(source["requirement_ids"]),
    "prework_assignments": sorted(
        source["prework_assignments"],
        key=lambda item: (item["requirement_id"], item["task_id"], item["epic_id"]),
    ),
}
for optional in ("locale", "source_ref", "supersedes_source_digest"):
    if optional in source:
        source_payload[optional] = source[optional]
source["source_digest"] = digest(source_payload)
source_approval = source["authority_approval"]
source_approval["approved_digest"] = source["source_digest"]
source_approval["approval_payload_digest"] = digest({
    field: source_approval[field] for field in APPROVAL_FIELDS
})
assertion = source["tier1_assertions"][0]
assertion["source_digest"] = source["source_digest"]
assertion["assertion_digest"] = digest({
    key: value for key, value in assertion.items()
    if key not in {"assertion_digest", "authority_approval"}
})
assertion_approval = assertion["authority_approval"]
assertion_approval["approved_digest"] = assertion["assertion_digest"]
assertion_approval["approval_payload_digest"] = digest({
    field: assertion_approval[field] for field in APPROVAL_FIELDS
})
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
print(source_approval["approval_payload_digest"])
print(assertion_approval["approval_payload_digest"])
PY
)" || return 1
    source_digest="${digests%%$'\n'*}"
    assertion_digest="${digests##*$'\n'}"
    local source_signature assertion_signature
    source_signature="$(printf '%s\n%s\n' "$secret_key" "$source_digest" | test_signature)" || return 1
    assertion_signature="$(printf '%s\n%s\n' "$secret_key" "$assertion_digest" | test_signature)" || return 1
    yq -i ".source_remarks[0].authority_approval.signature = \"${source_signature}\" |
        .source_remarks[0].tier1_assertions[0].authority_approval.signature = \"${assertion_signature}\"" "$REQUIREMENTS"
}

prepare_signed_review_fixture() {
    local state="$1"
    local status="${2-ACTIVE}"
    local valid_from="${3-2026-01-01T00:00:00Z}"
    local valid_until="${4-2036-01-01T00:00:00Z}"
    local seed public_key secret_key
    seed="$(test_seed)"
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework "review-${state}-${status}" || return 1
    env REVIEW_PUBLIC_KEY="$public_key" REVIEW_KEY_STATUS="$status" \
        REVIEW_VALID_FROM="$valid_from" REVIEW_VALID_UNTIL="$valid_until" \
        yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
          "key_id":"key-review-test-0001",
          "authority_id":"authority-review-test-0001",
          "allowed_roles":["OPERATOR"],
          "public_key":strenv(REVIEW_PUBLIC_KEY),
          "status":strenv(REVIEW_KEY_STATUS),
          "valid_from":strenv(REVIEW_VALID_FROM),
          "valid_until":strenv(REVIEW_VALID_UNTIL)
        }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1
    yq -i ".originating_review.state = \"${state}\" |
        .originating_review.authority_approval.authority_id = \"authority-review-test-0001\" |
        .originating_review.authority_approval.authority_role = \"OPERATOR\" |
        .originating_review.authority_approval.key_id = \"key-review-test-0001\"" "$REVIEW" || return 1
    reseal_and_sign_review "$secret_key"
}

prepare_authenticated_disposition_fixture() {
    local expression="$1" seed public_key secret_key
    seed="$(test_seed)"
    # shellcheck disable=SC2016
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    # shellcheck disable=SC2016
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework authenticated-disposition || return 1
    env DISPOSITION_PUBLIC_KEY="$public_key" yq -i \
        '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
          "key_id":"key-disposition-test-0001",
          "authority_id":"authority-disposition-test-0001",
          "allowed_roles":["OPERATOR"],
          "public_key":strenv(DISPOSITION_PUBLIC_KEY),
          "status":"ACTIVE",
          "valid_from":"2026-01-01T00:00:00Z",
          "valid_until":"2036-01-01T00:00:00Z"
        }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1
    "$PYTHON" - "${TEST_FRAMEWORK}/config/customer-delivery-receipt.schema.json" <<'PY' || return 1
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    schema = json.load(handle)
def relax(value):
    if isinstance(value, dict):
        if value.get("pattern") == r"\S":
            del value["pattern"]
        for nested in value.values():
            relax(nested)
    elif isinstance(value, list):
        for nested in value:
            relax(nested)
relax(schema)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
    yq -i "$expression |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.authority_id = \"authority-disposition-test-0001\" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.authority_role = \"OPERATOR\" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.key_id = \"key-disposition-test-0001\"" \
        "$RECEIPT" || return 1
    reseal_and_sign_disposition "$secret_key"
}

prepare_same_requirement_review_inventory() {
    local second_state="${1:-APPROVED}" seed public_key secret_key digests_raw digest_value
    local -a digests
    local review_signature manifest_signature
    seed="$(test_seed)"
    # shellcheck disable=SC2016
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    # shellcheck disable=SC2016
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework same-requirement-reviews || return 1
    env REVIEW_PUBLIC_KEY="$public_key" yq -i \
        '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
          "key_id":"key-review-test-0002",
          "authority_id":"authority-review-test-0002",
          "allowed_roles":["OPERATOR"],
          "public_key":strenv(REVIEW_PUBLIC_KEY),
          "status":"ACTIVE",
          "valid_from":"2026-01-01T00:00:00Z",
          "valid_until":"2036-01-01T00:00:00Z"
        }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1
    "$PYTHON" - "$TEST_SCRIPT" "${TEST_FRAMEWORK}/config/review-evolution.schema.json" "$public_key" <<'PY' || return 1
import base64
import hashlib
import json
import re
import sys

script_path, schema_path, public_key = sys.argv[1:]
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
authority = schema["x-datarim-originating-review-contract"]["inventory_authority"]
authority["authority_id"] = "authority-review-test-0002"
authority["key_id"] = "key-review-test-0002"
authority["public_key"] = public_key
authority["fingerprint"] = "sha256:" + hashlib.sha256(base64.b64decode(public_key)).hexdigest()
contract = schema["x-datarim-originating-review-contract"]
contract_digest = hashlib.sha256(json.dumps(
    contract, ensure_ascii=False, sort_keys=True, separators=(",", ":")
).encode("utf-8")).hexdigest()
with open(schema_path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
with open(script_path, encoding="utf-8") as handle:
    source = handle.read()
pattern = r'("review:x-datarim-originating-review-contract": ")[0-9a-f]{64}("[,])'
source, count = re.subn(pattern, rf'\g<1>{contract_digest}\g<2>', source)
if count != 1:
    raise SystemExit("review contract digest seam missing")
with open(script_path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    digests_raw="$("$PYTHON" - "$REVIEW" "$second_state" <<'PY'
import copy
import hashlib
import json
import sys
import yaml

path, state = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    review = yaml.safe_load(handle)

def digest(payload):
    return "sha256:" + hashlib.sha256(json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")).hexdigest()

approval_fields = (
    "approved_digest", "authority_id", "authority_role", "approved_at",
    "evidence_ref", "algorithm", "key_id",
)
item = copy.deepcopy(review["originating_review_inventory"][0])
item["review_id"] = "review-0002"
item["review_ref"] = "review-system/reviews/review-0002"
item["evidence_ref"] = "artifacts/reviews/review-0002-approval.json"
item["state"] = state
item["authority_approval"].update({
    "authority_id": "authority-review-test-0002",
    "authority_role": "OPERATOR",
    "key_id": "key-review-test-0002",
    "evidence_ref": "artifacts/reviews/review-0002-authority-approval.json",
})
item["review_digest"] = digest({field: item[field] for field in (
    "review_id", "requirement_id", "delivery_receipt_id", "reviewer",
    "review_ref", "state", "observed_at", "evidence_ref",
)})
approval = item["authority_approval"]
approval["approved_digest"] = item["review_digest"]
approval["approval_payload_digest"] = digest({field: approval[field] for field in approval_fields})
review["originating_review_inventory"].append(item)
manifest = review["originating_review_inventory_manifest"]
manifest["review_pairs"] = [
    {"review_id": "review-0001", "requirement_id": "req-0001"},
    {"review_id": "review-0002", "requirement_id": "req-0001"},
]
manifest["inventory_digest"] = digest({
    "delivery_receipt_id": manifest["delivery_receipt_id"],
    "review_pairs": manifest["review_pairs"],
})
manifest_approval = manifest["authority_approval"]
manifest_approval.update({
    "approved_digest": manifest["inventory_digest"],
    "authority_id": "authority-review-test-0002",
    "authority_role": "OPERATOR",
    "key_id": "key-review-test-0002",
})
manifest_approval["approval_payload_digest"] = digest({
    field: manifest_approval[field] for field in approval_fields
})
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(review, handle, allow_unicode=True, sort_keys=False)
print(approval["approval_payload_digest"])
print(manifest_approval["approval_payload_digest"])
PY
)" || return 1
    while IFS= read -r digest_value; do
        digests[${#digests[@]}]="$digest_value"
    done <<<"$digests_raw"
    [[ "${#digests[@]}" -eq 2 ]] || {
        printf 'same_requirement_digest_inventory=%s raw=%s\n' "${#digests[@]}" "$digests_raw"
        return 1
    }
    review_signature="$(sign_test_digest "$secret_key" "${digests[0]}")" || return 1
    manifest_signature="$(sign_test_digest "$secret_key" "${digests[1]}")" || return 1
    yq -i ".originating_review_inventory[1].authority_approval.signature = \"${review_signature}\" |
        .originating_review_inventory_manifest.authority_approval.signature = \"${manifest_signature}\"" \
        "$REVIEW"
}

@test "complete canonical delivery chain is MET" {
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"decision=MET"* ]] \
        || { printf 'canonical_status=%s canonical_output=%s\n' "$status" "$output"; return 1; }
}

@test "authorized disposition reseal cannot make whitespace U4 evidence MET" {
    prepare_authenticated_disposition_fixture \
        '.requirements.req-0001.coverage_chain.red_green.red.command = "   "' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"u4_nonblank_required:req-0001:red_green.red.command"* ]]
}

@test "signed delivery bundle cannot replay under another CLI task identity" {
    local replay_task="WEB-9999"
    git -C "$ROOT" mv "$REQUIREMENTS" \
        "$ROOT/datarim/tasks/${replay_task}-customer-requirements.yaml"
    git -C "$ROOT" mv "$RECEIPT" \
        "$ROOT/datarim/receipts/${replay_task}-customer-delivery.yaml"
    git -C "$ROOT" mv "$REVIEW" \
        "$ROOT/datarim/receipts/${replay_task}-review-evolution.yaml"
    git -C "$ROOT" commit -q -m "replay unchanged signed bundle under another task"

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$replay_task" --stage qa --format text
    if [ "$status" -ne 1 ]; then
        printf 'replay_status=%s replay_output=%s\n' "$status" "$output"
    fi
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"task_identity_mismatch:WEB-9999:WEB-0001"* ]]
}

@test "signed requirement set cannot replay under a substituted outer set" {
    yq -i '.requirement_set_id = "reqset-9999"' "$REQUIREMENTS"
    yq -i '.requirement_set_id = "reqset-9999" |
        .parent_links[] |= select(.relation == "requirement_set").id = "reqset-9999"' "$RECEIPT"

    run_validator
    if [ "$status" -ne 1 ]; then
        printf 'reqset_replay_status=%s reqset_replay_output=%s\n' "$status" "$output"
    fi
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"requirement_set_signed_binding_mismatch:req-0001"* ]]
}

@test "signed canonical epic identity rejects coordinated receipt and review parent replay" {
    yq -i '(.parent_links[] | select(.relation == "epic").id) = "epic:attacker:9999"' "$RECEIPT"
    yq -i '(.parent_links[] | select(.relation == "epic").id) = "epic:attacker:9999"' "$REVIEW"

    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and "epic_identity_mismatch:epic:attacker:9999:epic:web:0000" in d["findings"]' "$output"
}

@test "post-work task epic and review reseal cannot reattribute signed pre-work authority" {
    local replay_task="EVIL-9999" seed public_key secret_key
    seed="$(test_seed)"
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework postwork-reattribution || return 1
    env RESEAL_PUBLIC_KEY="$public_key" yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
      "key_id":"key-postwork-reseal-0001",
      "authority_id":"authority-postwork-reseal-0001",
      "allowed_roles":["OPERATOR"],
      "public_key":strenv(RESEAL_PUBLIC_KEY),
      "status":"ACTIVE",
      "valid_from":"2026-01-01T00:00:00Z",
      "valid_until":"2036-01-01T00:00:00Z"
    }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1

    yq -i '.requirements.req-0001.acceptance.implementation.task_id = "task:evil:9999"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.task_id = "task:evil:9999" |
        (.parent_links[] | select(.relation == "task").id) = "task:evil:9999" |
        (.parent_links[] | select(.relation == "epic").id) = "epic:evil:0000" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.authority_id = "authority-postwork-reseal-0001" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.key_id = "key-postwork-reseal-0001"' "$RECEIPT"
    yq -i '(.parent_links[] | select(.relation == "task").id) = "task:evil:9999" |
        (.parent_links[] | select(.relation == "epic").id) = "epic:evil:0000"' "$REVIEW"
    reseal_and_sign_disposition "$secret_key" || return 1

    git -C "$ROOT" mv "$REQUIREMENTS" "$ROOT/datarim/tasks/${replay_task}-customer-requirements.yaml"
    git -C "$ROOT" mv "$RECEIPT" "$ROOT/datarim/receipts/${replay_task}-customer-delivery.yaml"
    git -C "$ROOT" mv "$REVIEW" "$ROOT/datarim/receipts/${replay_task}-review-evolution.yaml"
    git -C "$ROOT" add datarim
    git -C "$ROOT" commit -q -m "coordinated post-work reattribution"

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$TEST_SCRIPT" --root "$ROOT" --task "$replay_task" --stage qa --format json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert {"acceptance_prework_task_mismatch:req-0001", "receipt_prework_task_mismatch:req-0001"} <= set(d["findings"])' "$output"
}

@test "post-work knowledge and start-time reseal cannot rewrite signed pre-work authority" {
    local seed public_key secret_key
    seed="$(test_seed)"
    public_key="$(printf '%s\n' "$seed" | test_public_key)"
    secret_key="$(printf '%s\n' "$seed" | test_private_key)"
    build_test_framework postwork-u3-reseal || return 1
    env RESEAL_PUBLIC_KEY="$public_key" yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [{
      "key_id":"key-u3-reseal-0001",
      "authority_id":"authority-u3-reseal-0001",
      "allowed_roles":["OPERATOR"],
      "public_key":strenv(RESEAL_PUBLIC_KEY),
      "status":"ACTIVE",
      "valid_from":"2026-01-01T00:00:00Z",
      "valid_until":"2036-01-01T00:00:00Z"
    }] | ."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= sort_by(.key_id)' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" || return 1
    authenticate_test_registry '.' || return 1

    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].revision = "4" |
        .requirements.req-0001.acceptance.implementation.started_at = "2026-01-02T09:30:00Z"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.skills[0].revision = "4" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.authority_id = "authority-u3-reseal-0001" |
        .requirements.req-0001.coverage_chain.customer_disposition.authority_approval.key_id = "key-u3-reseal-0001"' "$RECEIPT"
    reseal_and_sign_disposition "$secret_key" || return 1

    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert {"prework_knowledge_selection_mismatch:req-0001", "prework_implementation_started_at_mismatch:req-0001"} <= set(d["findings"])' "$output"
}

@test "authenticated assertion pre-work assignment must equal its signed source assignment" {
    prepare_authenticated_prework_fixture '.source_remarks[0].tier1_assertions[0].prework_assignment.task_id = "task:evil:9999" |
        .source_remarks[0].tier1_assertions[0].prework_assignment.epic_id = "epic:evil:0000"' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "assertion_prework_assignment_mismatch:assertion-0001" in d["findings"]' "$output"
}

@test "authenticated source pre-work assignments are exact per requirement" {
    prepare_authenticated_prework_fixture '.source_remarks[0].prework_assignments += [{
        "requirement_id":"req-0001",
        "task_id":"task:web:9999",
        "epic_id":"epic:web:0000",
        "knowledge_selection_digest":"sha256:4321e061f0e07de3203a3b0b474a2bb05cc30d3db2dae345f6c637eab61f1277",
        "implementation_started_at":"2026-01-02T10:00:00Z"
    }]' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "source_prework_assignment_duplicate:source-0001" in d["findings"]' "$output"
}

@test "authenticated pre-work epic must be canonical for its task prefix" {
    prepare_authenticated_prework_fixture '.source_remarks[0].prework_assignments[0].epic_id = "epic:evil:0000" |
        .source_remarks[0].tier1_assertions[0].prework_assignment.epic_id = "epic:evil:0000"' || return 1
    yq -i '(.parent_links[] | select(.relation == "epic").id) = "epic:evil:0000"' "$RECEIPT"
    yq -i '(.parent_links[] | select(.relation == "epic").id) = "epic:evil:0000"' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "prework_task_epic_mismatch:assertion-0001" in d["findings"]' "$output"
}

@test "acceptance task must equal the authenticated pre-work assignment" {
    yq -i '.requirements.req-0001.acceptance.implementation.task_id = "task:evil:9999"' "$REQUIREMENTS"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "acceptance_prework_task_mismatch:req-0001" in d["findings"]' "$output"
}

@test "authenticated review task parent must equal the signed pre-work task" {
    yq -i '(.parent_links[] | select(.relation == "task").id) = "task:evil:9999"' "$REVIEW"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "review_task_identity_mismatch" in d["findings"]' "$output"
}

@test "authenticated review epic parent must equal the signed canonical epic" {
    yq -i '(.parent_links[] | select(.relation == "epic").id) = "epic:attacker:9999"' "$REVIEW"

    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and "review_epic_identity_mismatch:epic:attacker:9999:epic:web:0000" in d["findings"]' "$output"
}

@test "all hard semantic stages enforce the same delivery decision" {
    local stage
    for stage in qa compliance archive; do
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
            "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage "$stage" --format json
        [ "$status" -eq 0 ] \
            && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["decision"] == "MET" and d["stage"] == sys.argv[2]' "$output" "$stage" \
            || return 1
    done
}

@test "missing verbatim provenance and broken bidirectional mapping are NOT_MET" {
    yq -i 'del(.source_remarks[0].verbatim_quote)' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:requirements"* ]]
}

@test "exact source quotes must agree with every mapped Tier-1 remark" {
    yq -i '.requirements.req-0001.acceptance.exact_source_quotes[0].verbatim_quote = "Derived paraphrase only."' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"exact_quote_mismatch:req-0001"* ]]
}

@test "tool-only acceptance cannot satisfy a visitor-visible requirement" {
    yq -i '.requirements.req-0001.acceptance.evidence.method = "CLI and CI checks only."' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:requirements"* ]]
}

@test "post-hoc knowledge selection is NOT_MET" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "2026-01-02T10:00:01Z" |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_before_implementation = true |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].immutable = true |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].revision = "1"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.roles[0].selected_at = "2026-01-02T10:00:01Z"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"knowledge_selected_post_hoc:req-0001:roles"* ]]
}

@test "mutable or unpinned knowledge is NOT_MET" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].immutable = false' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:requirements"* ]] \
        || return 1

    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].immutable = true |
        .requirements.req-0001.acceptance.knowledge_selection.skills[0].revision = "main"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.skills[0].revision = "main"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"knowledge_revision_unpinned:req-0001:skills"* ]]
}

@test "Gap and Unbound knowledge permit capability work but not delivered product claims" {
    local marker
    for marker in Gap Unbound; do
        build_marker="$marker"
        yq -i ".requirements.req-0001.acceptance.knowledge_selection.roles[0].id = \"${build_marker}\"" "$REQUIREMENTS"
        yq -i ".requirements.req-0001.coverage_chain.selected_knowledge.roles[0].id = \"${build_marker}\"" "$RECEIPT"
        run_validator
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"unbound_product_delivery:req-0001:roles"* ]] \
            || return 1
    done
}

@test "a user-facing requirement and parent need a visitor-visible delta" {
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = []' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"zero_visitor_visible_delta:req-0001"* ]]
}

@test "missing merge deploy live or disposition edges are NOT_MET" {
    local edge
    for edge in merged_revision deployed_revision live_evidence customer_disposition; do
        cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
        yq -i ".requirements.req-0001.coverage_status = \"NOT_MET\" |
            .requirements.req-0001.missing_edges = [\"${edge}\"] |
            del(.requirements.req-0001.coverage_chain.${edge})" "$RECEIPT"
        run_validator
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"missing_edge:req-0001:${edge}"* ]] \
            || return 1
    done
}

@test "production deployment SHA and digest must equal the merged accepted revision" {
    yq -i '.requirements.req-0001.coverage_chain.deployed_revision.revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_revision_mismatch:req-0001"* ]]
}

@test "receipt source quote digests exactly bind every linked source quote" {
    yq -i '.requirements.req-0001.coverage_chain.requirement.source_quote_digests[0].digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_quote_digest_mismatch:req-0001:source-0001"* ]]
}

@test "receipt selected knowledge exactly equals the accepted selection" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].revision = "4"' "$REQUIREMENTS"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert "knowledge_selection_mismatch:req-0001" in d["findings"]' "$output"
}

@test "in-progress product fix is separate from originating review closure" {
    yq -i '.product_fix.status = "IN_PROGRESS"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"product_fix_not_delivered:req-0001"* ]] \
        && [[ "$output" != *"parent_review_not_closed:req-0001"* ]]
}

@test "originating review digest binds every canonical review field" {
    yq -i '.originating_review.evidence_ref = "artifacts/reviews/tampered.json"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_digest_mismatch:review-0001"* ]]
}

@test "originating review approved digest equals its canonical review digest" {
    yq -i '.originating_review.authority_approval.approved_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_digest_mismatch:review-0001"* ]]
}

@test "originating review approval payload digest is canonical" {
    yq -i '.originating_review.authority_approval.evidence_ref = "artifacts/reviews/tampered-approval.json"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_payload_digest_mismatch:review-0001"* ]]
}

@test "originating review signature verifies over raw approval payload digest" {
    yq -i '.originating_review.authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_signature_invalid:review-0001"* ]]
}

@test "originating review rejects an unknown authority key" {
    yq -i '.originating_review.authority_approval.key_id = "key-unknown-0001"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_key_unknown:review-0001:key-unknown-0001"* ]]
}

@test "originating review authority identity equals its trusted key binding" {
    yq -i '.originating_review.authority_approval.authority_id = "authority-attacker-0001"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_authority_mismatch:review-0001"* ]]
}

@test "originating review authority role is allowed by its trusted key binding" {
    yq -i '.originating_review.authority_approval.authority_role = "CUSTOMER"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_role_unauthorized:review-0001"* ]]
}

@test "originating review rejects a revoked approval key" {
    prepare_signed_review_fixture APPROVED REVOKED || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_key_not_active:review-0001"* ]]
}

@test "originating review rejects a not-yet-valid approval key" {
    prepare_signed_review_fixture APPROVED ACTIVE "2027-01-01T00:00:00Z" || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_key_not_yet_valid:review-0001"* ]]
}

@test "originating review rejects an expired approval key" {
    prepare_signed_review_fixture APPROVED ACTIVE "2025-01-01T00:00:00Z" "2026-01-03T14:00:00Z" || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_approval_key_expired:review-0001"* ]]
}

@test "originating review observation cannot postdate review completion" {
    yq -i '.originating_review.observed_at = "2026-01-03T15:00:01Z"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_observed_after_reviewed_at:review-0001"* ]]
}

@test "originating review reference rejects a whitespace-only value" {
    yq -i '.originating_review.review_ref = "   "' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:review"* ]]
}

@test "originating review evidence reference rejects a whitespace-only value" {
    yq -i '.originating_review.evidence_ref = "   "' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:review"* ]]
}

@test "originating review registry reference is pinned to the bundled registry" {
    build_test_framework review-registry-ref || return 1
    yq -i '."x-datarim-trusted-authority-key-registry-ref".registry_id = "registry-attacker-0001"' \
        "${TEST_FRAMEWORK}/config/review-evolution.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"review_trust_registry_ref_mismatch"* ]]
}

@test "originating review requirement identity is cross-bound" {
    yq -i '.requirement_id = "req-0002"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"review_requirement_mismatch:req-0002"* ]]
}

@test "originating review receipt identity is cross-bound" {
    yq -i '.delivery_receipt_id = "receipt-0002"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"review_receipt_mismatch"* ]]
}

@test "originating review replay under another review identity is rejected" {
    yq -i '.review_id = "review-0002"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_digest_mismatch:review-0002"* ]]
}

@test "coordinated originating review reseal still requires a new signature" {
    yq -i '.originating_review.state = "CHANGES_REQUESTED" |
        .originating_review.evidence_ref = "artifacts/reviews/changes-requested.json"' "$REVIEW"
    reseal_and_sign_review "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" || return 1
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_signature_invalid:review-0001"* ]]
}

@test "authenticated OPEN originating review blocks closure" {
    prepare_signed_review_fixture OPEN || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0001"* ]]
}

@test "authenticated CHANGES_REQUESTED originating review blocks closure" {
    prepare_signed_review_fixture CHANGES_REQUESTED || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0001"* ]]
}

@test "one requirement may have two independently authenticated APPROVED reviews" {
    prepare_same_requirement_review_inventory APPROVED || return 1
    run_test_framework_json
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'"decision":"MET"'* ]]
}

@test "signed review inventory rejects an omitted second OPEN review" {
    prepare_same_requirement_review_inventory OPEN || return 1
    yq -i 'del(.originating_review_inventory[1])' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_inventory_pair_missing:review-0002:req-0001"* ]]
}

@test "present second OPEN review blocks closure even beside an APPROVED review" {
    prepare_same_requirement_review_inventory OPEN || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0001"* ]]
}

@test "present second CHANGES_REQUESTED review blocks closure even beside an APPROVED review" {
    prepare_same_requirement_review_inventory CHANGES_REQUESTED || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0001"* ]]
}

@test "signed review inventory rejects a duplicate review identity" {
    prepare_same_requirement_review_inventory APPROVED || return 1
    yq -i '.originating_review_inventory += [.originating_review_inventory[1]]' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_id_duplicate:review-0002"* ]]
}

@test "signed review inventory rejects an extra review pair" {
    prepare_same_requirement_review_inventory APPROVED || return 1
    yq -i '.originating_review_inventory += [.originating_review_inventory[1]] |
        .originating_review_inventory[2].review_id = "review-0003"' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_inventory_pair_extra:review-0003:req-0001"* ]]
}

@test "signed review inventory manifest signature is independently verified" {
    yq -i '.originating_review_inventory_manifest.authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$REVIEW"
    run_validator_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_inventory_manifest_signature_invalid"* ]]
}

@test "every same-requirement review remains independently authenticated" {
    prepare_same_requirement_review_inventory APPROVED || return 1
    yq -i '.originating_review_inventory[1].review_ref = "review-system/reviews/tampered"' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_digest_mismatch:review-0002"* ]]
}

@test "two-requirement epic cannot close with its second originating review missing" {
    prepare_two_requirement_fixture || return 1
    yq -i 'del(.originating_review_inventory[1])' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_inventory_pair_missing:review-0002:req-0002"* ]]
}

@test "two-requirement epic closes when its exact signed review inventory is APPROVED" {
    prepare_two_requirement_fixture APPROVED || return 1
    run_test_framework_json
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'"decision":"MET"'* ]]
}

@test "two-requirement epic cannot close with its second originating review OPEN" {
    prepare_two_requirement_fixture OPEN || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0002"* ]]
}

@test "two-requirement epic cannot close with its second originating review CHANGES_REQUESTED" {
    prepare_two_requirement_fixture CHANGES_REQUESTED || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0002"* ]]
}

@test "every originating review inventory record is authenticated" {
    prepare_two_requirement_fixture || return 1
    yq -i '.originating_review_inventory[1].review_ref = "review-system/reviews/tampered"' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_digest_mismatch:review-0002"* ]]
}

@test "originating review inventory rejects requirements outside the exact set" {
    prepare_two_requirement_fixture || return 1
    yq -i '.originating_review_inventory += [.originating_review_inventory[1]] |
        .originating_review_inventory[2].requirement_id = "req-9999" |
        .originating_review_inventory[2].review_id = "review-9999"' "$REVIEW"
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"originating_review_inventory_pair_extra:review-9999:req-9999"* ]]
}

@test "a rejected child disposition cannot produce a MET delivery decision" {
    yq -i '.requirements.req-0001.acceptance.disposition = "rejected"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.status = "rejected"' "$RECEIPT"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["epic_status"] == "NOT_MET" and "child_disposition_not_met:req-0001" in d["findings"]' "$output"
}

@test "receipt task and requirement-set parent links are exact" {
    yq -i '.parent_links += [{"relation":"task","id":"task:web:9999"}]' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_link_set_mismatch:task"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    yq -i '.parent_links += [{"relation":"requirement_set","id":"requirement-set-9999"}]' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_link_set_mismatch:requirement_set"* ]]
}

@test "authored epic status is rejected instead of drifting from computed child state" {
    yq -i '.parent_links[0].status = "MET"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:receipt"* ]]
}

@test "supersession cycles are NOT_MET" {
    yq -i '.source_remarks[0].requirement_ids += ["req-0002"] |
        .requirements.req-0002 = .requirements.req-0001 |
        .requirements.req-0001.acceptance.disposition = "superseded" |
        .requirements.req-0001.acceptance.superseded_by = "req-0002" |
        .requirements.req-0002.acceptance.disposition = "superseded" |
        .requirements.req-0002.acceptance.superseded_by = "req-0001"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"cycle:req-0001"* ]]
}

@test "duplicate YAML IDs fail closed instead of being overwritten" {
    printf '%s\n' '  req-0001:' '    source_ids: [source-0001]' '    atomic_statement: duplicate' >> "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"duplicate_id:req-0001"* ]]
}

@test "dangling requirement references are NOT_MET" {
    yq -i '.source_remarks[0].requirement_ids = ["req-9999"]' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"dangling_requirement_ref:source-0001:req-9999"* ]]
}

@test "applicable live evidence needs the exact eight-cell RU EN matrix" {
    yq -i 'del(.requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7])' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:receipt"* || "$output" == *"painted_matrix_incomplete:req-0001"* ]]
}

@test "JSON output is deterministic and machine-readable" {
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    local first="$output"
    [ "$status" -eq 0 ] || return 1
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    [ "$status" -eq 0 ] \
        && [ "$output" = "$first" ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["decision"] == "MET" and d["findings"] == []' "$output"
}

@test "usage errors and missing canonical artifacts exit 2" {
    run "$SCRIPT" --root "$ROOT" --task bad --stage qa --format text
    [ "$status" -eq 2 ] || return 1
    rm "$RECEIPT"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format text
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"missing_artifact"* ]]
}

@test "Tier-2 atomic analysis structurally retains Tier-1 provenance and applicability" {
    yq -i '.requirements.req-0001.acceptance.applicability.locales = ["en"]' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"tier1_scope_weakened:req-0001:locales"* ]]
}

@test "production wording cannot disguise a tool-only visitor acceptance criterion" {
    yq -i '.requirements.req-0001.acceptance.production_assertion.product = "other-product"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion_identity_mismatch:req-0001:product"* ]]
}

@test "remote branch revisions are mutable and not pinned" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].revision = "origin/main"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.skills[0].revision = "origin/main"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"knowledge_revision_unpinned:req-0001:skills"* ]]
}

@test "visitor requirements cannot declare the painted matrix not applicable" {
    yq -i '.requirements.req-0001.acceptance.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.applicability.not_applicable_reason = "Claimed not applicable."' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.not_applicable_reason = "Claimed not applicable." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "Claimed not applicable." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = []' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"visitor_matrix_not_applicable:req-0001"* ]]
}

@test "requirement and receipt matrix applicability must agree" {
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.not_applicable_reason = "Contradictory receipt applicability." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "Contradictory receipt applicability." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = []' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"applicability_mismatch:req-0001"* ]]
}

@test "enabling-only delivery cannot close a user-facing parent" {
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = [] |
        .requirements.req-0001.coverage_chain.live_evidence.visitor_visible = false |
        .requirements.req-0001.coverage_chain.live_evidence.observation_kind = "NON_VISITOR_CONTROL" |
        .requirements.req-0001.coverage_chain.live_evidence.surface_class = "NON_VISITOR" |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.not_applicable_reason = "Enabling evidence only." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "Enabling evidence only." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = []' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"user_facing_parent_enabling_only:req-0001"* ]]
}

@test "semantic NOT_MET forces computed epic status NOT_MET" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "2026-01-02T10:00:01Z"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.roles[0].selected_at = "2026-01-02T10:00:01Z"' "$RECEIPT"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["epic_status"] == "NOT_MET"' "$output"
}

@test "implementation delta task is bound to selected implementation task" {
    yq -i '.requirements.req-0001.acceptance.implementation.task_id = "task:web:9999"' "$REQUIREMENTS"
    yq -i '(.parent_links[] | select(.relation == "task").id) = "task:web:9999"' "$RECEIPT"
    yq -i '(.parent_links[] | select(.relation == "task").id) = "task:web:9999"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"implementation_task_mismatch:req-0001"* ]]
}

@test "selected knowledge IDs are unique across knowledge kinds" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].id = "frontend-reviewer"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.skills[0].id = "frontend-reviewer"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"duplicate_knowledge_id:req-0001:frontend-reviewer"* ]]
}

@test "implementation delta IDs are unique" {
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.enabling_changes += [.requirements.req-0001.coverage_chain.implementation_delta.enabling_changes[0]] |
        .requirements.req-0001.coverage_chain.implementation_delta.enabling_count = 2' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"duplicate_delta_id:req-0001:delta-e-0001"* ]]
}

@test "painted matrix evidence cannot be recorded after customer disposition" {
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.painted_matrix[0].observed_at = "2026-01-03T13:00:01Z"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"painted_matrix_timestamp_mismatch:req-0001"* ]]
}

@test "RED evidence must precede GREEN evidence" {
    yq -i '.requirements.req-0001.coverage_chain.red_green.red.observed_at = "2026-01-02T11:16:00Z"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"red_green_timestamp_mismatch:req-0001"* ]]
}

@test "implementation starts no later than RED evidence" {
    yq -i '.requirements.req-0001.acceptance.implementation.started_at = "2026-01-02T10:06:00Z"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"implementation_red_timestamp_mismatch:req-0001"* ]]
}

@test "live production identity exactly equals accepted product identity" {
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.product = "other-product"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"live_product_mismatch:req-0001"* ]]
}

@test "merged revision must be one of the accepted implementation revisions" {
    yq -i '.requirements.req-0001.acceptance.implementation.code_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" |
        .requirements.req-0001.acceptance.implementation.content_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"accepted_revision_mismatch:req-0001"* ]]
}

@test "customer disposition must agree with the accepted requirement disposition" {
    yq -i '.requirements.req-0001.acceptance.disposition = "pending"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"customer_disposition_mismatch:req-0001"* ]]
}

@test "intermediate symlink escapes from root fail closed" {
    local outside="${BATS_TEST_TMPDIR}/outside"
    mkdir -p "$outside"
    mv "$REQUIREMENTS" "${outside}/${TASK_ID}-customer-requirements.yaml"
    rmdir "${ROOT}/datarim/tasks"
    ln -s "$outside" "${ROOT}/datarim/tasks"
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and "path_escape:requirements" in d["findings"]' "$output"
}

@test "exported realpath function cannot bypass intermediate symlink confinement" {
    local outside="${BATS_TEST_TMPDIR}/outside-function"
    mkdir -p "$outside"
    mv "$REQUIREMENTS" "${outside}/${TASK_ID}-customer-requirements.yaml"
    rmdir "${ROOT}/datarim/tasks"
    ln -s "$outside" "${ROOT}/datarim/tasks"
    realpath() {
        printf '%s\n' "${!#}"
    }
    export -f realpath
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    unset -f realpath
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and "path_escape:requirements" in d["findings"]' "$output"
}

@test "PATH realpath shim cannot bypass intermediate symlink confinement" {
    local outside="${BATS_TEST_TMPDIR}/outside-path"
    local shim_dir="${BATS_TEST_TMPDIR}/hostile-path"
    mkdir -p "$outside" "$shim_dir"
    mv "$REQUIREMENTS" "${outside}/${TASK_ID}-customer-requirements.yaml"
    rmdir "${ROOT}/datarim/tasks"
    ln -s "$outside" "${ROOT}/datarim/tasks"
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\\n'\'' "${!#}"' >"${shim_dir}/realpath"
    chmod +x "${shim_dir}/realpath"
    run env PATH="${shim_dir}:${PATH}" CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and "path_escape:requirements" in d["findings"]' "$output"
}

@test "ambient framework-root override cannot replace bundled schemas" {
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="${BATS_TEST_TMPDIR}/hostile-framework" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    if [ "$status" -ne 0 ] \
        || ! "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET"' "$output"; then
        printf 'framework_root_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
}

@test "dependency failure is deterministic machine-readable JSON" {
    local dependency_free_venv="${BATS_TEST_TMPDIR}/python-without-dependencies"
    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        /usr/bin/env -i LC_ALL=C DEVELOPER_DIR=/Library/Developer/CommandLineTools \
            "${CUSTOMER_TEST_PYTHON_RUNTIME:?missing CUSTOMER_TEST_PYTHON_RUNTIME}" \
            -m venv "$dependency_free_venv" || return 1
        /bin/ln -sf /usr/bin/python3 "${dependency_free_venv}/bin/python" || return 1
    else
        "$PYTHON" -m venv "$dependency_free_venv" || return 1
    fi
    run env CUSTOMER_DELIVERY_PYTHON="${dependency_free_venv}/bin/python" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    if [ "$status" -ne 2 ] \
        || ! "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["task"] == "WEB-0001" and d["stage"] == "compliance" and d["status"] == "ERROR" and d["findings"] == ["missing_python_dependencies"]' "$output"; then
        printf 'dependency_failure_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
}

@test "trusted interpreter metadata contract covers Linux and macOS stat semantics" {
    grep -q '# PORTABLE_TRUST:linux_gnu_stat' "$SCRIPT" \
        && grep -q '# PORTABLE_TRUST:darwin_bsd_stat' "$SCRIPT" \
        && grep -q '/usr/bin/python3' "$SCRIPT" \
        && ! grep -q 'python_anchor in /usr/bin/python3 /usr/local/bin/python3' "$SCRIPT"
}

@test "forged writable trusted runtime metadata fails closed" {
    build_test_framework forged-writable-runtime || return 1
    "$PYTHON" - "$TEST_SCRIPT" <<'PY' || return 1
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = '''IFS='|' read -r trusted_runtime_device trusted_runtime_inode trusted_runtime_uid \\
    trusted_runtime_mode trusted_runtime_type <<<"$trusted_runtime_metadata"
'''
if source.count(needle) != 1:
    raise SystemExit("TRUSTED_RUNTIME_METADATA_FIXTURE_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(
    needle,
    needle + "trusted_runtime_uid=1000\ntrusted_runtime_mode=777\n",
)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    chmod +x "$TEST_SCRIPT"

    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["untrusted_python_runtime"]' "$output"
}

@test "ambient Python and Apple developer routing cannot redirect the trusted runtime" {
    mkdir -p "${BATS_TEST_TMPDIR}/hostile-python-home"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        PYTHONHOME="${BATS_TEST_TMPDIR}/hostile-python-home" \
        PYTHONPATH="${BATS_TEST_TMPDIR}/hostile-python-home" \
        PYTHONEXECUTABLE="${BATS_TEST_TMPDIR}/hostile-python" \
        __PYVENV_LAUNCHER__="${BATS_TEST_TMPDIR}/hostile-launcher" \
        DEVELOPER_DIR="${BATS_TEST_TMPDIR}/hostile-developer" \
        TOOLCHAINS='hostile.toolchain' \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    if [ "$status" -ne 0 ] \
        || ! "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET"' "$output"; then
        printf 'routing_scrub_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
}

@test "current directory cannot shadow trusted Python dependencies" {
    local hostile_cwd="${BATS_TEST_TMPDIR}/hostile-python-cwd"
    mkdir -p "$hostile_cwd"
    printf '%s\n' 'raise RuntimeError("HOSTILE_CWD_JSONSCHEMA_IMPORTED")' >"${hostile_cwd}/jsonschema.py"
    printf '%s\n' 'raise RuntimeError("HOSTILE_CWD_BASE64_IMPORTED")' >"${hostile_cwd}/base64.py"
    run bash -c 'cd "$1" && env CUSTOMER_DELIVERY_PYTHON="$2" "$3" --root "$4" --task "$5" --stage qa --format json' \
        bash "$hostile_cwd" "$VALIDATOR_PYTHON" "$SCRIPT" "$ROOT" "$TASK_ID"
    if [ "$status" -ne 0 ] \
        || ! "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET"' "$output" \
        || [[ "$output" == *HOSTILE_CWD_JSONSCHEMA_IMPORTED* ]]; then
        printf 'cwd_isolation_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
}

@test "Darwin trusted site bootstrap rejects executable pth authority" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path hostile_pth result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    hostile_pth="${site_path}/customer_delivery_hostile.pth"
    SITE_CLEANUP_PATH="$hostile_pth"
    printf '%s\n' 'raise RuntimeError("HOSTILE_PTH_EXECUTED")' >"$hostile_pth"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    /bin/rm -f -- "$hostile_pth"
    clear_site_cleanup
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_runtime"]' "$output_copy" \
        && [[ "$output_copy" != *HOSTILE_PTH_EXECUTED* ]]
}

@test "Darwin trusted site bootstrap rejects symlinked dependency content" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path hostile_link result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    hostile_link="${site_path}/customer_delivery_outside_link"
    SITE_CLEANUP_PATH="$hostile_link"
    /bin/ln -s "$BATS_TEST_TMPDIR" "$hostile_link"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    /bin/rm -f -- "$hostile_link"
    clear_site_cleanup
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "Darwin trusted site bootstrap rejects regular-file dist-info forgery" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path dist_info backup result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    dist_info="${site_path}/jsonschema-4.23.0.dist-info"
    backup="${BATS_TEST_TMPDIR}/jsonschema-dist-info"
    /bin/mv "$dist_info" "$backup" || return 1
    SITE_CLEANUP_PATH="$dist_info"
    SITE_CLEANUP_BACKUP="$backup"
    printf '%s\n' 'forged regular dist-info entry' >"$dist_info"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    /bin/rm -f -- "$dist_info"
    /bin/mv -- "$backup" "$dist_info"
    clear_site_cleanup
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "Darwin trusted site bootstrap rejects symlinked dist-info" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path dist_info backup result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    dist_info="${site_path}/jsonschema-4.23.0.dist-info"
    backup="${BATS_TEST_TMPDIR}/jsonschema-dist-info-symlink"
    /bin/mv "$dist_info" "$backup" || return 1
    SITE_CLEANUP_PATH="$dist_info"
    SITE_CLEANUP_BACKUP="$backup"
    /bin/ln -s "$backup" "$dist_info"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    /bin/unlink -- "$dist_info"
    /bin/mv -- "$backup" "$dist_info"
    clear_site_cleanup
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "Darwin trusted site bootstrap authenticates dist-info metadata" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path metadata backup result output_copy line
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    metadata="${site_path}/jsonschema-4.23.0.dist-info/METADATA"
    backup="${BATS_TEST_TMPDIR}/jsonschema-METADATA"
    /bin/mv "$metadata" "$backup" || return 1
    SITE_CLEANUP_PATH="$metadata"
    SITE_CLEANUP_BACKUP="$backup"
    : >"$metadata"
    while IFS= read -r line; do
        if [[ "$line" == 'Version: '* ]]; then
            printf '%s\n' 'Version: 0.0.0-forged'
        else
            printf '%s\n' "$line"
        fi
    done <"$backup" >"$metadata"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    /bin/rm -f -- "$metadata"
    /bin/mv -- "$backup" "$metadata"
    clear_site_cleanup
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "Darwin trusted site bootstrap rejects METADATA boundary forgeries" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path metadata backup kind result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    metadata="${site_path}/jsonschema-4.23.0.dist-info/METADATA"
    for kind in symlink directory fifo oversized wrong_name duplicate_name duplicate_version; do
        backup="${BATS_TEST_TMPDIR}/jsonschema-METADATA-${kind}"
        /bin/mv "$metadata" "$backup" || return 1
        SITE_CLEANUP_PATH="$metadata"
        SITE_CLEANUP_BACKUP="$backup"
        case "$kind" in
            symlink)
                /bin/ln -s "$backup" "$metadata" || return 1
                ;;
            directory)
                /bin/mkdir "$metadata" || return 1
                ;;
            fifo)
                "$PYTHON" -c 'import os,sys; os.mkfifo(sys.argv[1])' "$metadata" || return 1
                ;;
            oversized)
                "$PYTHON" -c 'import sys; open(sys.argv[1], "wb").write(b"Name: jsonschema\nVersion: 4.23.0\n\n" + b"x" * 1048577)' "$metadata" || return 1
                ;;
            wrong_name)
                /usr/bin/sed 's/^Name: jsonschema$/Name: forged-project/' "$backup" >"$metadata"
                ;;
            duplicate_name)
                { printf '%s\n' 'Name: jsonschema'; /bin/cat "$backup"; } >"$metadata"
                ;;
            duplicate_version)
                { printf '%s\n' 'Version: 4.23.0'; /bin/cat "$backup"; } >"$metadata"
                ;;
        esac
        if [[ "$kind" == fifo ]]; then
            run_validator_json_bounded "$SCRIPT" 2
        else
            run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
                "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
        fi
        result="$status"
        output_copy="$output"
        if [[ -L "$metadata" ]]; then
            /bin/unlink -- "$metadata"
        elif [[ -d "$metadata" ]]; then
            /bin/rmdir -- "$metadata"
        else
            /bin/mv -- "$metadata" "${BATS_TEST_TMPDIR}/forged-METADATA-${kind}"
        fi
        /bin/mv -- "$backup" "$metadata"
        clear_site_cleanup
        assert_darwin_dependency_site_integrity || return 1
        if [ "$result" -ne 2 ] \
            || ! "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
            || [[ "$output_copy" == *Traceback* ]]; then
            printf 'METADATA boundary kind=%s status=%s output=%s\n' "$kind" "$result" "$output_copy"
            return 1
        fi
    done
}

@test "Darwin trusted site bootstrap detects METADATA identity change after read" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path metadata original replacement result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    metadata="${site_path}/jsonschema-4.23.0.dist-info/METADATA"
    original="${site_path}/jsonschema-4.23.0.dist-info/METADATA.original-a2"
    replacement="${BATS_TEST_TMPDIR}/jsonschema-METADATA-replacement"
    build_test_framework metadata-identity-change || return 1
    "$PYTHON" - "$TEST_SCRIPT" <<'PY' || return 1
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "            metadata_after = os.fstat(metadata_fd)\n"
new = '''            os.rename(
                "METADATA", "METADATA.original-a2",
                src_dir_fd=dist_fd, dst_dir_fd=dist_fd,
            )
            replacement_fd = os.open(
                "METADATA", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                0o600, dir_fd=dist_fd,
            )
            try:
                os.write(replacement_fd, b"Name: jsonschema\\nVersion: 4.23.0\\n\\n")
            finally:
                os.close(replacement_fd)
            metadata_after = os.fstat(metadata_fd)
'''
if source.count(old) != 1:
    raise SystemExit("METADATA_IDENTITY_ATTACK_SEAM_MISSING_OR_AMBIGUOUS")
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    SITE_IDENTITY_CLEANUP_SITE="$site_path"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$TEST_SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    cleanup_metadata_identity_fixture || return 1
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "Darwin trusted site bootstrap detects METADATA replacement before open" {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only trusted site boundary'
    local site_path result output_copy
    site_path="${CUSTOMER_TEST_PYTHON_SITE:?missing CUSTOMER_TEST_PYTHON_SITE}"
    build_test_framework metadata-preopen-identity-change || return 1
    "$PYTHON" - "$TEST_SCRIPT" <<'PY' || return 1
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = '''        metadata_entry = os.stat("METADATA", follow_symlinks=False)
        if (
'''
new = '''        metadata_entry = os.stat("METADATA", follow_symlinks=False)
        if distribution == "jsonschema":
            os.rename(
                "METADATA", "METADATA.original-a2",
                src_dir_fd=dist_fd, dst_dir_fd=dist_fd,
            )
            original_fd = os.open(
                "METADATA.original-a2", os.O_RDONLY | os.O_CLOEXEC,
                dir_fd=dist_fd,
            )
            try:
                original_bytes = os.read(original_fd, metadata_entry.st_size)
            finally:
                os.close(original_fd)
            replacement_fd = os.open(
                "METADATA", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                0o600, dir_fd=dist_fd,
            )
            try:
                os.write(replacement_fd, original_bytes)
            finally:
                os.close(replacement_fd)
        if (
'''
if source.count(old) != 1:
    raise SystemExit("METADATA_PREOPEN_ATTACK_SEAM_MISSING_OR_AMBIGUOUS")
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    SITE_IDENTITY_CLEANUP_SITE="$site_path"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$TEST_SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    result="$status"
    output_copy="$output"
    cleanup_metadata_identity_fixture || return 1
    assert_darwin_dependency_site_integrity || return 1
    [ "$result" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["untrusted_python_dependencies"]' "$output_copy" \
        && [[ "$output_copy" != *Traceback* ]]
}

@test "canonical inputs are parsed from confined stable descriptor snapshots" {
    grep -q '# SECURITY_RULE:input_snapshot_openat' "$SCRIPT" \
        && grep -q '# SECURITY_RULE:input_snapshot_identity' "$SCRIPT"
}

@test "pre-open path replacement cannot redirect a canonical snapshot" {
    local outside="$BATS_TEST_TMPDIR/outside-requirements.yaml"
    cp "$REQUIREMENTS" "$outside"
    build_test_framework preopen-replacement || return 1
    "$PYTHON" - "$TEST_SCRIPT" "$outside" <<'PY' || return 1
import sys
path, outside = sys.argv[1:]
source = open(path, encoding="utf-8").read()
old = '''documents = {}
schemas = {}
for name in ("requirements", "receipt", "review"):
    try:
'''
new = f'''documents = {{}}
schemas = {{}}
for name in ("requirements", "receipt", "review"):
    try:
        if name == "requirements":
            os.replace(DOCUMENT_PATHS[name], DOCUMENT_PATHS[name] + \".preopen\")
            os.symlink({outside!r}, DOCUMENT_PATHS[name])
'''
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_unavailable:requirements"]' "$output"
}

@test "repository binding refuses a symlink swapped into the canonical gitdir" {
    local displaced_gitdir="${BATS_TEST_TMPDIR}/displaced-gitdir"
    mv "${ROOT}/.git" "$displaced_gitdir"
    ln -s "$displaced_gitdir" "${ROOT}/.git"
    build_test_framework repository-symlink-swap || return 1
    "$PYTHON" - "$TEST_SCRIPT" "$displaced_gitdir" <<'PY' || return 1
import sys

path, displaced_gitdir = sys.argv[1:]
source = open(path, encoding="utf-8").read()
old = """            gitdir_fd = os.dup(dotgit_fd)
        except NotADirectoryError:"""
new = f"""            gitdir_fd = os.dup(dotgit_fd)
            if os.path.islink(os.path.join(ROOT, ".git")):
                os.unlink(os.path.join(ROOT, ".git"))
                os.rename({displaced_gitdir!r}, os.path.join(ROOT, ".git"))
        except NotADirectoryError:"""
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["findings"] == ["source_history_unavailable"]' "$output"
}

@test "post-open identity change invalidates the captured snapshot" {
    build_test_framework postopen-identity || return 1
    replace_test_script_literal \
        '        before = os.fstat(file_descriptor)' \
        $'        before = os.fstat(file_descriptor)\n        if label == "requirements":\n            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns + 1000000000))' || return 1
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_identity_changed:requirements"]' "$output"
}

@test "oversized canonical input is rejected before YAML parsing" {
    "$PYTHON" - "$REQUIREMENTS" <<'PY' || return 1
import os
import sys

path = sys.argv[1]
limit = 8 * 1024 * 1024
with open(path, "ab") as handle:
    handle.write(b" " * (limit + 1 - os.path.getsize(path)))
PY
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_resource_limit:bytes:requirements"]' "$output"
}

@test "requirement cardinality is bounded before schema validation" {
    "$PYTHON" - "$REQUIREMENTS" <<'PY' || return 1
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
document["requirements"] = {f"req-{index:04d}": {} for index in range(1, 514)}
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, sort_keys=False)
PY
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_resource_limit:requirements"]' "$output"
}

@test "source record cardinality is bounded before schema validation" {
    "$PYTHON" - "$REQUIREMENTS" <<'PY' || return 1
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
document["source_remarks"] = [{"source_id": f"source-{index:04d}"} for index in range(1, 1026)]
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, sort_keys=False)
PY
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_resource_limit:records"]' "$output"
}

@test "evidence cardinality is bounded before schema validation" {
    "$PYTHON" - "$RECEIPT" <<'PY' || return 1
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
document["requirements"]["req-0001"]["coverage_chain"]["requirement"]["source_quote_digests"] = [
    {} for _ in range(4097)
]
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, sort_keys=False)
PY
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_resource_limit:evidence"]' "$output"
}

@test "signature cardinality is bounded before schema validation" {
    "$PYTHON" - "$REVIEW" <<'PY' || return 1
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
document["signature_flood"] = [{"signature": "ed25519:x"} for _ in range(1025)]
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, sort_keys=False)
PY
    run_validator_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["input_resource_limit:signatures"]' "$output"
}

@test "all validation subprocesses share one total deadline" {
    local shim="${BATS_TEST_TMPDIR}/slow-openssl"
    local real_openssl start end elapsed
    real_openssl="$(command -v openssl)" || return 1
    printf '%s\n' \
        '#!/bin/bash' \
        'if [ "${1:-}" != version ]; then sleep 0.35; fi' \
        "exec \"${real_openssl}\" \"\$@\"" >"$shim"
    chmod 0755 "$shim"
    build_test_framework total-validation-deadline || return 1
    replace_test_script_literal \
        'VALIDATION_TOTAL_TIMEOUT_SECONDS = 20' \
        'VALIDATION_TOTAL_TIMEOUT_SECONDS = 1' || return 1
    rebind_test_openssl "$shim" || return 1
    start="$($PYTHON -c 'import time; print(time.perf_counter())')"
    run_test_framework_json
    end="$($PYTHON -c 'import time; print(time.perf_counter())')"
    elapsed="$($PYTHON -c 'import sys; print(float(sys.argv[2])-float(sys.argv[1]))' "$start" "$end")"
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["validation_resource_limit:deadline"]' "$output" \
        && "$PYTHON" -c 'import sys; assert float(sys.argv[1]) < 2.0' "$elapsed" \
        || { printf 'deadline_output=%s elapsed=%s\n' "$output" "$elapsed"; return 1; }
}

@test "OpenSSL version output is bounded before allocation" {
    local shim="${BATS_TEST_TMPDIR}/noisy-openssl"
    "$PYTHON" - "$shim" <<'PY' || return 1
import os
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("#!/bin/bash\n")
    handle.write("if [ \"${1:-}\" = version ]; then head -c 1048576 /dev/zero | tr '\\0' x; exit 0; fi\n")
    handle.write("exit 1\n")
os.chmod(sys.argv[1], 0o755)
PY
    build_test_framework crypto-output-budget || return 1
    rebind_test_openssl "$shim" || return 1
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["validation_resource_limit:subprocess_output"]' "$output" \
        || { printf 'crypto_output=%s\n' "$output"; return 1; }
}

@test "OpenSSL deadline terminates stubborn descendant pipe holders" {
    local shim="${BATS_TEST_TMPDIR}/stubborn-openssl"
    local pid_file="${BATS_TEST_TMPDIR}/stubborn-openssl.pid"
    local descendant_pid attempt
    "$PYTHON" - "$shim" "$pid_file" <<'PY' || return 1
import os
import sys

shim, pid_file = sys.argv[1:]
with open(shim, "w", encoding="utf-8") as handle:
    handle.write("#!/bin/bash\n")
    handle.write('if [ "${1:-}" = version ]; then\n')
    handle.write("  (trap '' TERM; sleep 30) &\n")
    handle.write(f"  printf '%s\\n' \"$!\" > {pid_file!r}\n")
    handle.write("  exit 0\n")
    handle.write("fi\n")
    handle.write("exit 1\n")
os.chmod(shim, 0o755)
PY
    build_test_framework stubborn-crypto-descendant || return 1
    replace_test_script_literal \
        'VALIDATION_TOTAL_TIMEOUT_SECONDS = 20' \
        'VALIDATION_TOTAL_TIMEOUT_SECONDS = 1' || return 1
    rebind_test_openssl "$shim" || return 1
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["validation_resource_limit:deadline"]' "$output" \
        || { printf 'stubborn_crypto_output=%s\n' "$output"; return 1; }
    descendant_pid="$(<"$pid_file")"
    for attempt in {1..10}; do
        kill -0 "$descendant_pid" 2>/dev/null || return 0
        sleep 0.05
    done
    kill -KILL "$descendant_pid" 2>/dev/null || true
    printf 'stubborn_crypto_descendant_survived=%s\n' "$descendant_pid"
    return 1
}

@test "non-Python executable cannot satisfy the interpreter pin" {
    run env CUSTOMER_DELIVERY_PYTHON=/bin/true \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["untrusted_python_runtime"]' "$output"
}

@test "interpreter wrapper cannot impersonate the pinned Python runtime" {
    local fake_python="${BATS_TEST_TMPDIR}/fake-python"
    printf '%s\n' '#!/bin/sh' "exec \"${PYTHON}\" \"\$@\"" > "$fake_python"
    chmod +x "$fake_python"
    run env CUSTOMER_DELIVERY_PYTHON="$fake_python" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["untrusted_python_runtime"]' "$output"
}

@test "perfect probe dependency and MET forgery cannot impersonate a trusted CPython inode" {
    local fake_python="${BATS_TEST_TMPDIR}/perfect-fake-python"
    "$PYTHON" - "$fake_python" <<'PY' || return 1
import os
import sys

path = sys.argv[1]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(r'''#!/usr/bin/env bash
if [[ "${3:-}" == *CUSTOMER_DELIVERY_DEPENDENCIES_OK* ]]; then
    printf '%s\n' CUSTOMER_DELIVERY_DEPENDENCIES_OK
    exit 0
fi
if [[ "${1:-}" == -I && "${2:-}" == -c ]]; then
    identity="$(stat -Lc '%d|%i' -- "$0")"
    printf '%s|cpython|3|12\n' "$identity"
    exit 0
fi
printf '%s\n' '{"decision":"MET","epic_status":"MET","findings":[],"stage":"qa","status":"MET","task":"WEB-0001"}'
exit 0
''')
os.chmod(path, 0o700)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$fake_python" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["untrusted_python_runtime"]' "$output"
}

@test "empty validator response cannot be accepted as MET" {
    build_test_framework empty-validator-response || return 1
    replace_test_script_literal \
        'emit("MET", 0, epic_status)' \
        'sys.exit(0)  # MUTATED:empty_validator_response' || return 1
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["invalid_validator_response"]' "$output"
}

@test "hostile malformed YAML returns JSON without traceback" {
    printf '%s\n' '? [unhashable, key]' ': value' > "$REQUIREMENTS"
    run_validator_json
    [ "$status" -eq 1 ] \
        && [[ "$output" != *"Traceback"* ]] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["task"] == "WEB-0001" and d["stage"] == "qa" and d["status"] == "NOT_MET" and d["findings"]' "$output"
}

@test "semantic invariant registries are exact and cannot lose a registered rule" {
    build_test_framework invariant-registry || return 1
    yq -i 'del(."x-datarim-semantic-invariants".invariant_ids[0])' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"invariant_registry_mismatch:requirements"* ]]
}

@test "semantic implementation dispatch cannot lose a registered rule" {
    build_test_framework invariant-dispatch || return 1
    "$PYTHON" - "$TEST_SCRIPT" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = "source-id-unique assertion-id-unique"
if source.count(needle) != 1:
    raise SystemExit("implementation registry seam missing or ambiguous")
source = source.replace(needle, "assertion-id-unique")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"invariant_unimplemented:requirements:source-id-unique"* ]]
}

@test "trusted registry entry order is authenticated before key lookup" {
    build_test_framework registry-order || return 1
    yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries |= reverse' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"trust_registry_entry_order"* ]]
}

@test "trusted registry canonical digest is verified before key lookup" {
    build_test_framework registry-digest || return 1
    yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0].authority_id = "authority-attacker-0001"' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"trust_registry_digest_mismatch"* ]]
}

@test "trusted registry signature is verified against the pinned root" {
    build_test_framework registry-signature || return 1
    yq -i '."x-datarim-signature-contract".key_resolution.bundled_registry.registry_signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"trust_registry_signature_invalid"* ]]
}

@test "trusted registry duplicates conflicts and invalid validity windows fail closed" {
    local name expression expected
    while IFS='|' read -r name expression expected; do
        build_test_framework "$name" || return 1
        yq -i "$expression" "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
        run_test_framework_json
        [ "$status" -eq 2 ] \
            && [[ "$output" == *"$expected"* ]] \
            || return 1
    done <<'CASES'
registry-duplicate|."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0]]|trust_registry_duplicate_key:key-customer-0001
registry-conflict|."x-datarim-signature-contract".key_resolution.bundled_registry.entries += [(."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0] * {"authority_id":"authority-attacker-0001"})]|trust_registry_conflicting_key:key-customer-0001
registry-window|."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0].valid_until = "2026-01-01T00:00:00Z"|trust_registry_invalid_window:key-customer-0001
CASES
}

@test "trusted registry locator owner anchor structure and receipt reference are pinned" {
    local name expression expected
    while IFS='|' read -r name expression expected; do
        build_test_framework "$name" || return 1
        yq -i "$expression" "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
        run_test_framework_json
        [ "$status" -eq 2 ] \
            && [[ "$output" == *"$expected"* ]] \
            || return 1
    done <<'CASES'
registry-locator|."x-datarim-signature-contract".key_resolution.registry_locator.resolution = "AMBIENT_ALLOWED"|trust_registry_locator_mismatch
registry-owner|."x-datarim-signature-contract".key_resolution.registry_owner.authority_id = "authority-attacker-0001"|trust_registry_owner_mismatch
registry-anchor|."x-datarim-signature-contract".key_resolution.registry_owner.trust_anchor.key_id = "key-attacker-0001"|trust_registry_anchor_mismatch
registry-structure|."x-datarim-signature-contract".key_resolution.bundled_registry.extra = true|trust_registry_structure
registry-ref|."x-datarim-signature-contract".key_resolution.registry_locator.resolution = "AMBIENT_ALLOWED"|trust_registry_locator_mismatch
CASES

    build_test_framework registry-ref || return 1
    yq -i '."x-datarim-trusted-authority-key-registry-ref".registry_id = "registry-attacker-0001"' \
        "${TEST_FRAMEWORK}/config/customer-delivery-receipt.schema.json"
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"receipt_trust_registry_ref_mismatch"* ]]
}

@test "authenticated leaf registry status and approval windows fail closed" {
    local name expression expected
    while IFS='|' read -r name expression expected; do
        build_test_framework "$name" || return 1
        authenticate_test_registry "$expression" || return 1
        run_test_framework_json
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"$expected"* ]] \
            || return 1
    done <<'CASES'
leaf-revoked|."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0].status = "REVOKED"|source_approval_key_not_active:source-0001
leaf-future|."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0].valid_from = "2026-02-01T00:00:00Z"|source_approval_key_not_yet_valid:source-0001
leaf-expired|."x-datarim-signature-contract".key_resolution.bundled_registry.entries[0].valid_until = "2026-01-02T09:01:00Z"|source_approval_key_expired:source-0001
CASES
}

@test "approval key identity role and existence are authorized before signature acceptance" {
    yq -i '.source_remarks[0].authority_approval.key_id = "key-unknown-0001"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_approval_key_unknown:source-0001:key-unknown-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].authority_approval.key_id = "key-operator-0001"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_approval_authority_mismatch:source-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].authority_approval.authority_role = "OPERATOR"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_approval_role_unauthorized:source-0001"* ]]
}

@test "missing OpenSSL 3 dependency is deterministic machine-readable JSON" {
    build_test_framework missing-openssl || return 1
    rebind_test_openssl '/definitely-missing/datarim-openssl' || return 1
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["missing_crypto_dependency:openssl3"]' "$output"
}

@test "ambient PATH OpenSSL shim cannot authenticate an invalid disposition signature" {
    local hostile_path="${BATS_TEST_TMPDIR}/hostile-openssl-path"
    local canary="${BATS_TEST_TMPDIR}/hostile-openssl-called"
    mkdir -p "$hostile_path"
    # The generated shim expands these variables when it executes.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf called > "$HOSTILE_OPENSSL_CANARY"' \
        'if [ "${1:-}" = version ]; then printf "OpenSSL 3.999 hostile\\n"; fi' \
        'exit 0' > "$hostile_path/openssl"
    chmod 0755 "$hostile_path/openssl"
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$RECEIPT"

    run env PATH="$hostile_path:$PATH" HOSTILE_OPENSSL_CANARY="$canary" \
        CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and "disposition_signature_invalid:req-0001" in d["findings"]' "$output" \
        && [ ! -e "$canary" ]
}

@test "source JCS digest and approval payload commitments are independently enforced" {
    yq -i '.source_remarks[0].verbatim_quote = "Coherently rewritten source." |
        .requirements.req-0001.acceptance.exact_source_quotes[0].verbatim_quote = "Coherently rewritten source."' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_digest_mismatch:source-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "tampered-source-approval"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_approval_payload_digest_mismatch:source-0001"* ]]
}

@test "source and assertion approval digests and assertion JCS are independently enforced" {
    yq -i '.source_remarks[0].authority_approval.approved_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_approval_digest_mismatch:source-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].tier1_assertions[0].assertion_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"assertion_digest_mismatch:assertion-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.approved_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"assertion_approval_digest_mismatch:assertion-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.evidence_ref = "tampered-assertion-approval"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"assertion_approval_payload_digest_mismatch:assertion-0001"* ]]
}

@test "source and assertion signatures use raw digest Ed25519 framing" {
    yq -i '.source_remarks[0].authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_signature_invalid:source-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"assertion_signature_invalid:assertion-0001"* ]]
}

@test "source tier role authorization and assertion authority identity are structural" {
    yq -i '.source_remarks[0].source_tier = "AUTHORIZED_RELAY_VERBATIM"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_tier_role_unauthorized:source-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.key_id = "key-operator-0001"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"assertion_source_key_mismatch:assertion-0001"* ]]
}

@test "terminal disposition commits the full pre-disposition coverage chain" {
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.evidence_ref = "artifacts/live/tampered.json"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"coverage_chain_digest_mismatch:req-0001"* ]]
}

@test "terminal disposition identities digests approval and signature are bound" {
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.receipt_id = "receipt-9999"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"disposition_receipt_id_mismatch:req-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"disposition_signature_invalid:req-0001"* ]]
}

@test "terminal disposition canonical and approval payload digests are independently bound" {
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.note = "tampered note"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"disposition_digest_mismatch:req-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.authority_approval.approved_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"disposition_approval_digest_mismatch:req-0001"* ]] \
        || return 1

    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.authority_approval.evidence_ref = "tampered-disposition-approval"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"disposition_approval_payload_digest_mismatch:req-0001"* ]]
}

@test "pending customer disposition is unsigned and cannot close coverage" {
    yq -i '.requirements.req-0001.coverage_status = "NOT_MET" |
        .requirements.req-0001.missing_edges = ["customer_disposition"] |
        .requirements.req-0001.coverage_chain.customer_disposition = {
          "status":"pending",
          "recorded_at":"2026-01-03T13:00:00Z",
          "evidence_ref":"pending-customer-review-0001"
        }' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"missing_edge:req-0001:customer_disposition"* ]]
}

@test "source records are append-only against available Git history" {
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "authoritative root replacement after document snapshots cannot redirect source history" {
    local substitute="${BATS_TEST_TMPDIR}/root-swap-substitute"
    prepare_authenticated_prework_fixture \
        '.source_remarks[0].source_ref = "customer-interview-newly-signed"' \
        || return 1
    run_test_framework_json
    if [ "$status" -ne 1 ] \
        || [[ "$output" != *"source_history_prior_digest_deleted:"* ]]; then
        printf 'root_swap_baseline_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
    mkdir -p "$substitute/datarim/tasks"
    cp "$REQUIREMENTS" "$substitute/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    git -C "$substitute" init -q
    git -C "$substitute" config user.name test
    git -C "$substitute" config user.email test@example.invalid
    git -C "$substitute" add datarim
    git -C "$substitute" commit -q -m clean-substitute
    "$PYTHON" - "$TEST_SCRIPT" "$substitute" <<'PY' || return 1
import sys
path, substitute = sys.argv[1:]
source = open(path, encoding="utf-8").read()
old = "validate_requirements_contract()\nvalidate_source_history()\ncheck_supersession_cycles()"
new = f'''validate_requirements_contract()
os.rename(ROOT, ROOT + ".authoritative")
os.rename({substitute!r}, ROOT)
validate_source_history()
check_supersession_cycles()'''
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    run_test_framework_json
    if [ "$status" -ne 1 ] \
        || [[ "$output" != *"source_history_repository_identity_changed:root"* ]]; then
        printf 'root_swap_attack_status=%s output=%s\n' "$status" "$output"
        return 1
    fi
}

@test "authoritative gitdir replacement after document snapshots cannot redirect source history" {
    local substitute="${BATS_TEST_TMPDIR}/gitdir-swap-substitute"
    prepare_authenticated_prework_fixture \
        '.source_remarks[0].source_ref = "customer-interview-newly-signed"' \
        || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_digest_deleted:"* ]] \
        || return 1
    mkdir -p "$substitute/datarim/tasks"
    cp "$REQUIREMENTS" "$substitute/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    git -C "$substitute" init -q
    git -C "$substitute" config user.name test
    git -C "$substitute" config user.email test@example.invalid
    git -C "$substitute" add datarim
    git -C "$substitute" commit -q -m clean-substitute
    "$PYTHON" - "$TEST_SCRIPT" "$substitute/.git" <<'PY' || return 1
import sys
path, substitute_gitdir = sys.argv[1:]
source = open(path, encoding="utf-8").read()
old = "validate_requirements_contract()\nvalidate_source_history()\ncheck_supersession_cycles()"
new = f'''validate_requirements_contract()
os.rename(os.path.join(ROOT, ".git"), os.path.join(ROOT, ".git.authoritative"))
os.rename({substitute_gitdir!r}, os.path.join(ROOT, ".git"))
validate_source_history()
check_supersession_cycles()'''
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_repository_identity_changed:gitdir"* ]]
}

@test "git child uses the bound gitdir when the path is transiently replaced" {
    local substitute="${BATS_TEST_TMPDIR}/transient-gitdir-substitute"
    local fake_gitdir="${BATS_TEST_TMPDIR}/transient-fake-gitdir"
    local hidden_gitdir="${BATS_TEST_TMPDIR}/transient-hidden-gitdir"
    local shim="${BATS_TEST_TMPDIR}/transient-git-wrapper"
    prepare_authenticated_prework_fixture \
        '.source_remarks[0].source_ref = "customer-interview-newly-signed"' \
        || return 1
    mkdir -p "$substitute/datarim/tasks"
    cp "$REQUIREMENTS" "$substitute/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    git -C "$substitute" init -q
    git -C "$substitute" config user.name test
    git -C "$substitute" config user.email test@example.invalid
    git -C "$substitute" add datarim
    git -C "$substitute" commit -q -m clean-substitute
    mv "$substitute/.git" "$fake_gitdir"
    "$PYTHON" - "$shim" "$ROOT/.git" "$hidden_gitdir" "$fake_gitdir" <<'PY' || return 1
import os
import sys
path, authoritative, hidden, fake = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/bin/bash
set -euo pipefail
mv {authoritative!r} {hidden!r}
mv {fake!r} {authoritative!r}
set +e
/usr/bin/git "$@"
rc=$?
set -e
mv {authoritative!r} {fake!r}
mv {hidden!r} {authoritative!r}
exit "$rc"
''')
os.chmod(path, 0o700)
PY
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_digest_deleted:"* ]] \
        && [[ "$output" != *"source_history_repository_identity_changed:"* ]]
}

@test "linked Git worktree gitdir commondir and object store remain authoritative" {
    local linked="${BATS_TEST_TMPDIR}/linked-consumer"
    git -C "$ROOT" worktree add -q --detach "$linked" HEAD || return 1
    ROOT="$linked"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    run_validator_json
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET" and d["findings"] == []' "$output"
}

@test "linked Git worktree rejects common grafts and object alternates" {
    local linked="${BATS_TEST_TMPDIR}/linked-controls-consumer"
    local common_gitdir="$ROOT/.git"
    git -C "$ROOT" worktree add -q --detach "$linked" HEAD || return 1
    ROOT="$linked"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    printf '%s\n' "$(git -C "$ROOT" rev-parse HEAD)" >"${common_gitdir}/info/grafts"
    run_validator_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'source_history_grafts_present'* ]] || return 1
    /bin/rm -f -- "${common_gitdir}/info/grafts"
    printf '%s\n' "${BATS_TEST_TMPDIR}/foreign-objects" >"${common_gitdir}/objects/info/alternates"
    run_validator_json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'source_history_alternates_present'* ]]
}

@test "ambient GIT_DIR cannot substitute a clean authoritative history" {
    local substitute="${BATS_TEST_TMPDIR}/substitute-repository"
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    mkdir -p "$substitute/datarim/tasks"
    cp "$REQUIREMENTS" "$substitute/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    git -C "$substitute" init -q
    git -C "$substitute" config user.name test
    git -C "$substitute" config user.email test@example.invalid
    git -C "$substitute" add datarim
    git -C "$substitute" commit -q -m substituted-clean-history

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" GIT_DIR="${substitute}/.git" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "ambient GIT_WORK_TREE cannot redirect authoritative history discovery" {
    local substitute_worktree="${BATS_TEST_TMPDIR}/substitute-worktree"
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    mkdir -p "$substitute_worktree"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" GIT_WORK_TREE="$substitute_worktree" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "pinned Apple Git version syntax retains authoritative history validation" {
    local shim="${BATS_TEST_TMPDIR}/apple-git"
    "$PYTHON" - "$shim" <<'PY' || return 1
import os
import sys

path = sys.argv[1]
with open(path, "w", encoding="utf-8") as handle:
    handle.write('''#!/bin/bash
if [[ "$*" == "--version" ]]; then
    printf '%s\\n' 'git version 2.39.5 (Apple Git-154)'
    exit 0
fi
exec /usr/bin/git "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework apple-git-version || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    run_test_framework_json
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET" and d["findings"] == []' "$output" \
        || { printf 'apple_git_status=%s output=%s\n' "$status" "$output"; return 1; }
}

@test "ambient GIT_OBJECT_DIRECTORY cannot replace the authoritative object store" {
    local substitute_objects="${BATS_TEST_TMPDIR}/substitute-objects"
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    mkdir -p "$substitute_objects"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" GIT_OBJECT_DIRECTORY="$substitute_objects" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "ambient PATH Git shim cannot substitute a clean authoritative history" {
    local substitute="${BATS_TEST_TMPDIR}/path-substitute-repository"
    local shim_dir="${BATS_TEST_TMPDIR}/path-git-shim"
    local real_git
    real_git="$(command -v git)" || return 1
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    mkdir -p "$substitute/datarim/tasks" "$shim_dir"
    cp "$REQUIREMENTS" "$substitute/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    git -C "$substitute" init -q
    git -C "$substitute" config user.name test
    git -C "$substitute" config user.email test@example.invalid
    git -C "$substitute" add datarim
    git -C "$substitute" commit -q -m substituted-clean-history
    "$PYTHON" - "${shim_dir}/git" "$real_git" "$substitute" <<'PY' || return 1
import os
import sys

path, real_git, substitute = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
args=()
skip_next=false
for argument in "$@"; do
    if [[ "$skip_next" == true ]]; then
        skip_next=false
        continue
    fi
    if [[ "$argument" == -C ]]; then
        skip_next=true
        continue
    fi
    args+=("$argument")
done
exec "{real_git}" -C "{substitute}" "${{args[@]}}"
''')
os.chmod(path, 0o700)
PY

    run env PATH="${shim_dir}:${PATH}" CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format json
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "historical null source snapshot fails closed without traceback" {
    local commit
    commit="$(commit_invalid_historical_requirements null)" || return 1
    run_validator_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical list source snapshot fails closed without traceback" {
    local commit
    commit="$(commit_invalid_historical_requirements list)" || return 1
    run_validator_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical null source remarks fail closed without traceback" {
    local commit
    commit="$(commit_invalid_historical_requirements null-source-remarks)" || return 1
    run_validator_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical malformed source record fails closed without traceback" {
    local commit
    commit="$(commit_invalid_historical_requirements invalid-record)" || return 1
    run_validator_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical legacy schema version remains source-comparable" {
    commit_invalid_historical_requirements legacy-schema-version >/dev/null || return 1
    run_validator_json
    [ "$status" -eq 0 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "MET" and d["findings"] == []' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical invalid UTF-8 fails closed without traceback" {
    local commit
    commit="$(commit_invalid_historical_requirements invalid-utf8)" || return 1
    run_validator_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "historical Git batch read failure fails closed without traceback" {
    local commit git_path shim
    commit="$(git -C "$ROOT" rev-parse HEAD)" || return 1
    git_path="$(command -v git)" || return 1
    shim="${BATS_TEST_TMPDIR}/git-show-failure"
    mkdir -p "$shim"
    "$PYTHON" - "${shim}/git" "$git_path" <<'PY' || return 1
import os
import sys

path, real_git = sys.argv[1:]
script = f'''#!/usr/bin/env bash
for argument in "$@"; do
    if [[ "$argument" == cat-file ]]; then
        exit 73
    fi
done
exec "{real_git}" "$@"
'''
with open(path, "w", encoding="utf-8") as handle:
    handle.write(script)
os.chmod(path, 0o700)
PY
    build_test_framework git-read-failure || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}/git\"" || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && assert_source_history_parse_result "$commit" "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "source history commit scan is capped and fails closed" {
    local commit
    commit="$(commit_invalid_historical_requirements legacy-schema-version)" || return 1
    [ -n "$commit" ] || return 1
    build_test_framework history-commit-budget || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_MAX_COMMITS = 1024' \
        'SOURCE_HISTORY_MAX_COMMITS = 1' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:commit_budget"]' "$output"
}

@test "source history blob output is capped and fails closed" {
    build_test_framework history-output-budget || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_MAX_TOTAL_BLOB_BYTES = 16777216' \
        'SOURCE_HISTORY_MAX_TOTAL_BLOB_BYTES = 64' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:output_budget"]' "$output"
}

@test "source history subprocesses share one total deadline" {
    local shim="${BATS_TEST_TMPDIR}/slow-git"
    local real_git start end elapsed
    real_git="$(command -v git)" || return 1
    "$PYTHON" - "$shim" "$real_git" <<'PY' || return 1
import os
import sys

path, real_git = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
for argument in "$@"; do
    if [[ "$argument" == cat-file ]]; then
        sleep 2
    fi
done
exec "{real_git}" "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework history-total-deadline || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS = 10' \
        'SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS = 1' || return 1
    start="$($PYTHON -c 'import time; print(time.perf_counter())')"
    run_test_framework_json
    end="$($PYTHON -c 'import time; print(time.perf_counter())')"
    elapsed="$($PYTHON -c 'import sys; print(float(sys.argv[2])-float(sys.argv[1]))' "$start" "$end")"
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:deadline"]' "$output" \
        && "$PYTHON" -c 'import sys; assert float(sys.argv[1]) < 1.8' "$elapsed"
}


@test "source history stdout cap terminates producer before oversized output completes" {
    local shim="${BATS_TEST_TMPDIR}/oversized-stdout-git"
    local canary="${BATS_TEST_TMPDIR}/oversized-stdout-completed"
    local real_git
    real_git="$(command -v git)" || return 1
    "$PYTHON" - "$shim" "$real_git" "$canary" <<'PY' || return 1
import os
import sys

path, real_git, canary = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
if [[ "$*" == *"rev-parse --git-dir"* ]]; then
    head -c 1048576 /dev/zero | tr '\\0' x
    : > "{canary}"
    exit 0
fi
exec "{real_git}" "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework history-stream-stdout || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES = 262144' \
        'SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES = 1024' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:output_budget"]' "$output" \
        && [ ! -e "$canary" ]
}

@test "source history stderr cap terminates producer before oversized diagnostics complete" {
    local shim="${BATS_TEST_TMPDIR}/oversized-stderr-git"
    local canary="${BATS_TEST_TMPDIR}/oversized-stderr-completed"
    local real_git
    real_git="$(command -v git)" || return 1
    "$PYTHON" - "$shim" "$real_git" "$canary" <<'PY' || return 1
import os
import sys

path, real_git, canary = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
if [[ "$*" == *"rev-parse --git-dir"* ]]; then
    head -c 1048576 /dev/zero | tr '\\0' e >&2
    : > "{canary}"
fi
exec "{real_git}" "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework history-stream-stderr || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_MAX_STDERR_BYTES = 65536' \
        'SOURCE_HISTORY_MAX_STDERR_BYTES = 1024' || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:output_budget"]' "$output" \
        && [ ! -e "$canary" ]
}

@test "source history deadline kills stubborn descendant pipe holders" {
    local shim="${BATS_TEST_TMPDIR}/descendant-pipe-git"
    local pidfile="${BATS_TEST_TMPDIR}/descendant-pipe.pid"
    local real_git start end elapsed descendant_pid descendant_state
    real_git="$(command -v git)" || return 1
    "$PYTHON" - "$shim" "$real_git" "$pidfile" <<'PY' || return 1
import os
import sys

path, real_git, pidfile = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
if [[ "$*" == *"rev-parse --git-dir"* ]]; then
    /usr/bin/python3 -c 'import os,signal,time; p=os.fork(); p and os._exit(0); signal.signal(signal.SIGHUP, signal.SIG_IGN); signal.signal(signal.SIGTERM, signal.SIG_IGN); open("{pidfile}", "w").write(str(os.getpid())); time.sleep(4)' &
    printf '%s\\n' "$PWD"
    exit 0
fi
exec "{real_git}" "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework history-descendant-deadline || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    replace_test_script_literal \
        'SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS = 10' \
        'SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS = 1' || return 1
    start="$($PYTHON -c 'import time; print(time.perf_counter())')"
    run_test_framework_json
    end="$($PYTHON -c 'import time; print(time.perf_counter())')"
    elapsed="$($PYTHON -c 'import sys; print(float(sys.argv[2])-float(sys.argv[1]))' "$start" "$end")"
    descendant_pid="$(cat "$pidfile")" || return 1
    descendant_state="$(ps -o stat= -p "$descendant_pid" 2>/dev/null || true)"
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_resource_limit:deadline"]' "$output" \
        && "$PYTHON" -c 'import sys; assert float(sys.argv[1]) < 2.5' "$elapsed" \
        && { [ -z "$descendant_state" ] || [[ "$descendant_state" == Z* ]]; }
}

@test "MET requires an authoritative Git history for the requirement source" {
    mv "${ROOT}/.git" "${BATS_TEST_TMPDIR}/hidden-git"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_unavailable"* ]]
}

@test "bound repository whose Git probe fails is unavailable" {
    local shim="${BATS_TEST_TMPDIR}/failing-git-probe"
    local real_git
    real_git="$(command -v git)" || return 1
    "$PYTHON" - "$shim" "$real_git" <<'PY' || return 1
import os
import sys

path, real_git = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    handle.write(f'''#!/usr/bin/env bash
if [[ "$*" == *"rev-parse --git-dir"* ]]; then
    exit 1
fi
exec "{real_git}" "$@"
''')
os.chmod(path, 0o700)
PY
    build_test_framework failing-git-probe || return 1
    replace_test_script_literal \
        'PINNED_GIT = "/usr/bin/git"' \
        "PINNED_GIT = \"${shim}\"" || return 1
    run_test_framework_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["findings"] == ["source_history_unavailable"]' "$output"
}

@test "MET requires the requirement source itself in authoritative Git history" {
    mv "${ROOT}/.git" "${BATS_TEST_TMPDIR}/baseline-git"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.name test
    git -C "$ROOT" config user.email test@example.invalid
    git -C "$ROOT" add "datarim/receipts"
    git -C "$ROOT" commit -q -m receipts-only
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_unavailable"* ]]
}

@test "Git replacement objects cannot hide an in-place source mutation" {
    local baseline tree replacement
    baseline="$(git -C "$ROOT" rev-parse HEAD)"
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-in-place"' "$REQUIREMENTS"
    git -C "$ROOT" add "datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    tree="$(git -C "$ROOT" write-tree)"
    replacement="$(printf 'replacement\n' | git -C "$ROOT" commit-tree "$tree")"
    git -C "$ROOT" replace "$baseline" "$replacement"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"source_history_prior_record_mutated:source-0001"* ]]
}

@test "shallow Git history cannot authorize customer delivery" {
    local head
    head="$(git -C "$ROOT" rev-parse HEAD)"
    printf '%s\n' "$head" >"${ROOT}/.git/shallow"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["findings"] == ["source_history_shallow_repository"]' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "Git grafts cannot rewrite authoritative customer history" {
    local head
    head="$(git -C "$ROOT" rev-parse HEAD)"
    printf '%s\n' "$head" >"${ROOT}/.git/info/grafts"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["findings"] == ["source_history_grafts_present"]' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "Git object alternates cannot supply authoritative customer history" {
    mkdir -p "${ROOT}/.git/objects/info"
    printf '%s\n' "${BATS_TEST_TMPDIR}/foreign-objects" >"${ROOT}/.git/objects/info/alternates"
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["findings"] == ["source_history_alternates_present"]' "$output"
}

@test "nested YAML lone surrogate is deterministic JSON NOT_MET without traceback" {
    "$PYTHON" - "$REQUIREMENTS" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = "evidence_ref: source-authority-approval-0001"
if source.count(needle) != 1:
    raise SystemExit("nested evidence_ref seam missing or ambiguous")
source = source.replace(needle, 'evidence_ref: "\\uD800"')
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    run_validator_json
    [ "$status" -eq 1 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "NOT_MET" and d["findings"] == ["invalid_unicode_scalar:requirements:$/source_remarks/0/authority_approval/evidence_ref"]' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "trusted-registry lone surrogate is deterministic JSON ERROR without traceback" {
    build_test_framework registry-surrogate || return 1
    "$PYTHON" - "${TEST_FRAMEWORK}/config/customer-requirement.schema.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    schema = json.load(handle)
schema["x-datarim-signature-contract"]["key_resolution"]["bundled_registry"]["entries"][0]["authority_id"] = "\ud800"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(schema, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["invalid_unicode_scalar:schema:requirements:$/x-datarim-signature-contract/key_resolution/bundled_registry/entries/0/authority_id"]' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

@test "top Unicode boundary returns deterministic JSON when scalar precheck is faulted" {
    build_test_framework unicode-boundary || return 1
    "$PYTHON" - "$TEST_SCRIPT" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = 'reject_invalid_unicode(documents[name], name, "NOT_MET", 1)  # SECURITY_RULE:unicode_document'
if source.count(needle) != 1:
    raise SystemExit("Unicode document precheck seam missing or ambiguous")
source = source.replace(needle, "pass  # TEST_FAULT:unicode_document")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    "$PYTHON" - "$REQUIREMENTS" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
source = source.replace(
    "evidence_ref: source-authority-approval-0001",
    'evidence_ref: "\\uD800"',
)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    run_test_framework_json
    [ "$status" -eq 2 ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["status"] == "ERROR" and d["findings"] == ["unicode_processing_error"]' "$output" \
        && [[ "$output" != *"Traceback"* ]]
}

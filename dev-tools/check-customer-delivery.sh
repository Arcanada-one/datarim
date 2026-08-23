#!/usr/bin/env bash
# Deterministically validate one task's customer-delivery evidence bundle.
#
# Canonical task-bound artifacts under --root (no discovery or fallback):
#   datarim/tasks/<TASK-ID>-customer-requirements.yaml
#   datarim/receipts/<TASK-ID>-customer-delivery.yaml
#   datarim/receipts/<TASK-ID>-review-evolution.yaml
#
# Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

usage() {
    cat <<'EOF'
usage: check-customer-delivery.sh --root DIR --task TASK-ID --stage qa|compliance|archive [--format text|json]

Reads exactly these canonical task-bound artifacts below DIR:
  datarim/tasks/<TASK-ID>-customer-requirements.yaml
  datarim/receipts/<TASK-ID>-customer-delivery.yaml
  datarim/receipts/<TASK-ID>-review-evolution.yaml

Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
EOF
}

root=''
task=''
stage=''
format='text'
parse_error=''
while (($#)); do
    case "$1" in
        --root|--task|--stage|--format)
            option="$1"
            if (($# < 2)); then
                parse_error='invalid_usage'
                break
            fi
            value="$2"
            case "$option" in
                --root) root="$value" ;;
                --task) task="$value" ;;
                --stage) stage="$value" ;;
                --format) format="$value" ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            parse_error='invalid_usage'
            shift
            ;;
    esac
done

emit_config_error() {
    local finding="$1"
    local safe_task=''
    local safe_stage=''
    [[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]] && safe_task="$task"
    [[ "$stage" == qa || "$stage" == compliance || "$stage" == archive ]] && safe_stage="$stage"
    if [[ "$format" == json ]]; then
        printf '{"decision":"ERROR","findings":["%s"],"stage":"%s","status":"ERROR","task":"%s"}\n' \
            "$finding" "$safe_stage" "$safe_task"
    else
        printf 'decision=ERROR stage=%s task=%s status=ERROR findings=%s\n' \
            "$safe_stage" "$safe_task" "$finding"
        printf 'finding=%s\n' "$finding"
    fi
}

if [[ -n "$parse_error" || -z "$root" || -z "$task" || -z "$stage" ]]; then
    emit_config_error 'invalid_usage'
    exit 2
fi
[[ "$format" == text || "$format" == json ]] || { format='text'; emit_config_error 'invalid_format'; exit 2; }
[[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]] || { emit_config_error 'invalid_task'; exit 2; }
[[ "$stage" == qa || "$stage" == compliance || "$stage" == archive ]] || { emit_config_error 'invalid_stage'; exit 2; }
[[ -d "$root" && ! -L "$root" ]] || { emit_config_error 'invalid_root'; exit 2; }
root="$(cd "$root" && pwd -P)"

framework_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ -d "$framework_root" ]] || { emit_config_error 'invalid_framework_root'; exit 2; }
requirements="${root}/datarim/tasks/${task}-customer-requirements.yaml"
receipt="${root}/datarim/receipts/${task}-customer-delivery.yaml"
review="${root}/datarim/receipts/${task}-review-evolution.yaml"
requirements_schema="${framework_root}/config/customer-requirement.schema.json"
receipt_schema="${framework_root}/config/customer-delivery-receipt.schema.json"
review_schema="${framework_root}/config/review-evolution.schema.json"

resolve_confined_file() {
    local label="$1"
    local candidate="$2"
    local boundary="$3"
    local resolved
    if [[ ! -f "$candidate" ]]; then
        emit_config_error "missing_artifact:${label}"
        return 2
    fi
    if [[ -L "$candidate" ]]; then
        emit_config_error "path_escape:${label}"
        return 2
    fi
    resolved="$(realpath -e -- "$candidate")" || {
        emit_config_error "path_escape:${label}"
        return 2
    }
    case "$resolved" in
        "$boundary"/*) resolved_file="$resolved" ;;
        *)
            emit_config_error "path_escape:${label}"
            return 2
            ;;
    esac
}

resolved_file=''
resolve_confined_file requirements "$requirements" "$root" || exit 2
requirements="$resolved_file"
resolve_confined_file receipt "$receipt" "$root" || exit 2
receipt="$resolved_file"
resolve_confined_file review "$review" "$root" || exit 2
review="$resolved_file"
resolve_confined_file requirements_schema "$requirements_schema" "$framework_root" || exit 2
requirements_schema="$resolved_file"
resolve_confined_file receipt_schema "$receipt_schema" "$framework_root" || exit 2
receipt_schema="$resolved_file"
resolve_confined_file review_schema "$review_schema" "$framework_root" || exit 2
review_schema="$resolved_file"

python_bin="${CUSTOMER_DELIVERY_PYTHON:-python3}"
if ! "$python_bin" -c 'import jsonschema, yaml; assert "date-time" in jsonschema.FormatChecker().checkers' >/dev/null 2>&1; then
    emit_config_error 'missing_python_dependencies'
    exit 2
fi
exec "$python_bin" - "$task" "$stage" "$format" "$root" \
    "$requirements" "$receipt" "$review" \
    "$requirements_schema" "$receipt_schema" "$review_schema" <<'PY'
import base64
import binascii
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime

import jsonschema
import yaml


TASK, STAGE, OUTPUT_FORMAT, ROOT = sys.argv[1:5]
DOCUMENT_PATHS = dict(zip(
    ("requirements", "receipt", "review"),
    sys.argv[5:8],
))
SCHEMA_PATHS = dict(zip(
    ("requirements", "receipt", "review"),
    sys.argv[8:11],
))

U4_EDGES = (
    "requirement",  # U4_EDGE
    "selected_knowledge",  # U4_EDGE
    "implementation_delta",  # U4_EDGE
    "red_green",  # U4_EDGE
    "merged_revision",  # U4_EDGE
    "deployed_revision",  # U4_EDGE
    "live_evidence",  # U4_EDGE
    "customer_disposition",  # U4_EDGE
)
KNOWLEDGE_KINDS = (
    "roles", "skills", "blueprints", "constraints", "policies", "success_criteria"
)
PAINTED_MATRIX = {
    (locale, viewport, theme)
    for locale in ("ru", "en")
    for viewport in ("mobile", "desktop")
    for theme in ("light", "dark")
}
APPROVAL_FIELDS = (
    "approved_digest",
    "authority_id",
    "authority_role",
    "approved_at",
    "evidence_ref",
    "algorithm",
    "key_id",
)
EXPECTED_INVARIANT_REGISTRY_DIGESTS = {
    "requirements": "6192ad1fe2c834a630a1c98b773976d3ea64db399681bb563bf1568434f129b8",
    "receipt": "1250c71d958cd19f7b1bd71cf6400cea5cb4c404a37d6ed328c9c3e4f5ce17dc",
}
EXPECTED_CONTRACT_DIGESTS = {
    "requirements:x-datarim-crypto-verifier-contract": "01d0ec21009c76101d4046190404667c64a5aa61abc22b612ca77befe3d91e72",
    "requirements:x-datarim-canonicalization": "bbd3995cdfbded121f17ef11f4751c0c02ccceef2b9f393f4969163af29053d0",
    "requirements:x-datarim-source-tier-authorization": "f5f858651d222f1dab1560060cefbd8d49a47a2b41e2b95161b74b4b9dfc3109",
    "receipt:x-datarim-customer-disposition-contract": "994129b7b66c3ad29f4e76bb564ae4937d42e2e46dd5a983dd3eaa7741bf5d96",
    "receipt:x-datarim-coverage-chain-digest-contract": "9f7f5391d3c7922d97fe33148f5d7c2dc1a72808415f899cc04129ef5ee95b68",
    "receipt:x-datarim-task-identity-contract": "7a473577dd2f09bb1e26559f30cf1b62e627233ee6bc8b3fea68c29706629a00",
    "review:x-datarim-originating-review-contract": "292e30935e6ee89252bcd7eae0487184115f96b6b6ad2e3d71c6a1f767770975",
}
PINNED_OPENSSL = "/usr/bin/openssl"
PINNED_REGISTRY_OWNER_ID = "authority-operator-0001"
PINNED_REGISTRY_ROOT_KEY_ID = "key-registry-root-0001"
PINNED_REGISTRY_PUBLIC_KEY = "r6djD8Z3khD94nHJ2NuHwFahvXDkuirHLxPsk/NR0LI="
PINNED_REGISTRY_FINGERPRINT = (
    "sha256:97b1d5e3ea072e7c5b168dab1304aa5f7916f3cd5857b452104ff748a6ad47c4"
)


class DuplicateKeyError(yaml.YAMLError):
    def __init__(self, key):
        super().__init__(str(key))
        self.key = str(key)


class UniqueKeyLoader(yaml.SafeLoader):
    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            event = self.peek_event()
            raise yaml.YAMLError(f"YAML alias is not allowed: {event.anchor}")
        return super().compose_node(parent, index)


def construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            hash(key)
        except TypeError as error:
            raise yaml.YAMLError("unhashable YAML mapping key") from error
        if key in mapping:
            raise DuplicateKeyError(key)
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


findings = []


def add(code):
    findings.append(code)


def jcs_bytes(payload):
    def check(value):
        if isinstance(value, float):
            raise ValueError("floating-point values are outside the delivery schema domain")
        if isinstance(value, dict):
            if not all(isinstance(key, str) for key in value):
                raise ValueError("JCS object keys must be strings")
            for nested in value.values():
                check(nested)
        elif isinstance(value, list):
            for nested in value:
                check(nested)
        elif value is not None and not isinstance(value, (str, int, bool)):
            raise ValueError("unsupported JCS value")

    check(payload)
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_digest(payload):
    return "sha256:" + hashlib.sha256(jcs_bytes(payload)).hexdigest()


def raw_sha256(value):
    if re.fullmatch(r"sha256:[0-9a-f]{64}", value or "") is None:
        raise ValueError("invalid sha256 framing")
    return bytes.fromhex(value[7:])


def canonical_base64(value, expected_length):
    decoded = base64.b64decode(value, validate=True)
    if len(decoded) != expected_length:
        raise ValueError("invalid decoded length")
    if base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError("noncanonical base64")
    return decoded


def verify_ed25519(signature_text, digest_text, public_key_text):
    try:
        message = raw_sha256(digest_text)
        if not signature_text.startswith("ed25519:"):
            return False
        signature = canonical_base64(signature_text[8:], 64)
        public_key = canonical_base64(public_key_text, 32)
    except (TypeError, ValueError, binascii.Error):
        return False
    try:
        with tempfile.TemporaryDirectory(prefix="customer-delivery-crypto-") as directory:
            key_path = os.path.join(directory, "public.der")
            message_path = os.path.join(directory, "message.bin")
            signature_path = os.path.join(directory, "signature.bin")
            with open(key_path, "wb") as handle:
                handle.write(bytes.fromhex("302a300506032b6570032100") + public_key)
            with open(message_path, "wb") as handle:
                handle.write(message)
            with open(signature_path, "wb") as handle:
                handle.write(signature)
            result = subprocess.run(
                [
                    PINNED_OPENSSL,
                    "pkeyutl",
                    "-verify",
                    "-pubin",
                    "-keyform",
                    "DER",
                    "-inkey",
                    key_path,
                    "-rawin",
                    "-in",
                    message_path,
                    "-sigfile",
                    signature_path,
                ],
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                env={"LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"},
            )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def approval_payload_digest(approval):
    return sha256_digest({field: approval[field] for field in APPROVAL_FIELDS})


def emit(decision, code, epic_status="NOT_MET"):
    unique = sorted(set(findings))
    if OUTPUT_FORMAT == "json":
        print(json.dumps(
            {
                "decision": decision,
                "epic_status": epic_status,
                "findings": unique,
                "stage": STAGE,
                "status": decision,
                "task": TASK,
            },
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ))
    else:
        joined = ",".join(unique)
        print(
            f"decision={decision} stage={STAGE} task={TASK} status={decision} "
            f"epic_status={epic_status} findings={joined}"
        )
        for finding in unique:
            print(f"finding={finding}")
    raise SystemExit(code)


def deterministic_unicode_excepthook(error_type, error, traceback):
    if issubclass(error_type, UnicodeError):
        add("unicode_processing_error")  # SECURITY_RULE:unicode_top_boundary
        try:
            emit("ERROR", 2)
        except SystemExit as exit_status:
            sys.stdout.flush()
            sys.stderr.flush()
            os._exit(exit_status.code)
    sys.__excepthook__(error_type, error, traceback)


sys.excepthook = deterministic_unicode_excepthook


def json_pointer_segment(value):
    return value.replace("~", "~0").replace("/", "~1")


def invalid_unicode_scalar_path(value, path="$"):
    if isinstance(value, str):
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            return path
        return None
    if isinstance(value, list):
        for index, item in enumerate(value):
            violation = invalid_unicode_scalar_path(item, f"{path}/{index}")
            if violation is not None:
                return violation
        return None
    if isinstance(value, dict):
        for index, (key, item) in enumerate(value.items()):
            if isinstance(key, str) and any(
                0xD800 <= ord(character) <= 0xDFFF for character in key
            ):
                return f"{path}/<invalid-key-{index}>"
            segment = json_pointer_segment(key) if isinstance(key, str) else f"<key-{index}>"
            violation = invalid_unicode_scalar_path(item, f"{path}/{segment}")
            if violation is not None:
                return violation
    return None


def reject_invalid_unicode(value, label, decision, code):
    violation = invalid_unicode_scalar_path(value)
    if violation is not None:
        add(f"invalid_unicode_scalar:{label}:{violation}")
        emit(decision, code)


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


documents = {}
schemas = {}
for name in ("requirements", "receipt", "review"):
    try:
        with open(DOCUMENT_PATHS[name], encoding="utf-8") as handle:
            loader = UniqueKeyLoader(handle)
            try:
                documents[name] = loader.get_single_data()
            finally:
                loader.dispose()
        reject_invalid_unicode(documents[name], name, "NOT_MET", 1)  # SECURITY_RULE:unicode_document
    except DuplicateKeyError as error:
        add(f"duplicate_id:{error.key}")
        emit("NOT_MET", 1)
    except (OSError, UnicodeError, yaml.YAMLError):
        add(f"parse:{name}")
        emit("NOT_MET", 1)
    try:
        schemas[name] = load_json(SCHEMA_PATHS[name])
        reject_invalid_unicode(schemas[name], f"schema:{name}", "ERROR", 2)  # SECURITY_RULE:unicode_schema
        jsonschema.Draft202012Validator.check_schema(schemas[name])
    except (OSError, UnicodeError, json.JSONDecodeError, jsonschema.SchemaError):
        add(f"invalid_framework_schema:{name}")
        emit("ERROR", 2)


def validate_invariant_contracts():
    for name, expected in EXPECTED_INVARIANT_REGISTRY_DIGESTS.items():
        registry = schemas[name].get("x-datarim-semantic-invariants")
        if not isinstance(registry, dict) or hashlib.sha256(jcs_bytes(registry)).hexdigest() != expected:
            add(f"invariant_registry_mismatch:{name}")
    for locator, expected in EXPECTED_CONTRACT_DIGESTS.items():
        name, annotation = locator.split(":", 1)
        contract = schemas[name].get(annotation)
        if not isinstance(contract, dict) or hashlib.sha256(jcs_bytes(contract)).hexdigest() != expected:
            add(f"semantic_contract_mismatch:{name}:{annotation}")


def validate_crypto_verifier():
    expected = {
        "backend": "OPENSSL",
        "major_version": 3,
        "executable": PINNED_OPENSSL,
        "resolution": "PINNED_ABSOLUTE_PATH",
        "ambient_path": "PROHIBITED",
        "file_type": "REGULAR",
        "owner_uid": 0,
        "group_or_other_writable": "PROHIBITED",
        "verification_success_exit_code": 0,
    }
    if schemas["requirements"].get("x-datarim-crypto-verifier-contract") != expected:
        add("crypto_verifier_contract_mismatch")
        return False
    try:
        metadata = os.lstat(PINNED_OPENSSL)
    except OSError:
        add("missing_crypto_dependency:openssl3")
        return False
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_mode & 0o022
    ):
        add("untrusted_crypto_dependency:openssl3")
        return False
    try:
        result = subprocess.run(
            [PINNED_OPENSSL, "version"],
            check=False,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
            env={"LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"},
        )
    except (OSError, subprocess.SubprocessError):
        add("missing_crypto_dependency:openssl3")
        return False
    if result.returncode != 0 or re.match(r"^OpenSSL 3\.", result.stdout) is None:
        add("untrusted_crypto_dependency:openssl3")
        return False
    return True


def validate_trust_registry():
    resolution = schemas["requirements"].get("x-datarim-signature-contract", {}).get(
        "key_resolution", {}
    )
    expected_locator = {
        "schema_relative_path": "customer-requirement.schema.json",
        "json_pointer": "/x-datarim-signature-contract/key_resolution/bundled_registry",
        "resolution": "BUNDLED_ONLY",
        "ambient_override": "PROHIBITED",
    }
    if resolution.get("registry_locator") != expected_locator:
        add("trust_registry_locator_mismatch")  # SECURITY_RULE:registry_locator
    owner = resolution.get("registry_owner", {})
    anchor = owner.get("trust_anchor", {}) if isinstance(owner, dict) else {}
    expected_anchor = {
        "key_id": PINNED_REGISTRY_ROOT_KEY_ID,
        "algorithm": "ED25519",
        "public_key": PINNED_REGISTRY_PUBLIC_KEY,
        "fingerprint": PINNED_REGISTRY_FINGERPRINT,
        "semantics": "SCHEMA_REVIEWED_PINNED_PUBLIC_KEY",
        "usage": "REGISTRY_SIGNATURE_ONLY",
    }
    if owner.get("authority_id") != PINNED_REGISTRY_OWNER_ID or owner.get("authority_role") != "OPERATOR":
        add("trust_registry_owner_mismatch")  # SECURITY_RULE:registry_owner
    if anchor != expected_anchor:
        add("trust_registry_anchor_mismatch")  # SECURITY_RULE:registry_anchor
    try:
        root_key = canonical_base64(PINNED_REGISTRY_PUBLIC_KEY, 32)
        if "sha256:" + hashlib.sha256(root_key).hexdigest() != PINNED_REGISTRY_FINGERPRINT:
            add("trust_registry_anchor_fingerprint_mismatch")
    except (ValueError, binascii.Error):
        add("trust_registry_anchor_framing")

    registry = resolution.get("bundled_registry")
    if not isinstance(registry, dict) or set(registry) != {
        "registry_id", "revision", "digest", "registry_signature", "entries"
    }:
        add("trust_registry_structure")  # SECURITY_RULE:registry_structure
        return None
    entries = registry.get("entries")
    if not isinstance(entries, list) or not entries:
        add("trust_registry_structure")
        return None
    seen = {}
    for entry in entries:
        if not isinstance(entry, dict):
            add("trust_registry_structure")
            continue
        key_id = entry.get("key_id", "unknown")
        if key_id in seen:
            if entry == seen[key_id]:
                add(f"trust_registry_duplicate_key:{key_id}")  # SECURITY_RULE:registry_duplicate
            else:
                add(f"trust_registry_conflicting_key:{key_id}")  # SECURITY_RULE:registry_conflict
        seen[key_id] = entry
        if set(entry) - {
            "key_id", "authority_id", "allowed_roles", "public_key", "status",
            "valid_from", "valid_until",
        }:
            add(f"trust_registry_entry_not_closed:{key_id}")
        try:
            canonical_base64(entry["public_key"], 32)
            valid_from = datetime.fromisoformat(entry["valid_from"].replace("Z", "+00:00"))
            valid_until = entry.get("valid_until")
            if valid_until is not None and valid_from >= datetime.fromisoformat(
                valid_until.replace("Z", "+00:00")
            ):
                add(f"trust_registry_invalid_window:{key_id}")  # SECURITY_RULE:registry_window
        except (KeyError, TypeError, ValueError, binascii.Error):
            add(f"trust_registry_entry_invalid:{key_id}")
    ids = [entry.get("key_id", "") for entry in entries if isinstance(entry, dict)]
    if ids != sorted(ids):
        add("trust_registry_entry_order")  # SECURITY_RULE:registry_order
    registry_payload = {
        field: registry[field] for field in ("registry_id", "revision", "entries")
    }
    if registry.get("digest") != sha256_digest(registry_payload):
        add("trust_registry_digest_mismatch")  # SECURITY_RULE:registry_digest
    if not verify_ed25519(
        registry.get("registry_signature", ""),
        registry.get("digest", ""),
        PINNED_REGISTRY_PUBLIC_KEY,
    ):
        add("trust_registry_signature_invalid")  # SECURITY_RULE:registry_signature
    expected_ref = {
        **expected_locator,
        "registry_id": registry.get("registry_id"),
        "registry_digest": registry.get("digest"),
    }
    if schemas["receipt"].get("x-datarim-trusted-authority-key-registry-ref") != expected_ref:
        add("receipt_trust_registry_ref_mismatch")  # SECURITY_RULE:registry_receipt_ref
    if schemas["review"].get("x-datarim-trusted-authority-key-registry-ref") != expected_ref:
        add("review_trust_registry_ref_mismatch")  # SECURITY_RULE:registry_review_ref
    return seen


validate_invariant_contracts()
if findings or not validate_crypto_verifier():
    emit("ERROR", 2)
trusted_keys = validate_trust_registry()
if findings or trusted_keys is None:
    emit("ERROR", 2)

# Preserve high-value cross-document attribution even when an A1 conditional
# schema rule also rejects the same otherwise-readable delivery document.
receipt_document = documents.get("receipt")
requirements_document = documents.get("requirements")
receipt_requirements = (
    receipt_document.get("requirements", {})
    if isinstance(receipt_document, dict)
    else {}
)
preflight_requirements = (
    requirements_document.get("requirements", {})
    if isinstance(requirements_document, dict)
    else {}
)
if isinstance(receipt_requirements, dict):
    for requirement_id, delivery in sorted(receipt_requirements.items()):
        chain = delivery.get("coverage_chain", {}) if isinstance(delivery, dict) else {}
        for edge in delivery.get("missing_edges", []) if isinstance(delivery, dict) else []:
            if edge not in chain or (
                edge == "customer_disposition"
                and isinstance(chain.get(edge), dict)
                and chain[edge].get("status") == "pending"
            ):
                add(f"missing_edge:{requirement_id}:{edge}")
        delta = chain.get("implementation_delta", {}) if isinstance(chain, dict) else {}
        live = chain.get("live_evidence", {}) if isinstance(chain, dict) else {}
        requirement = preflight_requirements.get(requirement_id, {})
        acceptance = requirement.get("acceptance", {}) if isinstance(requirement, dict) else {}
        acceptance_scope = acceptance.get("applicability", {}) if isinstance(acceptance, dict) else {}
        live_scope = live.get("applicability", {}) if isinstance(live, dict) else {}
        if acceptance.get("visitor_visible") is True and acceptance_scope.get(
            "painted_matrix_applicable"
        ) is False:
            add(f"visitor_matrix_not_applicable:{requirement_id}")
        if (
            isinstance(acceptance_scope, dict)
            and isinstance(live_scope, dict)
            and acceptance_scope.get("painted_matrix_applicable")
            != live_scope.get("painted_matrix_applicable")
        ):
            add(f"applicability_mismatch:{requirement_id}")
        if (
            isinstance(delta, dict)
            and isinstance(live, dict)
            and acceptance.get("visitor_visible") is True
            and (delta.get("visitor_visible_count", 0) < 1 or not delta.get("visitor_visible_changes"))
        ):
            add(f"zero_visitor_visible_delta:{requirement_id}")
            add(f"user_facing_parent_enabling_only:{requirement_id}")

format_checker = jsonschema.FormatChecker()
for name in ("requirements", "receipt", "review"):
    validator = jsonschema.Draft202012Validator(
        schemas[name],
        format_checker=format_checker,
    )
    for error in sorted(
        validator.iter_errors(documents[name]),
        key=lambda item: tuple(str(part) for part in item.absolute_path),
    ):
        path = "/".join(str(part) for part in error.absolute_path) or "$"
        add(f"schema:{name}:{path}")

if findings:
    emit("NOT_MET", 1)

requirements_doc = documents["requirements"]
receipt_doc = documents["receipt"]
review_doc = documents["review"]
requirements = requirements_doc["requirements"]
deliveries = receipt_doc["requirements"]
sources = {item["source_id"]: item for item in requirements_doc["source_remarks"]}
assertions = {}
assertions_by_requirement = {}

if len(sources) != len(requirements_doc["source_remarks"]):
    add("duplicate_id:source")
for source in requirements_doc["source_remarks"]:
    for assertion in source["tier1_assertions"]:
        assertion_id = assertion["assertion_id"]
        if assertion_id in assertions:
            add(f"duplicate_id:assertion:{assertion_id}")
        assertions[assertion_id] = (source["source_id"], assertion)
        assertions_by_requirement.setdefault(assertion["requirement_id"], set()).add(
            assertion_id
        )
if requirements_doc["requirement_set_id"] != receipt_doc["requirement_set_id"]:
    add("requirement_set_mismatch")

for source_id, source in sorted(sources.items()):
    for requirement_id in source["requirement_ids"]:
        if requirement_id not in requirements:
            add(f"dangling_requirement_ref:{source_id}:{requirement_id}")
        elif source_id not in requirements[requirement_id]["source_ids"]:
            add(f"source_mapping_not_bidirectional:{source_id}:{requirement_id}")

for requirement_id, requirement in sorted(requirements.items()):
    for source_id in requirement["source_ids"]:
        if source_id not in sources:
            add(f"dangling_source_ref:{requirement_id}:{source_id}")
        elif requirement_id not in sources[source_id]["requirement_ids"]:
            add(f"source_mapping_not_bidirectional:{source_id}:{requirement_id}")

for requirement_id in sorted(set(requirements) - set(deliveries)):
    add(f"dangling_delivery_ref:{requirement_id}")
for requirement_id in sorted(set(deliveries) - set(requirements)):
    add(f"dangling_requirement_ref:receipt:{requirement_id}")


def parse_time(value, code):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        add(code)
        return None


def validate_approval(kind, record_id, approval):
    key_id = approval["key_id"]
    binding = trusted_keys.get(key_id)
    if binding is None:
        add(f"{kind}_approval_key_unknown:{record_id}:{key_id}")  # SECURITY_RULE:key_known
        return
    if approval["authority_id"] != binding["authority_id"]:
        add(f"{kind}_approval_authority_mismatch:{record_id}")  # SECURITY_RULE:key_authority
    if approval["authority_role"] not in binding["allowed_roles"]:
        add(f"{kind}_approval_role_unauthorized:{record_id}")  # SECURITY_RULE:key_role
    if binding["status"] != "ACTIVE":
        add(f"{kind}_approval_key_not_active:{record_id}")  # SECURITY_RULE:key_active
    approved_at = parse_time(approval["approved_at"], f"timestamp:{record_id}:approved_at")
    valid_from = parse_time(binding["valid_from"], f"timestamp:{key_id}:valid_from")
    valid_until = (
        parse_time(binding["valid_until"], f"timestamp:{key_id}:valid_until")
        if "valid_until" in binding
        else None
    )
    if approved_at is not None and valid_from is not None and approved_at < valid_from:
        add(f"{kind}_approval_key_not_yet_valid:{record_id}")  # SECURITY_RULE:key_valid_from
    if approved_at is not None and valid_until is not None and approved_at >= valid_until:
        add(f"{kind}_approval_key_expired:{record_id}")  # SECURITY_RULE:key_window
    if not verify_ed25519(
        approval["signature"], approval["approval_payload_digest"], binding["public_key"]
    ):
        add(f"{kind}_signature_invalid:{record_id}")  # SECURITY_RULE:artifact_signature


def originating_review_payload():
    origin = review_doc["originating_review"]
    return {
        "review_id": review_doc["review_id"],
        "requirement_id": review_doc["requirement_id"],
        "delivery_receipt_id": review_doc["delivery_receipt_id"],
        "reviewer": review_doc["reviewer"],
        "review_ref": origin["review_ref"],
        "state": origin["state"],
        "observed_at": origin["observed_at"],
        "evidence_ref": origin["evidence_ref"],
    }


def validate_originating_review_commitment():
    review_id = review_doc["review_id"]
    origin = review_doc["originating_review"]
    approval = origin["authority_approval"]
    expected_digest = sha256_digest(originating_review_payload())
    if origin["review_digest"] != expected_digest:
        add(f"originating_review_digest_mismatch:{review_id}")  # SECURITY_RULE:review_digest
    if approval["approved_digest"] != origin["review_digest"]:
        add(f"originating_review_approval_digest_mismatch:{review_id}")  # SECURITY_RULE:review_approved_digest
    if approval["approval_payload_digest"] != approval_payload_digest(approval):
        add(f"originating_review_approval_payload_digest_mismatch:{review_id}")  # SECURITY_RULE:review_approval_digest


def validate_originating_review_approval():
    review_id = review_doc["review_id"]
    approval = review_doc["originating_review"]["authority_approval"]
    key_id = approval["key_id"]
    binding = trusted_keys.get(key_id)
    if binding is None:
        add(f"originating_review_approval_key_unknown:{review_id}:{key_id}")  # SECURITY_RULE:review_key_known
        return
    if approval["authority_id"] != binding["authority_id"]:
        add(f"originating_review_approval_authority_mismatch:{review_id}")  # SECURITY_RULE:review_key_authority
    if approval["authority_role"] not in binding["allowed_roles"]:
        add(f"originating_review_approval_role_unauthorized:{review_id}")  # SECURITY_RULE:review_key_role
    if binding["status"] != "ACTIVE":
        add(f"originating_review_approval_key_not_active:{review_id}")  # SECURITY_RULE:review_key_active
    approved_at = parse_time(approval["approved_at"], f"timestamp:{review_id}:approved_at")
    valid_from = parse_time(binding["valid_from"], f"timestamp:{key_id}:valid_from")
    valid_until = parse_time(
        binding.get("valid_until"), f"timestamp:{key_id}:valid_until"
    ) if "valid_until" in binding else None
    if approved_at is not None and valid_from is not None and approved_at < valid_from:
        add(f"originating_review_approval_key_not_yet_valid:{review_id}")  # SECURITY_RULE:review_key_valid_from
    if approved_at is not None and valid_until is not None and approved_at >= valid_until:
        add(f"originating_review_approval_key_expired:{review_id}")  # SECURITY_RULE:review_key_window
    if not verify_ed25519(
        approval["signature"], approval["approval_payload_digest"], binding["public_key"]
    ):
        add(f"originating_review_signature_invalid:{review_id}")  # SECURITY_RULE:review_signature


def validate_originating_review_state():
    review_id = review_doc["review_id"]
    requirement_id = review_doc["requirement_id"]
    origin = review_doc["originating_review"]
    observed_at = parse_time(origin["observed_at"], f"timestamp:{review_id}:observed_at")
    reviewed_at = parse_time(review_doc["reviewed_at"], f"timestamp:{review_id}:reviewed_at")
    if observed_at is not None and reviewed_at is not None and observed_at > reviewed_at:
        add(f"originating_review_observed_after_reviewed_at:{review_id}")  # SECURITY_RULE:review_observed_at
    if origin["state"] == "OPEN":
        add(f"parent_review_not_closed:{requirement_id}")  # SECURITY_RULE:review_state_open
    if origin["state"] == "CHANGES_REQUESTED":
        add(f"parent_review_not_closed:{requirement_id}")  # SECURITY_RULE:review_state_changes


def validate_originating_review():
    validate_originating_review_commitment()
    validate_originating_review_approval()
    validate_originating_review_state()


def scope_equal(left, right):
    return (
        all(set(left[field]) == set(right[field]) for field in ("locales", "viewports", "themes"))
        and left["painted_matrix_applicable"] == right["painted_matrix_applicable"]
    )


def validate_requirements_contract():
    tier_roles = schemas["requirements"]["x-datarim-source-tier-authorization"][
        "tier_authority_roles"
    ]
    source_digests = {source["source_digest"] for source in sources.values()}
    for source_id, source in sorted(sources.items()):
        approval = source["authority_approval"]
        if approval["authority_role"] not in tier_roles.get(source["source_tier"], []):
            add(f"source_tier_role_unauthorized:{source_id}")  # SECURITY_RULE:source_tier_role
        source_payload = {
            "source_id": source["source_id"],
            "revision": source["revision"],
            "source_tier": source["source_tier"],
            "verbatim_quote": source["verbatim_quote"],
            "captured_at": source["captured_at"],
            "requirement_ids": sorted(source["requirement_ids"]),
        }
        for optional in ("locale", "source_ref", "supersedes_source_digest"):
            if optional in source:
                source_payload[optional] = source[optional]
        expected_digest = sha256_digest(source_payload)
        if source["source_digest"] != expected_digest:
            add(f"source_digest_mismatch:{source_id}")  # SECURITY_RULE:source_digest
        if approval["approved_digest"] != source["source_digest"]:
            add(f"source_approval_digest_mismatch:{source_id}")  # SECURITY_RULE:source_approved_digest
        if approval["approval_payload_digest"] != approval_payload_digest(approval):
            add(f"source_approval_payload_digest_mismatch:{source_id}")  # SECURITY_RULE:source_approval_digest
        validate_approval("source", source_id, approval)
        superseded = source.get("supersedes_source_digest")
        if superseded is not None and superseded not in source_digests:
            add(f"source_superseded_digest_dangling:{source_id}")

        asserted_requirements = {
            assertion["requirement_id"] for assertion in source["tier1_assertions"]
        }
        if asserted_requirements != set(source["requirement_ids"]):
            add(f"source_assertion_mapping_mismatch:{source_id}")
        for requirement_id in source["requirement_ids"]:
            if requirement_id not in requirements:
                add(f"dangling_requirement_ref:{source_id}:{requirement_id}")
                continue
            started_at = parse_time(
                requirements[requirement_id]["acceptance"]["implementation"]["started_at"],
                f"timestamp:{requirement_id}:implementation_started_at",
            )
            approved_at = parse_time(
                approval["approved_at"], f"timestamp:{source_id}:approved_at"
            )
            if approved_at is not None and started_at is not None and approved_at >= started_at:
                add(f"tier1_approval_not_before_implementation:{source_id}")

        for assertion in source["tier1_assertions"]:
            assertion_id = assertion["assertion_id"]
            assertion_approval = assertion["authority_approval"]
            if assertion["source_digest"] != source["source_digest"]:
                add(f"assertion_source_digest_mismatch:{assertion_id}")
            assertion_payload = {
                key: value
                for key, value in assertion.items()
                if key not in {"assertion_digest", "authority_approval"}
            }
            if assertion["assertion_digest"] != sha256_digest(assertion_payload):
                add(f"assertion_digest_mismatch:{assertion_id}")  # SECURITY_RULE:assertion_digest
            equality_findings = {
                "authority_id": "assertion_source_authority_mismatch",
                "authority_role": "assertion_source_role_mismatch",
                "key_id": "assertion_source_key_mismatch",
            }
            for field, code in equality_findings.items():
                if assertion_approval[field] != approval[field]:
                    add(f"{code}:{assertion_id}")  # SECURITY_RULE:assertion_source_binding
            if assertion_approval["approved_digest"] != assertion["assertion_digest"]:
                add(f"assertion_approval_digest_mismatch:{assertion_id}")  # SECURITY_RULE:assertion_approved_digest
            if assertion_approval["approval_payload_digest"] != approval_payload_digest(
                assertion_approval
            ):
                add(f"assertion_approval_payload_digest_mismatch:{assertion_id}")  # SECURITY_RULE:assertion_approval_digest
            validate_approval("assertion", assertion_id, assertion_approval)
            requirement_id = assertion["requirement_id"]
            if requirement_id in requirements:
                started_at = parse_time(
                    requirements[requirement_id]["acceptance"]["implementation"]["started_at"],
                    f"timestamp:{requirement_id}:implementation_started_at",
                )
                approved_at = parse_time(
                    assertion_approval["approved_at"],
                    f"timestamp:{assertion_id}:approved_at",
                )
                if approved_at is not None and started_at is not None and approved_at >= started_at:
                    add(f"tier1_approval_not_before_implementation:{assertion_id}")

    for requirement_id, requirement in sorted(requirements.items()):
        acceptance = requirement["acceptance"]
        validate_knowledge_selection(requirement_id, acceptance)
        referenced_assertions = set(requirement["tier1_assertion_ids"])
        authoritative_assertions = assertions_by_requirement.get(requirement_id, set())
        if referenced_assertions != authoritative_assertions:
            add(f"assertion_mapping_mismatch:{requirement_id}")
        authoritative_sources = {
            assertions[assertion_id][0]
            for assertion_id in referenced_assertions
            if assertion_id in assertions
        }
        if authoritative_sources != set(requirement["source_ids"]):
            add(f"source_assertion_mapping_mismatch:{requirement_id}")
        selected_assertion_id = acceptance["tier1_assertion_id"]
        if selected_assertion_id not in assertions:
            add(f"dangling_assertion_ref:{requirement_id}:{selected_assertion_id}")
        elif selected_assertion_id not in referenced_assertions:
            add(f"assertion_replaced:{requirement_id}:{selected_assertion_id}")

        provided_quotes = {}
        for row in acceptance["exact_source_quotes"]:
            if row["source_id"] in provided_quotes:
                add(f"exact_quote_source_duplicate:{requirement_id}:{row['source_id']}")
            provided_quotes[row["source_id"]] = row["verbatim_quote"]
        expected_quotes = {
            source_id: sources[source_id]["verbatim_quote"]
            for source_id in authoritative_sources
            if source_id in sources
        }
        if provided_quotes != expected_quotes:
            add(f"exact_quote_mismatch:{requirement_id}")

        accepted_scope = acceptance["applicability"]
        for assertion_id in sorted(referenced_assertions):
            if assertion_id not in assertions:
                continue
            assertion = assertions[assertion_id][1]
            identity_codes = {
                "predicate_id": "tier1_predicate_mismatch",
                "product": "tier1_product_mismatch",
                "surface": "tier1_surface_mismatch",
                "surface_class": "tier1_surface_class_mismatch",
            }
            for field, code in identity_codes.items():
                if acceptance[field] != assertion[field]:
                    add(f"{code}:{requirement_id}")
            asserted_scope = assertion["applicability"]
            for dimension in ("locales", "viewports", "themes"):
                if set(asserted_scope[dimension]) - set(accepted_scope[dimension]):
                    add(f"tier1_scope_weakened:{requirement_id}:{dimension}")
            if assertion["visitor_visible"] and not acceptance["visitor_visible"]:
                add(f"tier1_visitor_visible_weakened:{requirement_id}")
            if (
                asserted_scope["painted_matrix_applicable"]
                and not accepted_scope["painted_matrix_applicable"]
            ):
                add(f"tier1_painted_applicability_weakened:{requirement_id}")

        production = acceptance.get("production_assertion")
        if production is not None:
            for field in ("product", "surface", "surface_class", "predicate_id"):
                if production[field] != acceptance[field]:
                    add(f"production_assertion_identity_mismatch:{requirement_id}:{field}")
            if not scope_equal(production["applicability"], accepted_scope):
                add(f"production_assertion_scope_mismatch:{requirement_id}")
        method = acceptance["evidence"]["method"]
        if isinstance(method, dict):
            for field in ("product", "surface", "surface_class", "predicate_id"):
                if method[field] != acceptance[field]:
                    add(f"evidence_identity_mismatch:{requirement_id}:{field}")
            if not scope_equal(method["applicability"], accepted_scope):
                add(f"evidence_scope_mismatch:{requirement_id}")
        rendered = acceptance.get("rendered_test_evidence")
        if rendered is not None:
            for field in ("product", "surface", "predicate_id"):
                if rendered[field] != acceptance[field]:
                    add(f"rendered_test_identity_mismatch:{requirement_id}:{field}")
            if not scope_equal(rendered["applicability"], accepted_scope):
                add(f"rendered_test_scope_mismatch:{requirement_id}")
            rendered_at = parse_time(
                rendered["observed_at"], f"timestamp:{requirement_id}:rendered_test"
            )
            started_at = parse_time(
                acceptance["implementation"]["started_at"],
                f"timestamp:{requirement_id}:implementation_started_at",
            )
            if rendered_at is not None and started_at is not None and rendered_at < started_at:
                add(f"rendered_test_before_implementation:{requirement_id}")


def validate_source_history():
    git_env = dict(os.environ)
    git_env["GIT_NO_REPLACE_OBJECTS"] = "1"
    try:
        probe = subprocess.run(
            ["git", "-C", ROOT, "rev-parse", "--show-toplevel"],
            check=False,
            capture_output=True,
            env=git_env,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        probe = None
    if (
        probe is None
        or probe.returncode != 0
        or os.path.realpath(probe.stdout.strip()) != os.path.realpath(ROOT)
    ):
        add("source_history_unavailable")  # SECURITY_RULE:source_history_repo_required
        return
    shallow = subprocess.run(
        ["git", "-C", ROOT, "rev-parse", "--is-shallow-repository"],
        check=False,
        capture_output=True,
        env=git_env,
        text=True,
        timeout=10,
    )
    if shallow.returncode != 0 or shallow.stdout.strip() not in {"true", "false"}:
        add("source_history_unavailable")
        return
    if shallow.stdout.strip() == "true":
        add("source_history_shallow_repository")  # SECURITY_RULE:source_history_shallow_rejected
        return
    graft_path_result = subprocess.run(
        ["git", "-C", ROOT, "rev-parse", "--git-path", "info/grafts"],
        check=False,
        capture_output=True,
        env=git_env,
        text=True,
        timeout=10,
    )
    if graft_path_result.returncode != 0 or not graft_path_result.stdout.strip():
        add("source_history_unavailable")
        return
    graft_path = graft_path_result.stdout.strip()
    if not os.path.isabs(graft_path):
        graft_path = os.path.join(ROOT, graft_path)
    try:
        graft_present = os.path.getsize(graft_path) > 0
    except FileNotFoundError:
        graft_present = False
    except OSError:
        add("source_history_unavailable")
        return
    if graft_present:
        add("source_history_grafts_present")  # SECURITY_RULE:source_history_grafts_rejected
        return
    relative = os.path.relpath(DOCUMENT_PATHS["requirements"], ROOT)
    history = subprocess.run(
        ["git", "-C", ROOT, "log", "--format=%H", "--follow", "--", relative],
        check=False,
        capture_output=True,
        env=git_env,
        text=True,
        timeout=10,
    )
    if history.returncode != 0 or not history.stdout.strip():
        add("source_history_unavailable")  # SECURITY_RULE:source_history_document_required
        return
    snapshots = [requirements_doc]
    for commit in history.stdout.splitlines():
        blob = subprocess.run(
            ["git", "-C", ROOT, "show", f"{commit}:{relative}"],
            check=False,
            capture_output=True,
            env=git_env,
            text=True,
            timeout=10,
        )
        if blob.returncode != 0:
            continue
        try:
            prior = yaml.load(blob.stdout, Loader=UniqueKeyLoader)
        except yaml.YAMLError:
            add("source_history_parse")
            continue
        if prior != snapshots[-1]:
            snapshots.append(prior)
    for newer, older in zip(snapshots, snapshots[1:]):
        old_by_digest = {item["source_digest"]: item for item in older["source_remarks"]}
        new_by_digest = {item["source_digest"]: item for item in newer["source_remarks"]}
        for digest, prior in old_by_digest.items():
            if digest not in new_by_digest:
                add(f"source_history_prior_digest_deleted:{digest}")
            elif new_by_digest[digest] != prior:
                add(f"source_history_prior_record_mutated:{prior['source_id']}")  # SECURITY_RULE:source_history
        for digest, source in new_by_digest.items():
            superseded = source.get("supersedes_source_digest")
            if digest not in old_by_digest and superseded is not None and superseded not in old_by_digest:
                add(f"source_history_correction_not_linked:{source['source_id']}")


def validate_requirement_edge(requirement_id, requirement, chain):
    requirement_ref = chain["requirement"]
    if requirement_ref["requirement_id"] != requirement_id:
        add(f"requirement_identity_mismatch:{requirement_id}")
    provided = {}
    for row in requirement_ref["source_quote_digests"]:
        if row["source_id"] in provided:
            add(f"source_quote_digest_duplicate:{requirement_id}:{row['source_id']}")
        provided[row["source_id"]] = row["digest"]
    expected = {
        source_id: "sha256:" + hashlib.sha256(
            sources[source_id]["verbatim_quote"].encode("utf-8")
        ).hexdigest()
        for source_id in requirement["source_ids"]
        if source_id in sources
    }
    if set(provided) != set(expected):
        add(f"source_quote_digest_set_mismatch:{requirement_id}")
    for source_id in sorted(set(provided) & set(expected)):
        if provided[source_id] != expected[source_id]:
            add(f"source_quote_digest_mismatch:{requirement_id}:{source_id}")


def validate_selected_knowledge_edge(requirement_id, acceptance, chain):
    selected = acceptance["knowledge_selection"]
    if selected != chain["selected_knowledge"]:
        add(f"knowledge_selection_mismatch:{requirement_id}")


def validate_knowledge_selection(requirement_id, acceptance):
    selected = acceptance["knowledge_selection"]
    started_at = parse_time(
        acceptance["implementation"]["started_at"],
        f"timestamp:{requirement_id}:implementation_started_at",
    )
    seen_ids = set()
    for kind in KNOWLEDGE_KINDS:
        for pin in selected[kind]:
            pin_id = pin["id"]
            if pin_id in seen_ids:
                add(f"duplicate_knowledge_id:{requirement_id}:{pin_id}")
            seen_ids.add(pin_id)
            marker = f"{pin_id} {pin['revision']}".casefold()
            if re.search(r"(^|[^a-z])(gap|unbound)([^a-z]|$)", marker):
                add(f"unbound_product_delivery:{requirement_id}:{kind}")
            if pin["immutable"] is not True or pin["selected_before_implementation"] is not True:
                add(f"knowledge_revision_unpinned:{requirement_id}:{kind}")
            revision = pin["revision"].strip().casefold()
            if revision in {
                "main", "master", "head", "latest", "current", "pending"
            } or re.match(r"^(refs/(heads|remotes)/|origin/|upstream/)", revision):
                add(f"knowledge_revision_unpinned:{requirement_id}:{kind}")
            selected_at = parse_time(
                pin["selected_at"],
                f"timestamp:{requirement_id}:{kind}:selected_at",
            )
            if selected_at is not None and started_at is not None and selected_at >= started_at:
                add(f"knowledge_selected_post_hoc:{requirement_id}:{kind}")


def validate_implementation_delta_edge(requirement_id, acceptance, chain):
    delta = chain["implementation_delta"]
    if delta["task_id"] != acceptance["implementation"]["task_id"]:
        add(f"implementation_task_mismatch:{requirement_id}")
    if delta["visitor_visible_count"] != len(delta["visitor_visible_changes"]):
        add(f"visitor_visible_count_mismatch:{requirement_id}")
    if delta["enabling_count"] != len(delta["enabling_changes"]):
        add(f"enabling_count_mismatch:{requirement_id}")
    seen_ids = set()
    for change in delta["enabling_changes"] + delta["visitor_visible_changes"]:
        delta_id = change["delta_id"]
        if delta_id in seen_ids:
            add(f"duplicate_delta_id:{requirement_id}:{delta_id}")
        seen_ids.add(delta_id)
    if acceptance["visitor_visible"] and (
        delta["visitor_visible_count"] < 1 or not delta["visitor_visible_changes"]
    ):
        add(f"zero_visitor_visible_delta:{requirement_id}")


def validate_red_green_edge(requirement_id, acceptance, chain):
    started_at = parse_time(
        acceptance["implementation"]["started_at"],
        f"timestamp:{requirement_id}:implementation_started_at",
    )
    red_at = parse_time(
        chain["red_green"]["red"]["observed_at"],
        f"timestamp:{requirement_id}:red",
    )
    green_at = parse_time(
        chain["red_green"]["green"]["observed_at"],
        f"timestamp:{requirement_id}:green",
    )
    if red_at is not None and green_at is not None and red_at >= green_at:
        add(f"red_green_timestamp_mismatch:{requirement_id}")
    if started_at is not None and red_at is not None and started_at > red_at:
        add(f"implementation_red_timestamp_mismatch:{requirement_id}")


def validate_merged_revision_edge(requirement_id, acceptance, chain):
    merged = chain["merged_revision"]
    accepted_revisions = {
        acceptance["implementation"]["code_revision"],
        acceptance["implementation"]["content_revision"],
    }
    if merged["revision"] not in accepted_revisions:
        add(f"accepted_revision_mismatch:{requirement_id}")
    green_at = parse_time(
        chain["red_green"]["green"]["observed_at"],
        f"timestamp:{requirement_id}:green",
    )
    merged_at = parse_time(merged["merged_at"], f"timestamp:{requirement_id}:merged")
    if green_at is not None and merged_at is not None and green_at > merged_at:
        add(f"green_merge_timestamp_mismatch:{requirement_id}")


def validate_deployed_revision_edge(requirement_id, chain):
    merged = chain["merged_revision"]
    deployed = chain["deployed_revision"]
    if deployed["revision"] != merged["revision"] or deployed["digest"] != merged["digest"]:
        add(f"production_revision_mismatch:{requirement_id}")
    merged_at = parse_time(merged["merged_at"], f"timestamp:{requirement_id}:merged")
    deployed_at = parse_time(
        deployed["deployed_at"], f"timestamp:{requirement_id}:deployed"
    )
    if merged_at is not None and deployed_at is not None and merged_at > deployed_at:
        add(f"merge_deploy_timestamp_mismatch:{requirement_id}")


def validate_live_evidence_edge(requirement_id, acceptance, chain):
    delta = chain["implementation_delta"]
    deployed = chain["deployed_revision"]
    live = chain["live_evidence"]
    expected_applicable = acceptance["applicability"]["painted_matrix_applicable"]
    identity_codes = {
        "product": "live_product_mismatch",
        "surface": "live_surface_mismatch",
        "surface_class": "live_surface_class_mismatch",
        "predicate_id": "live_predicate_mismatch",
    }
    for field, code in identity_codes.items():
        if live[field] != acceptance[field]:
            add(f"{code}:{requirement_id}")
    if not scope_equal(live["applicability"], acceptance["applicability"]):
        add(f"applicability_mismatch:{requirement_id}")
    if live["painted_matrix_applicable"] != expected_applicable:
        add(f"applicability_mismatch:{requirement_id}")
    if live["visitor_visible"] != acceptance["visitor_visible"]:
        add(f"visitor_visibility_mismatch:{requirement_id}")
    if acceptance["visitor_visible"] and not expected_applicable:
        add(f"visitor_matrix_not_applicable:{requirement_id}")
    if acceptance["visitor_visible"] and (
        not live["visitor_visible"]
        or delta["visitor_visible_count"] < 1
        or not delta["visitor_visible_changes"]
    ):
        add(f"user_facing_parent_enabling_only:{requirement_id}")
    if acceptance["visitor_visible"] and not live["visitor_visible"]:
        add(f"visitor_production_evidence_missing:{requirement_id}")

    matrix = {
        (cell["locale"], cell["viewport"], cell["theme"])
        for cell in live["painted_matrix"]
    }
    applicability = acceptance["applicability"]
    expected_matrix = {
        (locale, viewport, theme)
        for locale in applicability["locales"]
        for viewport in applicability["viewports"]
        for theme in applicability["themes"]
    }
    if expected_applicable and (
        not live["painted_matrix_applicable"]
        or matrix != expected_matrix
        or len(live["painted_matrix"]) != len(expected_matrix)
    ):
        add(f"painted_matrix_incomplete:{requirement_id}")
    if acceptance["visitor_visible"] and (
        expected_matrix != PAINTED_MATRIX
        or matrix != PAINTED_MATRIX
        or len(live["painted_matrix"]) != 8
    ):
        add(f"painted_matrix_incomplete:{requirement_id}")

    deployed_at = parse_time(
        deployed["deployed_at"], f"timestamp:{requirement_id}:deployed"
    )
    live_at = parse_time(live["observed_at"], f"timestamp:{requirement_id}:live")
    disposition_at = parse_time(
        chain["customer_disposition"]["recorded_at"],
        f"timestamp:{requirement_id}:disposition",
    )
    if deployed_at is not None and live_at is not None and deployed_at > live_at:
        add(f"deploy_live_timestamp_mismatch:{requirement_id}")
    rendered = acceptance.get("rendered_test_evidence")
    if rendered is not None:
        rendered_at = parse_time(
            rendered["observed_at"], f"timestamp:{requirement_id}:rendered_test"
        )
        if rendered_at is not None and live_at is not None and rendered_at > live_at:
            add(f"rendered_test_after_live:{requirement_id}")
    for cell in live["painted_matrix"]:
        cell_at = parse_time(
            cell["observed_at"], f"timestamp:{requirement_id}:painted_matrix"
        )
        if cell_at is not None and (
            (deployed_at is not None and cell_at < deployed_at)
            or (live_at is not None and cell_at > live_at)
            or (disposition_at is not None and cell_at > disposition_at)
        ):
            add(f"painted_matrix_timestamp_mismatch:{requirement_id}")


def validate_customer_disposition_edge(requirement_id, acceptance, chain):
    live = chain["live_evidence"]
    disposition = chain["customer_disposition"]
    if disposition["status"] not in ("accepted", "rejected", "superseded"):
        add(f"customer_disposition_not_closed:{requirement_id}")
    if acceptance["disposition"] != disposition["status"]:
        add(f"customer_disposition_mismatch:{requirement_id}")
    live_at = parse_time(live["observed_at"], f"timestamp:{requirement_id}:live")
    disposition_at = parse_time(
        disposition["recorded_at"], f"timestamp:{requirement_id}:disposition"
    )
    if live_at is not None and disposition_at is not None and live_at > disposition_at:
        add(f"live_disposition_timestamp_mismatch:{requirement_id}")
    if disposition["receipt_id"] != receipt_doc["receipt_id"]:
        add(f"disposition_receipt_id_mismatch:{requirement_id}")
    if disposition["requirement_id"] != requirement_id:
        add(f"disposition_requirement_id_mismatch:{requirement_id}")
    chain_payload = {
        field: value for field, value in chain.items() if field != "customer_disposition"
    }
    expected_chain_digest = sha256_digest(chain_payload)
    if disposition["coverage_chain_digest"] != expected_chain_digest:
        add(f"coverage_chain_digest_mismatch:{requirement_id}")  # SECURITY_RULE:coverage_digest
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
    expected_disposition_digest = sha256_digest(disposition_payload)
    if disposition["disposition_digest"] != expected_disposition_digest:
        add(f"disposition_digest_mismatch:{requirement_id}")  # SECURITY_RULE:disposition_digest
    approval = disposition["authority_approval"]
    if approval["approved_digest"] != disposition["disposition_digest"]:
        add(f"disposition_approval_digest_mismatch:{requirement_id}")  # SECURITY_RULE:disposition_approved_digest
    if approval["approval_payload_digest"] != approval_payload_digest(approval):
        add(f"disposition_approval_payload_digest_mismatch:{requirement_id}")  # SECURITY_RULE:disposition_approval_digest
    if acceptance["visitor_visible"] and approval["authority_role"] != "OPERATOR":
        add(f"visitor_disposition_operator_required:{requirement_id}")
    validate_approval("disposition", requirement_id, approval)
    approval_at = parse_time(
        approval["approved_at"], f"timestamp:{requirement_id}:disposition_approved_at"
    )
    if disposition_at is not None and approval_at is not None and approval_at < disposition_at:
        add(f"disposition_approval_timestamp_mismatch:{requirement_id}")


def validate_requirement_set_binding(requirement_id, chain):
    signed_set_ids = {
        chain["requirement"]["requirement_set_id"],
        chain["customer_disposition"]["requirement_set_id"],
    }
    outer_set_ids = {
        requirements_doc["requirement_set_id"],
        receipt_doc["requirement_set_id"],
    }
    if len(signed_set_ids) != 1 or signed_set_ids != outer_set_ids:
        add(f"requirement_set_signed_binding_mismatch:{requirement_id}")


def check_supersession_cycles():
    graph = {}
    for requirement_id, requirement in requirements.items():
        target = requirement["acceptance"].get("superseded_by")
        if target:
            graph[requirement_id] = target
            if target not in requirements:
                add(f"dangling_requirement_ref:{requirement_id}:{target}")
    visited = set()
    active = []
    active_set = set()

    def visit(node):
        if node in active_set:
            cycle_nodes = active[active.index(node):]
            add(f"cycle:{min(cycle_nodes)}")
            return
        if node in visited:
            return
        visited.add(node)
        active.append(node)
        active_set.add(node)
        target = graph.get(node)
        if target in requirements:
            visit(target)
        active.pop()
        active_set.remove(node)

    for node in sorted(requirements):
        visit(node)


def validate_epic_identity_binding(receipt_epics, review_epics, signed_tasks):
    canonical_epics = set()
    for signed_task in signed_tasks:
        match = re.fullmatch(r"task:([a-z][a-z0-9]{1,9}):([0-9]{4})", signed_task)
        if match is not None:
            canonical_epics.add(f"epic:{match.group(1)}:0000")

    def identity_text(identifiers):
        return ",".join(sorted(identifiers)) if identifiers else "<missing>"

    if receipt_epics != canonical_epics:
        finding = f"epic_identity_mismatch:{identity_text(receipt_epics)}:{identity_text(canonical_epics)}"
        add(finding)  # SECURITY_RULE:epic_receipt_binding
    if review_epics != canonical_epics:
        finding = f"review_epic_identity_mismatch:{identity_text(review_epics)}:{identity_text(canonical_epics)}"
        add(finding)  # SECURITY_RULE:epic_review_binding
    return canonical_epics


def validate_invariant_dispatch():
    requirement_ids = """
source-id-unique assertion-id-unique source-requirement-bidirectional
signature-verifier-pinned-absolute-openssl3
source-assertion-bidirectional source-quote-set-exact source-canonical-digest-valid
source-approval-digest-equals-source-digest source-approval-payload-canonical-digest-valid
source-signature-valid source-signature-over-approval-payload-digest-valid
source-approval-key-known source-approval-key-authority-id-equal
source-approval-key-role-authorized source-approval-key-active
source-approval-key-valid-at-approval source-tier-authority-role-authorized
assertion-source-digest-equals-containing-source-digest
source-correction-superseded-digest-exists source-correction-prior-record-retained
source-correction-in-place-replacement-prohibited source-history-prior-digest-set-retained
source-history-prior-record-content-immutable
source-correction-appended-record-supersedes-prior-digest
tier1-assertion-canonical-digest-valid tier1-assertion-approval-digest-equals-assertion-digest
tier1-assertion-approval-payload-canonical-digest-valid tier1-assertion-signature-valid
tier1-assertion-signature-over-approval-payload-digest-valid tier1-assertion-approval-key-known
tier1-assertion-approval-key-authority-id-equal tier1-assertion-approval-key-role-authorized
tier1-assertion-approval-key-active tier1-assertion-approval-key-valid-at-approval
tier1-assertion-approval-authority-id-equals-containing-source
tier1-assertion-approval-authority-role-equals-containing-source
tier1-assertion-approval-key-id-equals-containing-source authority-key-registry-bundled-only
authority-key-registry-owner-pinned authority-key-registry-trust-anchor-pinned
authority-key-registry-canonical-digest-valid
authority-key-registry-signature-valid-against-pinned-trust-anchor
authority-key-registry-entry-order-valid authority-key-registry-key-id-unique
authority-key-registry-conflict-prohibited authority-key-registry-validity-interval-positive
tier1-authority-approval-before-implementation tier1-assertion-correction-append-only
source-verbatim-to-assertion-authority-approval-required assertion-acceptance-predicate-equal
assertion-acceptance-product-equal assertion-acceptance-surface-equal
assertion-acceptance-surface-class-equal acceptance-applicability-superset
acceptance-visitor-visible-nonweakening acceptance-painted-applicability-nonweakening
production-acceptance-product-equal production-acceptance-surface-equal
production-acceptance-surface-class-equal production-acceptance-predicate-equal
production-acceptance-applicability-equal evidence-acceptance-product-equal
evidence-acceptance-surface-equal evidence-acceptance-surface-class-equal
evidence-acceptance-predicate-equal evidence-acceptance-applicability-equal
rendered-test-acceptance-product-equal rendered-test-acceptance-surface-equal
rendered-test-acceptance-predicate-equal rendered-test-acceptance-applicability-equal
rendered-test-observed-after-implementation-start knowledge-selection-id-unique-across-kinds
knowledge-selection-revision-immutable knowledge-selection-revision-not-branch-ref
knowledge-selection-gap-unbound-prohibited knowledge-selection-before-implementation
supersession-target-exists supersession-graph-acyclic
""".split()
    receipt_ids = """
receipt-requirement-key-equals-embedded-id
receipt-requirement-key-set-equals-requirement-document-key-set
receipt-top-requirement-set-equals-embedded-id receipt-source-quote-digest-set-exact
receipt-selected-knowledge-set-exact receipt-implementation-task-equals-parent-task
receipt-u4-edge-declaration-exact receipt-enabling-count-equals-list-cardinality
receipt-visible-count-equals-list-cardinality receipt-live-product-equals-acceptance-product
receipt-live-surface-equals-acceptance-surface
receipt-live-surface-class-equals-acceptance-surface-class
receipt-live-predicate-equals-acceptance-predicate
receipt-live-applicability-equals-acceptance-applicability
receipt-live-visitor-visible-equals-acceptance-visitor-visible
receipt-zero-visible-rejected-for-user-facing receipt-painted-matrix-set-exact
receipt-red-before-green receipt-green-before-merge receipt-merge-before-deploy
receipt-deploy-before-matrix-observation receipt-matrix-observation-not-after-live-summary
receipt-deploy-before-live receipt-live-before-disposition
receipt-rendered-test-before-live-evidence receipt-merged-revision-accepted
receipt-deployed-revision-equals-merged-revision receipt-deployed-digest-equals-merged-digest
receipt-disposition-equals-requirement-disposition receipt-disposition-closure-exact
receipt-coverage-chain-canonical-digest-valid receipt-disposition-receipt-id-equals-top-id
receipt-disposition-requirement-set-id-equals-top-id
receipt-disposition-requirement-id-equals-entry-key receipt-terminal-disposition-signed
receipt-pending-disposition-unsigned receipt-disposition-canonical-digest-valid
receipt-disposition-approval-digest-equals-disposition-digest
receipt-disposition-approval-payload-canonical-digest-valid receipt-disposition-signature-valid
receipt-disposition-approval-key-known receipt-disposition-approval-key-authority-id-equal
receipt-disposition-approval-key-role-authorized receipt-disposition-approval-key-active
receipt-disposition-approval-key-valid-at-approval
receipt-visitor-acceptance-authority-role-operator receipt-parent-links-complete
receipt-cli-task-id-canonical-round-trip
receipt-cli-task-id-equals-signed-implementation-task-id
receipt-canonical-epic-derived-from-signed-task
receipt-epic-parent-equals-signed-canonical-epic
originating-review-receipt-id-equals-top-receipt-id
originating-review-requirement-set-transitively-bound-by-disposition
originating-review-canonical-digest-valid
originating-review-approval-digest-equals-review-digest
originating-review-approval-payload-canonical-digest-valid
originating-review-signature-valid originating-review-approval-key-known
originating-review-approval-key-authority-id-equal
originating-review-approval-key-role-authorized originating-review-approval-key-active
originating-review-approval-key-valid-at-approval
originating-review-observed-at-not-after-reviewed-at
originating-review-epic-parent-equals-signed-canonical-epic
review-open-or-changes-requested-blocks-closure receipt-epic-status-derived
receipt-user-facing-parent-has-visible-child
""".split()
    requirement_map = {identifier: validate_requirements_contract for identifier in requirement_ids}
    receipt_map = {identifier: validate_requirement_edge for identifier in receipt_ids}
    for identifier in requirement_ids:
        if identifier == "signature-verifier-pinned-absolute-openssl3":
            requirement_map[identifier] = validate_crypto_verifier
        elif identifier.startswith("authority-key-registry-"):
            requirement_map[identifier] = validate_trust_registry
        elif "history" in identifier or identifier.startswith("source-correction-"):
            requirement_map[identifier] = validate_source_history
        elif identifier.startswith("knowledge-selection-"):
            requirement_map[identifier] = validate_knowledge_selection
        elif identifier.startswith("supersession-"):
            requirement_map[identifier] = check_supersession_cycles
    for identifier in receipt_ids:
        if identifier in (
            "receipt-canonical-epic-derived-from-signed-task",
            "receipt-epic-parent-equals-signed-canonical-epic",
            "originating-review-epic-parent-equals-signed-canonical-epic",
        ):
            receipt_map[identifier] = validate_epic_identity_binding
        elif identifier.startswith("originating-review-") or identifier == "review-open-or-changes-requested-blocks-closure":
            receipt_map[identifier] = validate_originating_review
        elif "selected-knowledge" in identifier:
            receipt_map[identifier] = validate_selected_knowledge_edge
        elif "count" in identifier or "visible" in identifier and "live" not in identifier:
            receipt_map[identifier] = validate_implementation_delta_edge
        elif any(token in identifier for token in ("live-", "painted-matrix", "matrix-observation", "rendered-test")):
            receipt_map[identifier] = validate_live_evidence_edge
        elif "red-before-green" in identifier:
            receipt_map[identifier] = validate_red_green_edge
        elif "green-before-merge" in identifier or "merged-revision" in identifier:
            receipt_map[identifier] = validate_merged_revision_edge
        elif "merge-before-deploy" in identifier or "deployed-" in identifier:
            receipt_map[identifier] = validate_deployed_revision_edge
        elif "disposition" in identifier:
            receipt_map[identifier] = validate_customer_disposition_edge
    for name, implementation_map in (
        ("requirements", requirement_map),
        ("receipt", receipt_map),
    ):
        registered = set(schemas[name]["x-datarim-semantic-invariants"]["invariant_ids"])
        implemented = set(implementation_map)
        for identifier in sorted(registered - implemented):
            add(f"invariant_unimplemented:{name}:{identifier}")
        for identifier in sorted(implemented - registered):
            add(f"invariant_unregistered:{name}:{identifier}")
        if not all(callable(handler) for handler in implementation_map.values()):
            add(f"invariant_handler_not_callable:{name}")


dispatch_finding_count = len(findings)
validate_invariant_dispatch()  # SECURITY_RULE:invariant_dispatch
if len(findings) != dispatch_finding_count:
    emit("ERROR", 2)
validate_requirements_contract()
validate_source_history()
check_supersession_cycles()

for requirement_id in sorted(set(requirements) & set(deliveries)):
    requirement = requirements[requirement_id]
    acceptance = requirement["acceptance"]
    delivery = deliveries[requirement_id]
    chain = delivery["coverage_chain"]
    actual_missing = [edge for edge in U4_EDGES if edge not in chain]
    if (
        "customer_disposition" in chain
        and chain["customer_disposition"].get("status") == "pending"
        and "customer_disposition" not in actual_missing
    ):
        actual_missing.append("customer_disposition")
    declared_missing = sorted(delivery.get("missing_edges", []))
    if sorted(actual_missing) != declared_missing:
        add(f"missing_edge_declaration_mismatch:{requirement_id}")
    if delivery["coverage_status"] != "MET":
        for edge in sorted(set(actual_missing) | set(declared_missing)):
            add(f"missing_edge:{requirement_id}:{edge}")
        if not actual_missing:
            add(f"coverage_not_met:{requirement_id}")
        continue
    for edge in actual_missing:
        add(f"missing_edge:{requirement_id}:{edge}")
    if actual_missing:
        continue

    validate_requirement_set_binding(requirement_id, chain)  # SECURITY_RULE:review_requirement_set_binding
    validate_requirement_edge(requirement_id, requirement, chain)  # U4_RULE:requirement
    validate_selected_knowledge_edge(requirement_id, acceptance, chain)  # U4_RULE:selected_knowledge
    validate_implementation_delta_edge(requirement_id, acceptance, chain)  # U4_RULE:implementation_delta
    validate_red_green_edge(requirement_id, acceptance, chain)  # U4_RULE:red_green
    validate_merged_revision_edge(requirement_id, acceptance, chain)  # U4_RULE:merged_revision
    validate_deployed_revision_edge(requirement_id, chain)  # U4_RULE:deployed_revision
    validate_live_evidence_edge(requirement_id, acceptance, chain)  # U4_RULE:live_evidence
    validate_customer_disposition_edge(requirement_id, acceptance, chain)  # U4_RULE:customer_disposition

receipt_epics = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "epic"
}
receipt_tasks = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "task"
}
receipt_sets = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "requirement_set"
}
expected_task_links = {
    requirement["acceptance"]["implementation"]["task_id"]
    for requirement in requirements.values()
}
review_links = {(link["relation"], link["id"]) for link in review_doc["parent_links"]}
review_epics = {identifier for relation, identifier in review_links if relation == "epic"}
task_match = re.fullmatch(r"([A-Z][A-Z0-9]{1,9})-([0-9]{4})", TASK)
canonical_cli_task = (
    f"task:{task_match.group(1).lower()}:{task_match.group(2)}"
    if task_match is not None
    else None
)
if canonical_cli_task is None:
    add(f"task_identity_invalid:{TASK}")
elif expected_task_links != {canonical_cli_task}:
    signed_cli_tasks = []
    for signed_task in sorted(expected_task_links):
        signed_match = re.fullmatch(r"task:([a-z][a-z0-9]{1,9}):([0-9]{4})", signed_task)
        signed_cli_tasks.append(
            f"{signed_match.group(1).upper()}-{signed_match.group(2)}"
            if signed_match is not None
            else signed_task
        )
    add(f"task_identity_mismatch:{TASK}:{','.join(signed_cli_tasks)}")  # SECURITY_RULE:task_cli_binding
canonical_epics = validate_epic_identity_binding(
    receipt_epics, review_epics, expected_task_links
)
if not receipt_epics:
    add("dangling_parent_ref:epic")
if receipt_tasks != expected_task_links:
    add("parent_link_set_mismatch:task")
expected_requirement_sets = {requirements_doc["requirement_set_id"]}
if receipt_sets != expected_requirement_sets:
    add("parent_link_set_mismatch:requirement_set")

review_requirement = review_doc["requirement_id"]
if review_requirement not in requirements:
    add(f"dangling_requirement_ref:review:{review_requirement}")
    add(f"review_requirement_mismatch:{review_requirement}")  # SECURITY_RULE:review_requirement_binding
if review_doc["delivery_receipt_id"] != receipt_doc["receipt_id"]:
    add("review_receipt_mismatch")  # SECURITY_RULE:review_receipt_binding
if review_doc["product_fix"]["requirement_id"] != review_requirement:
    add(f"review_product_requirement_mismatch:{review_requirement}")
if review_doc["product_fix"]["delivery_receipt_id"] != receipt_doc["receipt_id"]:
    add("review_product_receipt_mismatch")
if review_doc["product_fix"]["status"] != "DELIVERED":
    add(f"product_fix_not_delivered:{review_requirement}")
validate_originating_review()
required_review_links = {
    ("requirement", review_requirement),
    ("delivery_receipt", receipt_doc["receipt_id"]),
}
required_review_links.update(("epic", epic) for epic in canonical_epics)
required_review_links.update(("task", task_id) for task_id in expected_task_links)
for relation, identifier in sorted(required_review_links - review_links):
    add(f"dangling_parent_ref:review:{relation}:{identifier}")

for requirement_id, delivery in sorted(deliveries.items()):
    if delivery["coverage_chain"].get("customer_disposition", {}).get("status") == "rejected":
        add(f"child_disposition_not_met:{requirement_id}")

all_children_semantically_met = not findings and bool(deliveries) and all(
    item["coverage_status"] == "MET"
    and item["coverage_chain"].get("customer_disposition", {}).get("status") in ("accepted", "superseded")
    for item in deliveries.values()
)
epic_status = "MET" if receipt_epics and all_children_semantically_met else "NOT_MET"
if findings:
    emit("NOT_MET", 1, epic_status)
emit("MET", 0, epic_status)
PY

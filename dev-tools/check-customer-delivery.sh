#!/bin/bash -p
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

# Imported Bash functions and caller PATH entries are not trusted execution
# authority. Security-relevant external utilities below are invoked only by
# their validated host paths; clearing common names also prevents accidental
# future call sites from inheriting an exported function implementation.
unset -f cat dirname jq mktemp realpath rm stat tail wc 2>/dev/null || true

usage() {
    /usr/bin/cat <<'EOF'
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

framework_root="$(cd "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
    local resolved resolved_dir
    if [[ ! -f "$candidate" ]]; then
        emit_config_error "missing_artifact:${label}"
        return 2
    fi
    if [[ -L "$candidate" ]]; then
        emit_config_error "path_escape:${label}"
        return 2
    fi
    resolved_dir="$(cd -P -- "${candidate%/*}" && pwd -P)" || {
        emit_config_error "path_escape:${label}"
        return 2
    }
    resolved="${resolved_dir}/${candidate##*/}"
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

platform="$(/usr/bin/uname -s 2>/dev/null || true)"
architecture="$(/usr/bin/uname -m 2>/dev/null || true)"
case "$platform" in
    Linux)
        default_python='/usr/bin/python3'
        python_min_minor=11
        pinned_openssl='/usr/bin/openssl'
        ;;
    Darwin)
        default_python='/usr/bin/python3'
        python_min_minor=9
        case "$architecture" in
            arm64) pinned_openssl='/opt/homebrew/opt/openssl@3/bin/openssl' ;;
            x86_64) pinned_openssl='/usr/local/opt/openssl@3/bin/openssl' ;;
            *) emit_config_error 'unsupported_platform'; exit 2 ;;
        esac
        ;;
    *) emit_config_error 'unsupported_platform'; exit 2 ;;
esac

python_bin="${CUSTOMER_DELIVERY_PYTHON:-$default_python}"
if [[ -z "$python_bin" || ! -x "$python_bin" || -d "$python_bin" ]]; then
    emit_config_error 'untrusted_python_runtime'
    exit 2
fi
[[ "$python_bin" == /* ]] || { emit_config_error 'untrusted_python_runtime'; exit 2; }

stat_identity() {
    case "$platform" in
        Linux)
            /usr/bin/stat -L -c '%d|%i|%u|%a|%F' "$1" 2>/dev/null
            ;; # PORTABLE_TRUST:linux_gnu_stat
        Darwin)
            /usr/bin/stat -L -f '%d|%i|%u|%Lp|%HT' "$1" 2>/dev/null
            ;; # PORTABLE_TRUST:darwin_bsd_stat
    esac
}

python_metadata="$(stat_identity "$python_bin" || true)"
python_trusted=false
trusted_python_anchor=''
python_anchors=(/usr/bin/python3)
for python_anchor in "${python_anchors[@]}"; do
    [[ -e "$python_anchor" ]] || continue
    anchor_metadata="$(stat_identity "$python_anchor" || true)"
    [[ -n "$anchor_metadata" && "$python_metadata" == "$anchor_metadata" ]] || continue
    IFS='|' read -r _ _ python_uid python_mode python_type \
        <<<"$anchor_metadata"
    if [[ "$python_uid" == 0 && "$python_mode" =~ ^[0-7]{3,4}$ \
        && ("$python_type" == 'regular file' || "$python_type" == 'Regular File') ]] \
        && (( (8#$python_mode & 8#022) == 0 )); then
        python_trusted=true
        trusted_python_anchor="$python_anchor"
        break
    fi
done
if [[ "$python_trusted" != true ]]; then  # SECURITY_RULE:python_inode_trust
    emit_config_error 'untrusted_python_runtime'
    exit 2
fi

# Apple's fixed /usr/bin/python3 is an xcselect launcher, not necessarily the
# final CPython binary. Resolve it with all pre-CPython routing authority
# removed, then execute only the validated runtime.  # PORTABLE_TRUST:launcher_runtime_identity
unset DEVELOPER_DIR TOOLCHAINS __PYVENV_LAUNCHER__ PYTHONEXECUTABLE PYTHONHOME PYTHONPATH

secure_root_path() {
    local candidate="$1"
    local required_root="$2"
    local final_kind="$3"
    local current='' component metadata uid mode type
    local -a components=()
    [[ "$candidate" == /* && "$candidate" != *$'\n'* ]] || return 1
    if [[ -n "$required_root" ]]; then
        case "$candidate" in
            "$required_root"|"$required_root"/*) ;;
            *) return 1 ;;
        esac
    fi
    IFS='/' read -r -a components <<<"${candidate#/}"
    ((${#components[@]} > 0)) || return 1
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current="${current}/${component}"
        metadata="$(stat_identity "$current" || true)"
        IFS='|' read -r _ _ uid mode type <<<"$metadata"
        [[ -n "$metadata" && "$uid" == 0 && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#$mode & 8#022) == 0 )) || return 1
        if [[ "$current" == "$candidate" ]]; then
            case "$final_kind:$type" in
                'file:regular file'|'file:Regular File'|'directory:directory'|'directory:Directory') ;;
                *) return 1 ;;
            esac
        else
            [[ "$type" == directory || "$type" == Directory ]] || return 1
        fi
    done
}

trusted_developer_root=''
if [[ "$platform" == Darwin ]]; then
    # The hosted runner's active Xcode lives below the admin-writable
    # /Applications directory. Select the separately installed, immutable CLT
    # tree explicitly instead of weakening the component ownership contract.
    trusted_developer_root='/Library/Developer/CommandLineTools'
    secure_root_path "$trusted_developer_root" '' directory || {
        emit_config_error 'untrusted_python_runtime'
        exit 2
    }
fi
secure_root_path "$trusted_python_anchor" '' file || {
    emit_config_error 'untrusted_python_runtime'
    exit 2
}
if [[ "$platform" == Darwin ]]; then
    trusted_runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        DEVELOPER_DIR="$trusted_developer_root" \
        "$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
else
    trusted_runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        "$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
fi
secure_root_path "$trusted_runtime_path" "$trusted_developer_root" file || {
    emit_config_error 'untrusted_python_runtime'
    exit 2
}
trusted_runtime_metadata="$(stat_identity "$trusted_runtime_path" || true)"
IFS='|' read -r trusted_runtime_device trusted_runtime_inode trusted_runtime_uid \
    trusted_runtime_mode trusted_runtime_type <<<"$trusted_runtime_metadata"
if [[ -z "$trusted_runtime_metadata" || "$trusted_runtime_uid" != 0 \
    || ! "$trusted_runtime_mode" =~ ^[0-7]{3,4}$ \
    || ("$trusted_runtime_type" != 'regular file' && "$trusted_runtime_type" != 'Regular File') ]] \
    || (( (8#$trusted_runtime_mode & 8#022) != 0 )); then  # SECURITY_RULE:python_runtime_metadata_trust
    emit_config_error 'untrusted_python_runtime'
    exit 2
fi

trusted_python_site=''
trusted_python_site_metadata=''
if [[ "$platform" == Darwin ]]; then
    runtime_version="$(/usr/bin/env -i LC_ALL=C "$trusted_runtime_path" -I -c \
        'import sys; print(f"{sys.version_info.major}|{sys.version_info.minor}")' \
        2>/dev/null || true)"
    IFS='|' read -r runtime_major runtime_minor <<<"$runtime_version"
    if [[ "$python_bin" != */bin/python || "$runtime_major" != 3 \
        || ! "$runtime_minor" =~ ^[0-9]+$ ]]; then
        emit_config_error 'untrusted_python_runtime'
        exit 2
    fi
    python_venv_root="${python_bin%/bin/python}"
    trusted_python_site="${python_venv_root}/lib/python${runtime_major}.${runtime_minor}/site-packages"
    if [[ "$trusted_python_site" != /* || "$trusted_python_site" == *$'\n'* \
        || -L "$trusted_python_site" || ! -d "$trusted_python_site" ]]; then
        emit_config_error 'untrusted_python_runtime'
        exit 2
    fi
    # A .pth file is executable import-time authority. The pinned validator
    # dependencies do not require one, so this boundary rejects them instead
    # of asking site.addsitedir() to execute unverified code.
    for pth_file in "$trusted_python_site"/*.pth; do
        if [[ -e "$pth_file" || -L "$pth_file" ]]; then
            emit_config_error 'untrusted_python_runtime'
            exit 2
        fi
    done
    trusted_python_site_metadata="$(stat_identity "$trusted_python_site" || true)"
    [[ -n "$trusted_python_site_metadata" ]] || {
        emit_config_error 'untrusted_python_runtime'
        exit 2
    }
    IFS='|' read -r trusted_python_site_device trusted_python_site_inode _ \
        <<<"$trusted_python_site_metadata"
fi

assert_python_runtime_identity() {
    local current_candidate current_runtime current_site='' pth_file
    current_candidate="$(stat_identity "$python_bin" || true)"
    current_runtime="$(stat_identity "$trusted_runtime_path" || true)"
    if [[ "$platform" == Darwin ]]; then
        current_site="$(stat_identity "$trusted_python_site" || true)"
        [[ ! -L "$trusted_python_site" && "$current_site" == "$trusted_python_site_metadata" ]] \
            || return 1
        for pth_file in "$trusted_python_site"/*.pth; do
            [[ ! -e "$pth_file" && ! -L "$pth_file" ]] || return 1
        done
    fi
    [[ "$current_candidate" == "$python_metadata" \
        && "$current_runtime" == "$trusted_runtime_metadata" ]] \
        && secure_root_path "$trusted_runtime_path" "$trusted_developer_root" file
}

if [[ "$platform" == Darwin ]]; then
    python_isolation_args=(-I -S)
else
    python_isolation_args=(-I)
fi

run_trusted_python() {
    local child_status mode program bootstrap_program
    local -a child_args=()
    assert_python_runtime_identity || return 126
    if [[ "$platform" == Darwin ]]; then
        [[ "${1:-}" == -I && "${2:-}" == -S \
            && ("${3:-}" == -c || "${3:-}" == -) ]] || return 126
        mode="$3"
        shift 3
        # Darwin's fdesc exposes a directory descriptor as a non-traversable
        # special file (opening /dev/fd/N/child raises ENOTDIR). fchdir binds
        # relative imports to the already-open directory inode without
        # reopening its mutable pathname.
        bootstrap_program="$(/bin/cat <<'PY'
import importlib
import importlib.util
import os
import re
import stat
import sys
from email.parser import Parser

site_path = os.path.realpath(sys.argv[1])
expected_device = int(sys.argv[2])
expected_inode = int(sys.argv[3])
mode = sys.argv[4]
flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
site_fd = os.open(site_path, flags)
metadata = os.fstat(site_fd)
assert (metadata.st_dev, metadata.st_ino) == (expected_device, expected_inode)
assert not any(name.endswith(".pth") for name in os.listdir(site_fd))
os.fchdir(site_fd)
cwd_metadata = os.stat(".")
assert (cwd_metadata.st_dev, cwd_metadata.st_ino) == (expected_device, expected_inode)
pending = ["."]
scanned = 0
while pending:
    current = pending.pop()
    with os.scandir(current) as entries:
        for entry in entries:
            scanned += 1
            assert scanned <= 20000
            assert not entry.is_symlink()
            if entry.is_dir(follow_symlinks=False):
                pending.append(entry.path)

def normalized_distribution(value):
    return re.sub(r"[-_.]+", "_", value).lower()

def authenticated_dist_version(site_fd, distribution, expected_version):  # SECURITY_RULE:python_distinfo_type
    expected_basename = (
        f"{normalized_distribution(distribution)}-{expected_version}.dist-info"
    )
    candidates = [
        name for name in os.listdir(site_fd)
        if name.lower() == expected_basename.lower()
    ]
    if len(candidates) != 1:
        raise RuntimeError("dist_info_inventory_invalid")
    dist_info = candidates[0]
    entry_metadata = os.stat(dist_info, dir_fd=site_fd, follow_symlinks=False)
    if not stat.S_ISDIR(entry_metadata.st_mode):
        raise RuntimeError("dist_info_not_directory")
    dist_fd = os.open(dist_info, flags, dir_fd=site_fd)
    try:
        opened_dist_metadata = os.fstat(dist_fd)
        if (
            not stat.S_ISDIR(opened_dist_metadata.st_mode)
            or (opened_dist_metadata.st_dev, opened_dist_metadata.st_ino)
            != (entry_metadata.st_dev, entry_metadata.st_ino)
        ):
            raise RuntimeError("dist_info_identity_changed")
        metadata_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
        metadata_fd = os.open("METADATA", metadata_flags, dir_fd=dist_fd)
        try:
            metadata_before = os.fstat(metadata_fd)
            if (
                not stat.S_ISREG(metadata_before.st_mode)
                or metadata_before.st_size <= 0
                or metadata_before.st_size > 1048576
            ):
                raise RuntimeError("dist_info_metadata_invalid")
            remaining = metadata_before.st_size
            chunks = []
            while remaining:
                chunk = os.read(metadata_fd, min(remaining, 65536))
                if not chunk:
                    raise RuntimeError("dist_info_metadata_truncated")
                chunks.append(chunk)
                remaining -= len(chunk)
            if os.read(metadata_fd, 1) != b"":
                raise RuntimeError("dist_info_metadata_oversized")
            metadata_after = os.fstat(metadata_fd)
            if (
                not stat.S_ISREG(metadata_after.st_mode)
                or (metadata_after.st_dev, metadata_after.st_ino, metadata_after.st_size)
                != (metadata_before.st_dev, metadata_before.st_ino, metadata_before.st_size)
            ):
                raise RuntimeError("dist_info_metadata_identity_changed")
        finally:
            os.close(metadata_fd)
        dist_after = os.fstat(dist_fd)
        if (
            not stat.S_ISDIR(dist_after.st_mode)
            or (dist_after.st_dev, dist_after.st_ino)
            != (entry_metadata.st_dev, entry_metadata.st_ino)
        ):
            raise RuntimeError("dist_info_identity_changed")
    finally:
        os.close(dist_fd)
    parsed = Parser().parsestr(b"".join(chunks).decode("utf-8", "strict"))
    names = parsed.get_all("Name", [])
    versions = parsed.get_all("Version", [])
    if (
        len(names) != 1
        or len(versions) != 1
        or normalized_distribution(names[0]) != normalized_distribution(distribution)
        or versions[0] != expected_version
    ):  # SECURITY_RULE:python_distinfo_metadata
        raise RuntimeError("dist_info_metadata_mismatch")
    return versions[0]

sys.path.insert(0, ".")
trusted_dependency_versions = {}
expected = {
    "jsonschema": ("jsonschema", "4.23.0"),
    "rfc3339_validator": ("rfc3339-validator", "0.1.4"),
    "yaml": ("PyYAML", "6.0.2"),
}
for module_name, (distribution, version) in expected.items():
    spec = importlib.util.find_spec(module_name)
    assert spec is not None and spec.origin is not None
    assert os.path.commonpath((os.path.realpath(spec.origin), site_path)) == site_path
    trusted_dependency_versions[distribution] = authenticated_dist_version(
        site_fd, distribution, version
    )
    module = importlib.import_module(module_name)
    assert os.path.commonpath((os.path.realpath(module.__file__), site_path)) == site_path
cwd_metadata = os.stat(".")
metadata = os.fstat(site_fd)
assert (
    (cwd_metadata.st_dev, cwd_metadata.st_ino)
    == (metadata.st_dev, metadata.st_ino)
    == (expected_device, expected_inode)
)
sys.path.remove(".")
os.chdir("/")
if mode == "-c":
    program = sys.argv[5]
    sys.argv = ["-c"] + sys.argv[6:]
    filename = "<string>"
elif mode == "-":
    program = sys.stdin.buffer.read()
    sys.argv = ["-"] + sys.argv[5:]
    filename = "<stdin>"
else:
    raise SystemExit(126)
exec(compile(program, filename, "exec"), globals(), globals())
PY
)"
        if [[ "$mode" == -c ]]; then
            [[ $# -ge 1 ]] || return 126
            program="$1"
            shift
            child_args=(-I -S -c "$bootstrap_program" "$trusted_python_site" \
                "$trusted_python_site_device" "$trusted_python_site_inode" "$mode" "$program" "$@")
        else
            child_args=(-I -S -c "$bootstrap_program" "$trusted_python_site" \
                "$trusted_python_site_device" "$trusted_python_site_inode" "$mode" "$@")
        fi
        if /usr/bin/env -i LC_ALL=C \
            /bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash \
            "$python_bin" "$trusted_runtime_path" "${child_args[@]}"; then
            child_status=0
        else
            child_status=$?
        fi
    else
        if (
            unset DEVELOPER_DIR TOOLCHAINS __PYVENV_LAUNCHER__ PYTHONEXECUTABLE PYTHONHOME PYTHONPATH
            exec -a "$python_bin" "$trusted_runtime_path" "$@"
        ); then
            child_status=0
        else
            child_status=$?
        fi
    fi
    assert_python_runtime_identity || return 126
    return "$child_status"
}

run_trusted_python_stdlib() {
    local child_status
    assert_python_runtime_identity || return 126
    if [[ "$platform" == Darwin ]]; then
        [[ "${1:-}" == -I && "${2:-}" == -S \
            && ("${3:-}" == -c || "${3:-}" == -) ]] || return 126
        if /usr/bin/env -i LC_ALL=C \
            /bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash \
            "$python_bin" "$trusted_runtime_path" "$@"; then
            child_status=0
        else
            child_status=$?
        fi
    else
        if run_trusted_python "$@"; then
            child_status=0
        else
            child_status=$?
        fi
    fi
    assert_python_runtime_identity || return 126
    return "$child_status"
}

python_probe="$(run_trusted_python_stdlib "${python_isolation_args[@]}" -c '
import os
import sys

metadata = os.stat(sys.argv[1])
print(f"{metadata.st_dev}|{metadata.st_ino}|{sys.implementation.name}|{sys.version_info.major}|{sys.version_info.minor}")
' "$trusted_runtime_path" 2>/dev/null || true)"
IFS='|' read -r probe_device probe_inode probe_implementation probe_major probe_minor \
    <<<"$python_probe"
if [[ "$probe_device" != "$trusted_runtime_device" || "$probe_inode" != "$trusted_runtime_inode" \
    || "$probe_implementation" != cpython || "$probe_major" != 3 \
    || ! "$probe_minor" =~ ^[0-9]+$ || "$probe_minor" -lt "$python_min_minor" ]]; then
    emit_config_error 'untrusted_python_runtime'
    exit 2
fi
if [[ "$platform" != Darwin && "$(run_trusted_python "${python_isolation_args[@]}" -c '
import os
import sys
from importlib import metadata as importlib_metadata
from importlib import util as importlib_util

expected_site = os.path.realpath(sys.argv[1]) if sys.argv[1] else ""
origins_ok = True
if expected_site:
    bound_site = expected_site
    for module_name in ("jsonschema", "rfc3339_validator", "yaml"):
        spec = importlib_util.find_spec(module_name)
        origins_ok = origins_ok and spec is not None and spec.origin is not None \
            and os.path.commonpath((os.path.realpath(spec.origin), bound_site)) == bound_site
expected_versions = {
    "jsonschema": "4.23.0",
    "rfc3339-validator": "0.1.4",
    "PyYAML": "6.0.2",
}
if expected_site:
    versions_ok = trusted_dependency_versions == expected_versions
else:
    versions_ok = all(importlib_metadata.version(name) == version for name, version in expected_versions.items())
import jsonschema
import rfc3339_validator
import yaml
print("CUSTOMER_DELIVERY_DEPENDENCIES_OK" if origins_ok and versions_ok and "date-time" in jsonschema.FormatChecker().checkers else "")
' "$trusted_python_site" 2>/dev/null || true)" != CUSTOMER_DELIVERY_DEPENDENCIES_OK ]]; then
    emit_config_error 'missing_python_dependencies'
    exit 2
fi

umask 077
validator_output="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/customer-delivery-output.XXXXXX")" || {
    emit_config_error 'validator_output_unavailable'
    exit 2
}
trap '/usr/bin/rm -f -- "$validator_output"' EXIT
set +e
run_trusted_python "${python_isolation_args[@]}" - "$task" "$stage" "$format" "$root" \
    "$requirements" "$receipt" "$review" \
    "$requirements_schema" "$receipt_schema" "$review_schema" \
    "$framework_root" "$pinned_openssl" "$platform" >"$validator_output" <<'PY'
import base64
import binascii
import hashlib
import json
import os
import re
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
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
FRAMEWORK_ROOT = sys.argv[11]
PINNED_OPENSSL = sys.argv[12]
PLATFORM = sys.argv[13]

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
    "requirements": "b7638bd5bbebaf6034fa117758d0c7064c5ec0bec572ad5bb5dd897c91c2fd46",
    "receipt": "0ee4fec73622c0ef1e9369f327a6623a7cc249506cea00c0d917cebadffea661",
}
EXPECTED_CONTRACT_DIGESTS = {
    "requirements:x-datarim-crypto-verifier-contract": "9ebeb579d224d2f3db094c9873b7e1990da71f1ef789b30e64c5bb98deb33bed",
    "requirements:x-datarim-canonicalization": "28b09c2be6dc974f1522eb2fa48f34036ab1fa1dd91050109f0ff9d070ce126f",
    "requirements:x-datarim-source-tier-authorization": "f5f858651d222f1dab1560060cefbd8d49a47a2b41e2b95161b74b4b9dfc3109",
    "requirements:x-datarim-prework-identity-contract": "bdb98d473439c859ac6df06596a77e10cba8c711215668c285be44d0397484ce",
    "receipt:x-datarim-customer-disposition-contract": "994129b7b66c3ad29f4e76bb564ae4937d42e2e46dd5a983dd3eaa7741bf5d96",
    "receipt:x-datarim-coverage-chain-digest-contract": "9f7f5391d3c7922d97fe33148f5d7c2dc1a72808415f899cc04129ef5ee95b68",
    "receipt:x-datarim-task-identity-contract": "54e1d0c40950b024a0dcd760ee1964bb467088876b7624ff652e27f5dfbe69a5",
    "review:x-datarim-originating-review-contract": "79278a6f32ce798509cbb7b4578d2116007b37ac3f97646305d091ec3bdae5c4",
}
PINNED_GIT = "/usr/bin/git"
VALIDATION_TOTAL_TIMEOUT_SECONDS = 20
VALIDATION_DEADLINE = time.monotonic() + VALIDATION_TOTAL_TIMEOUT_SECONDS
MAX_INPUT_BYTES = 8388608
MAX_REQUIREMENTS = 512
MAX_SOURCE_RECORDS = 1024
MAX_EVIDENCE_RECORDS = 4096
MAX_SIGNATURES = 1024
MAX_CONTAINER_ITEMS = 8192
MAX_TOTAL_NODES = 100000
VALIDATION_MAX_STDOUT_BYTES = 65536
VALIDATION_MAX_STDERR_BYTES = 65536
SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS = 10
SOURCE_HISTORY_MAX_COMMITS = 1024
SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES = 262144
SOURCE_HISTORY_MAX_STDERR_BYTES = 65536
SOURCE_HISTORY_MAX_TOTAL_BLOB_BYTES = 16777216
PINNED_REGISTRY_OWNER_ID = "authority-operator-0001"
PINNED_REGISTRY_ROOT_KEY_ID = "key-registry-root-0001"
PINNED_REGISTRY_PUBLIC_KEY = "3hzCOohIkBiCEu9V2qNl8r0zc9iCZE/MbLFabv6/o18="
PINNED_REGISTRY_FINGERPRINT = (
    "sha256:dfae487eaca4758d5b0e0ffc372d4594032dc59534ff1124a5b8351f2c923ccf"
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
            returncode = run_silent_process(
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
            )
    except (OSError, subprocess.SubprocessError):
        return False
    return returncode == 0


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


def validation_resource_limit(kind):
    add(f"validation_resource_limit:{kind}")
    emit("ERROR", 2)


def remaining_validation_time():
    remaining = VALIDATION_DEADLINE - time.monotonic()
    if remaining <= 0:
        validation_resource_limit("deadline")
    return remaining


def validation_alarm_handler(_signal_number, _frame):
    validation_resource_limit("deadline")


def terminate_process_group(process):
    # The direct child can exit while a descendant still holds its pipes.
    # Always address the whole session process group, then reap the child.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=0.2)
    except (subprocess.TimeoutExpired, OSError):
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)  # SECURITY_RULE:validation_process_group_reap
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=0.2)
    except (subprocess.TimeoutExpired, OSError):
        pass


def run_silent_process(arguments):
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"},
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    try:
        return process.wait(timeout=max(0.001, remaining_validation_time()))
    except subprocess.TimeoutExpired:
        terminate_process_group(process)
        validation_resource_limit("deadline")
    except BaseException:
        terminate_process_group(process)
        raise


def run_bounded_process(arguments, stdout_limit=VALIDATION_MAX_STDOUT_BYTES,
                        stderr_limit=VALIDATION_MAX_STDERR_BYTES):
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"},
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None, b"", b""
    selector = selectors.DefaultSelector()
    stdout = bytearray()
    stderr = bytearray()
    try:
        for label, stream in (("stdout", process.stdout), ("stderr", process.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, label)
        while selector.get_map():
            remaining = remaining_validation_time()
            events = selector.select(timeout=min(0.05, remaining))
            if not events and process.poll() is not None:
                events = [(key, selectors.EVENT_READ) for key in selector.get_map().values()]
            for key, _ in events:
                try:
                    chunk = os.read(key.fileobj.fileno(), 65536)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                target = stdout if key.data == "stdout" else stderr
                limit = stdout_limit if key.data == "stdout" else stderr_limit
                if len(target) + len(chunk) > limit:
                    terminate_process_group(process)
                    validation_resource_limit("subprocess_output")  # SECURITY_RULE:validation_subprocess_output
                target.extend(chunk)
        returncode = process.wait(timeout=max(0.001, remaining_validation_time()))
        return returncode, bytes(stdout), bytes(stderr)
    except subprocess.TimeoutExpired:
        terminate_process_group(process)
        validation_resource_limit("deadline")
    except BaseException:
        terminate_process_group(process)
        raise
    finally:
        selector.close()
        for stream in (process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()


signal.signal(signal.SIGALRM, validation_alarm_handler)
signal.setitimer(signal.ITIMER_REAL, VALIDATION_TOTAL_TIMEOUT_SECONDS)


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


def repository_entry_identity(metadata, *, content_stable=False):
    identity = (metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode))
    if content_stable:
        identity += (
            metadata.st_size,
            metadata.st_mtime_ns,
            metadata.st_ctime_ns,
        )
    return identity


def bind_authoritative_repository():
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    root_fd = dotgit_fd = gitdir_fd = None
    try:
        root_fd = os.open(ROOT, directory_flags | nofollow)
        root_identity = repository_entry_identity(os.fstat(root_fd))
        if repository_entry_identity(os.stat(ROOT, follow_symlinks=False)) != root_identity:
            raise OSError("root identity changed while binding")
        gitdir_path = None
        dotgit_is_file = False
        try:
            dotgit_fd = os.open(
                ".git", directory_flags | nofollow, dir_fd=root_fd
            )
            gitdir_fd = os.dup(dotgit_fd)
        except NotADirectoryError:
            dotgit_is_file = True
            dotgit_fd = os.open(
                ".git", os.O_RDONLY | os.O_CLOEXEC | nofollow, dir_fd=root_fd
            )
            dotgit_before = os.fstat(dotgit_fd)
            if not stat.S_ISREG(dotgit_before.st_mode) or dotgit_before.st_size > 4096:
                raise OSError("invalid gitfile")
            chunks = []
            total = 0
            while True:
                chunk = os.read(dotgit_fd, min(4097 - total, 4096))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > 4096:
                    raise OSError("oversized gitfile")
            dotgit_after = os.fstat(dotgit_fd)
            if repository_entry_identity(
                dotgit_before, content_stable=True
            ) != repository_entry_identity(dotgit_after, content_stable=True):
                raise OSError("gitfile identity changed while binding")
            match = re.fullmatch(
                rb"gitdir: ([^\x00\r\n]+)\r?\n?", b"".join(chunks)
            )
            if match is None:
                raise OSError("invalid gitfile")
            gitdir_text = match.group(1).decode("utf-8", errors="strict")
            gitdir_path = (
                gitdir_text
                if os.path.isabs(gitdir_text)
                else os.path.normpath(os.path.join(ROOT, gitdir_text))
            )
            gitdir_fd = os.open(gitdir_path, directory_flags | nofollow)
        dotgit_identity = repository_entry_identity(
            os.fstat(dotgit_fd), content_stable=dotgit_is_file
        )
        gitdir_identity = repository_entry_identity(os.fstat(gitdir_fd))
        return {
            "root_fd": root_fd,
            "root_identity": root_identity,
            "dotgit_fd": dotgit_fd,
            "dotgit_identity": dotgit_identity,
            "dotgit_is_file": dotgit_is_file,
            "gitdir_fd": gitdir_fd,
            "gitdir_identity": gitdir_identity,
            "gitdir_path": gitdir_path,
        }
    except (OSError, UnicodeError):
        for descriptor in (gitdir_fd, dotgit_fd, root_fd):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass
        return None


def repository_identity_issue():
    binding = AUTHORITATIVE_REPOSITORY
    if binding is None:
        return "unavailable"
    try:
        if (
            repository_entry_identity(os.fstat(binding["root_fd"]))
            != binding["root_identity"]
            or repository_entry_identity(os.stat(ROOT, follow_symlinks=False))
            != binding["root_identity"]
        ):
            return "root"
        if repository_entry_identity(
            os.fstat(binding["dotgit_fd"]),
            content_stable=binding["dotgit_is_file"],
        ) != binding["dotgit_identity"]:
            return "gitdir"
        dotgit_path_identity = repository_entry_identity(
            os.stat(".git", dir_fd=binding["root_fd"], follow_symlinks=False),
            content_stable=binding["dotgit_is_file"],
        )
        if dotgit_path_identity != binding["dotgit_identity"]:
            return "gitdir"
        if (
            repository_entry_identity(os.fstat(binding["gitdir_fd"]))
            != binding["gitdir_identity"]
        ):
            return "gitdir"
        if binding["gitdir_path"] is not None and repository_entry_identity(
            os.stat(binding["gitdir_path"], follow_symlinks=False)
        ) != binding["gitdir_identity"]:
            return "gitdir"
    except OSError:
        return "root" if binding is not None else "unavailable"
    return None


AUTHORITATIVE_REPOSITORY = bind_authoritative_repository()


def read_confined_snapshot(path, boundary, label):
    relative = os.path.relpath(path, boundary)
    components = relative.split(os.sep)
    if (
        relative == os.pardir
        or relative.startswith(os.pardir + os.sep)
        or not components
        or any(component in ("", ".", "..") for component in components)
    ):
        add(f"input_path_escape:{label}")
        emit("ERROR", 2)
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    opened_directories = []
    file_descriptor = None
    try:
        if boundary == ROOT and AUTHORITATIVE_REPOSITORY is not None:
            current = os.dup(AUTHORITATIVE_REPOSITORY["root_fd"])
        else:
            current = os.open(boundary, directory_flags | nofollow)
        opened_directories.append(current)
        for component in components[:-1]:
            current = os.open(
                component,
                directory_flags | nofollow,
                dir_fd=current,
            )  # SECURITY_RULE:input_snapshot_openat
            opened_directories.append(current)
        file_descriptor = os.open(
            components[-1],
            os.O_RDONLY | os.O_CLOEXEC | nofollow,
            dir_fd=current,
        )
        before = os.fstat(file_descriptor)
        if not stat.S_ISREG(before.st_mode):
            add(f"input_not_regular:{label}")
            emit("ERROR", 2)
        if before.st_size > MAX_INPUT_BYTES:
            add(f"input_resource_limit:bytes:{label}")  # SECURITY_RULE:input_bytes
            emit("ERROR", 2)
        chunks = []
        total = 0
        while True:
            remaining_validation_time()
            chunk = os.read(file_descriptor, min(65536, MAX_INPUT_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_INPUT_BYTES:
                add(f"input_resource_limit:bytes:{label}")
                emit("ERROR", 2)
        after = os.fstat(file_descriptor)
        identity_before = (
            before.st_dev,
            before.st_ino,
            before.st_size,
            before.st_mtime_ns,
            before.st_ctime_ns,
        )
        identity_after = (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        )
        if identity_before != identity_after:
            add(f"input_identity_changed:{label}")  # SECURITY_RULE:input_snapshot_identity
            emit("ERROR", 2)
        return b"".join(chunks)
    except OSError:
        add(f"input_unavailable:{label}")
        emit("ERROR", 2)
    finally:
        if file_descriptor is not None:
            os.close(file_descriptor)
        for descriptor in reversed(opened_directories):
            os.close(descriptor)


def enforce_cardinality(document_set):
    requirements_document = document_set.get("requirements")
    receipt_document = document_set.get("receipt")
    requirement_count = 0
    if isinstance(requirements_document, dict) and isinstance(
        requirements_document.get("requirements"), dict
    ):
        requirement_count = max(
            requirement_count, len(requirements_document["requirements"])
        )
    if isinstance(receipt_document, dict) and isinstance(
        receipt_document.get("requirements"), dict
    ):
        requirement_count = max(requirement_count, len(receipt_document["requirements"]))
    if requirement_count > MAX_REQUIREMENTS:
        add("input_resource_limit:requirements")  # SECURITY_RULE:cardinality_requirements
        emit("ERROR", 2)

    source_records = (
        requirements_document.get("source_remarks", [])
        if isinstance(requirements_document, dict)
        else []
    )
    if isinstance(source_records, list) and len(source_records) > MAX_SOURCE_RECORDS:
        add("input_resource_limit:records")  # SECURITY_RULE:cardinality_records
        emit("ERROR", 2)

    evidence_keys = {
        "exact_source_quotes",
        "source_quote_digests",
        "enabling_changes",
        "visitor_visible_changes",
        "painted_matrix",
        "proposals",
    }
    evidence_count = 0
    signature_count = 0
    total_nodes = 0
    stack = list(document_set.values())
    while stack:
        remaining_validation_time()
        value = stack.pop()
        total_nodes += 1
        if total_nodes > MAX_TOTAL_NODES:
            add("input_resource_limit:nodes")
            emit("ERROR", 2)
        if isinstance(value, dict):
            for key, nested in value.items():
                if key == "signature":
                    signature_count += 1
                if key in evidence_keys and isinstance(nested, list):
                    evidence_count += len(nested)
                stack.append(nested)
        elif isinstance(value, list):
            if len(value) > MAX_CONTAINER_ITEMS:
                add("input_resource_limit:collection")
                emit("ERROR", 2)
            stack.extend(value)
    if evidence_count > MAX_EVIDENCE_RECORDS:
        add("input_resource_limit:evidence")  # SECURITY_RULE:cardinality_evidence
        emit("ERROR", 2)
    if signature_count > MAX_SIGNATURES:
        add("input_resource_limit:signatures")  # SECURITY_RULE:cardinality_signatures
        emit("ERROR", 2)


documents = {}
schemas = {}
for name in ("requirements", "receipt", "review"):
    try:
        document_bytes = read_confined_snapshot(
            DOCUMENT_PATHS[name], ROOT, name
        )
        document_text = document_bytes.decode("utf-8")
        loader = UniqueKeyLoader(document_text)
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
enforce_cardinality(documents)

for name in ("requirements", "receipt", "review"):
    try:
        schema_bytes = read_confined_snapshot(
            SCHEMA_PATHS[name], FRAMEWORK_ROOT, f"schema:{name}"
        )
        schemas[name] = json.loads(schema_bytes.decode("utf-8"))
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
        "platform_executables": {
            "Linux": "/usr/bin/openssl",
            "Darwin-arm64": "/opt/homebrew/opt/openssl@3/bin/openssl",
            "Darwin-x86_64": "/usr/local/opt/openssl@3/bin/openssl",
        },
        "resolution": "PLATFORM_PINNED_ABSOLUTE_PATH",
        "ambient_path": "PROHIBITED",
        "file_type": "REGULAR",
        "owner_policy": "ROOT_OR_MACOS_PACKAGE_MANAGER_OWNER",
        "group_or_other_writable": "PROHIBITED",
        "verification_success_exit_code": 0,
    }
    if schemas["requirements"].get("x-datarim-crypto-verifier-contract") != expected:
        add("crypto_verifier_contract_mismatch")
        return False
    try:
        metadata = os.stat(PINNED_OPENSSL)
    except OSError:
        add("missing_crypto_dependency:openssl3")
        return False
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid not in ({0} if PLATFORM == "Linux" else {0, os.geteuid()})
        or metadata.st_mode & 0o022
    ):
        add("untrusted_crypto_dependency:openssl3")
        return False
    try:
        allowed_paths = (
            {expected["platform_executables"]["Linux"]}
            if PLATFORM == "Linux"
            else {
                expected["platform_executables"]["Darwin-arm64"],
                expected["platform_executables"]["Darwin-x86_64"],
            }
        )
        if PINNED_OPENSSL not in allowed_paths:
            add("untrusted_crypto_dependency:openssl3")
            return False
        returncode, stdout, _stderr = run_bounded_process(
            [PINNED_OPENSSL, "version"], stdout_limit=4096, stderr_limit=4096
        )
    except (OSError, subprocess.SubprocessError):
        add("missing_crypto_dependency:openssl3")
        return False
    if returncode != 0 or re.match(rb"^OpenSSL 3\.", stdout) is None:
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
signed_prework_tasks_by_requirement = {}
signed_prework_epics_by_requirement = {}
signed_prework_knowledge_by_requirement = {}
signed_prework_started_by_requirement = {}

if len(sources) != len(requirements_doc["source_remarks"]):
    add("duplicate_id:source")
for source in requirements_doc["source_remarks"]:
    for assignment in source["prework_assignments"]:
        requirement_id = assignment["requirement_id"]
        signed_prework_tasks_by_requirement.setdefault(requirement_id, set()).add(
            assignment["task_id"]
        )
        signed_prework_epics_by_requirement.setdefault(requirement_id, set()).add(
            assignment["epic_id"]
        )
        signed_prework_knowledge_by_requirement.setdefault(requirement_id, set()).add(
            assignment["knowledge_selection_digest"]
        )
        signed_prework_started_by_requirement.setdefault(requirement_id, set()).add(
            assignment["implementation_started_at"]
        )
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


def primary_originating_review_record():
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
        "review_digest": origin["review_digest"],
        "authority_approval": origin["authority_approval"],
    }


def originating_review_payload(record):
    return {
        field: record[field]
        for field in (
            "review_id", "requirement_id", "delivery_receipt_id", "reviewer",
            "review_ref", "state", "observed_at", "evidence_ref",
        )
    }


def validate_originating_review_commitment(record):
    review_id = record["review_id"]
    approval = record["authority_approval"]
    expected_digest = sha256_digest(originating_review_payload(record))
    if record["review_digest"] != expected_digest:
        add(f"originating_review_digest_mismatch:{review_id}")  # SECURITY_RULE:review_digest
    if approval["approved_digest"] != record["review_digest"]:
        add(f"originating_review_approval_digest_mismatch:{review_id}")  # SECURITY_RULE:review_approved_digest
    if approval["approval_payload_digest"] != approval_payload_digest(approval):
        add(f"originating_review_approval_payload_digest_mismatch:{review_id}")  # SECURITY_RULE:review_approval_digest


def validate_originating_review_approval(record):
    review_id = record["review_id"]
    approval = record["authority_approval"]
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


def validate_originating_review_state(record, reviewed_at_value=None):
    review_id = record["review_id"]
    requirement_id = record["requirement_id"]
    observed_at = parse_time(record["observed_at"], f"timestamp:{review_id}:observed_at")
    reviewed_at = (
        parse_time(reviewed_at_value, f"timestamp:{review_id}:reviewed_at")
        if reviewed_at_value is not None
        else None
    )
    if observed_at is not None and reviewed_at is not None and observed_at > reviewed_at:
        add(f"originating_review_observed_after_reviewed_at:{review_id}")  # SECURITY_RULE:review_observed_at
    if record["state"] == "OPEN":
        add(f"parent_review_not_closed:{requirement_id}")  # SECURITY_RULE:review_state_open
    if record["state"] == "CHANGES_REQUESTED":
        add(f"parent_review_not_closed:{requirement_id}")  # SECURITY_RULE:review_state_changes


def validate_originating_review_inventory_manifest():
    manifest = review_doc["originating_review_inventory_manifest"]
    approval = manifest["authority_approval"]
    contract = schemas["review"]["x-datarim-originating-review-contract"]
    authority = contract["inventory_authority"]
    sorted_pairs = sorted(
        manifest["review_pairs"],
        key=lambda item: (item["review_id"], item["requirement_id"]),
    )
    expected_digest = sha256_digest({
        "delivery_receipt_id": manifest["delivery_receipt_id"],
        "review_pairs": sorted_pairs,
    })
    if manifest["review_pairs"] != sorted_pairs:
        add("originating_review_inventory_manifest_not_canonical")
    if manifest["inventory_digest"] != expected_digest:
        add("originating_review_inventory_manifest_digest_mismatch")  # SECURITY_RULE:review_manifest_digest
    if approval["approved_digest"] != manifest["inventory_digest"]:
        add("originating_review_inventory_manifest_approval_digest_mismatch")
    if approval["approval_payload_digest"] != approval_payload_digest(approval):
        add("originating_review_inventory_manifest_approval_payload_digest_mismatch")
    for field in ("authority_id", "authority_role", "key_id"):
        if approval[field] != authority[field]:
            add(f"originating_review_inventory_manifest_authority_mismatch:{field}")
    public_key = authority["public_key"]
    expected_fingerprint = "sha256:" + hashlib.sha256(
        base64.b64decode(public_key, validate=True)
    ).hexdigest()
    if authority["fingerprint"] != expected_fingerprint:
        add("originating_review_inventory_manifest_key_fingerprint_mismatch")
    if not verify_ed25519(
        approval["signature"], approval["approval_payload_digest"], public_key
    ):
        add("originating_review_inventory_manifest_signature_invalid")  # SECURITY_RULE:review_manifest_signature
    if manifest["delivery_receipt_id"] != receipt_doc["receipt_id"]:
        add("originating_review_inventory_manifest_receipt_mismatch")
    return sorted_pairs


def validate_originating_review():
    primary = primary_originating_review_record()
    validate_originating_review_commitment(primary)
    validate_originating_review_approval(primary)
    validate_originating_review_state(primary, review_doc["reviewed_at"])
    inventory = review_doc["originating_review_inventory"]
    expected_pairs = validate_originating_review_inventory_manifest()
    observed_pairs = []
    records_by_pair = {}
    review_ids = set()
    for record in inventory:
        requirement_id = record["requirement_id"]
        review_id = record["review_id"]
        pair = (review_id, requirement_id)
        observed_pairs.append({"review_id": review_id, "requirement_id": requirement_id})
        if pair in records_by_pair:
            add(f"originating_review_inventory_pair_duplicate:{review_id}:{requirement_id}")
        records_by_pair[pair] = record
        if review_id in review_ids:
            add(f"originating_review_id_duplicate:{review_id}")
        review_ids.add(review_id)
        validate_originating_review_commitment(record)
        validate_originating_review_approval(record)
        validate_originating_review_state(record)  # SECURITY_RULE:review_inventory_closure
        if record["delivery_receipt_id"] != receipt_doc["receipt_id"]:
            add(f"review_receipt_mismatch:{requirement_id}")
    observed_pairs = sorted(
        observed_pairs, key=lambda item: (item["review_id"], item["requirement_id"])
    )
    expected_pair_set = {
        (item["review_id"], item["requirement_id"]) for item in expected_pairs
    }
    if len(expected_pair_set) != len(expected_pairs):
        add("originating_review_inventory_manifest_pair_duplicate")
    observed_pair_set = {
        (item["review_id"], item["requirement_id"]) for item in observed_pairs
    }
    for review_id, requirement_id in sorted(expected_pair_set - observed_pair_set):
        add(f"originating_review_inventory_pair_missing:{review_id}:{requirement_id}")  # SECURITY_RULE:review_inventory_exact
    for review_id, requirement_id in sorted(observed_pair_set - expected_pair_set):
        add(f"originating_review_inventory_pair_extra:{review_id}:{requirement_id}")  # SECURITY_RULE:review_inventory_exact
    expected_requirements = set(requirements)
    manifested_requirements = {requirement_id for _, requirement_id in expected_pair_set}
    for requirement_id in sorted(expected_requirements - manifested_requirements):
        add(f"originating_review_inventory_missing:{requirement_id}")  # SECURITY_RULE:review_inventory_exact
    for requirement_id in sorted(manifested_requirements - expected_requirements):
        add(f"originating_review_inventory_extra:{requirement_id}")  # SECURITY_RULE:review_inventory_exact
    primary_pair = (primary["review_id"], primary["requirement_id"])
    primary_inventory_record = records_by_pair.get(primary_pair)
    if primary_inventory_record != primary:
        add(f"originating_review_primary_mismatch:{primary['requirement_id']}")  # SECURITY_RULE:review_inventory_primary


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
            "prework_assignments": sorted(
                source["prework_assignments"],
                key=lambda item: (
                    item["requirement_id"], item["task_id"], item["epic_id"]
                ),
            ),
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
        source_assignments = {
            assignment["requirement_id"]: assignment
            for assignment in source["prework_assignments"]
        }
        if len(source_assignments) != len(source["prework_assignments"]):
            add(f"source_prework_assignment_duplicate:{source_id}")  # SECURITY_RULE:source_prework_scope
        if set(source_assignments) != set(source["requirement_ids"]):
            add(f"source_prework_assignment_scope_mismatch:{source_id}")
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
            assignment = assertion["prework_assignment"]
            if (
                assignment["requirement_id"] != assertion["requirement_id"]
                or source_assignments.get(assertion["requirement_id"]) != assignment
            ):
                add(f"assertion_prework_assignment_mismatch:{assertion_id}")  # SECURITY_RULE:assertion_prework_binding
            task_match = re.fullmatch(
                r"task:([a-z][a-z0-9]{1,9}):[0-9]{4}", assignment["task_id"]
            )
            expected_epic = (
                f"epic:{task_match.group(1)}:0000" if task_match is not None else None
            )
            if assignment["epic_id"] != expected_epic:
                add(f"prework_task_epic_mismatch:{assertion_id}")  # SECURITY_RULE:prework_epic_derivation
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

        signed_tasks = signed_prework_tasks_by_requirement.get(requirement_id, set())
        if signed_tasks != {acceptance["implementation"]["task_id"]}:
            add(f"acceptance_prework_task_mismatch:{requirement_id}")  # SECURITY_RULE:acceptance_prework_binding
        expected_knowledge_digest = sha256_digest(acceptance["knowledge_selection"])
        if signed_prework_knowledge_by_requirement.get(requirement_id, set()) != {
            expected_knowledge_digest
        }:
            add(f"prework_knowledge_selection_mismatch:{requirement_id}")  # SECURITY_RULE:prework_knowledge_binding
        if signed_prework_started_by_requirement.get(requirement_id, set()) != {
            acceptance["implementation"]["started_at"]
        }:
            add(f"prework_implementation_started_at_mismatch:{requirement_id}")  # SECURITY_RULE:prework_started_at_binding

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


def _validate_source_history():
    deadline = min(
        VALIDATION_DEADLINE,
        time.monotonic() + SOURCE_HISTORY_TOTAL_TIMEOUT_SECONDS,
    )
    git_env = {
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
    }  # SECURITY_RULE:git_environment_sanitized
    binding = AUTHORITATIVE_REPOSITORY
    if binding is None:
        add("source_history_unavailable")
        return
    gitdir_fd_path = (
        f"/proc/self/fd/{binding['gitdir_fd']}"
        if PLATFORM == "Linux"
        else f"/dev/fd/{binding['gitdir_fd']}"
    )
    git_prefix = [
        PINNED_GIT,
        "-c", "core.attributesFile=/dev/null",
        "-c", "core.fsmonitor=false",
        "-c", "core.hooksPath=/dev/null",
        f"--git-dir={gitdir_fd_path}",
    ]
    resource_limited = False
    repository_identity_reported = False

    def resource_limit(reason):
        nonlocal resource_limited
        if not resource_limited:
            add(f"source_history_resource_limit:{reason}")
            resource_limited = True

    def repository_identity_valid():
        nonlocal repository_identity_reported
        issue = repository_identity_issue()
        if issue is None:
            return True
        if not repository_identity_reported:
            add(f"source_history_repository_identity_changed:{issue}")
            repository_identity_reported = True
        return False

    def terminate_process_group(process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except OSError:
            pass
        grace_deadline = min(deadline, time.monotonic() + 0.2)
        while time.monotonic() < grace_deadline:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            except OSError:
                break
            time.sleep(0.01)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except OSError:
            pass
        try:
            process.wait(timeout=0.2)
        except (subprocess.TimeoutExpired, OSError):
            pass

    def run_git(arguments, *, input_bytes=None, output_limit=SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES):
        if not repository_identity_valid():
            return None
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            resource_limit("deadline")
            return None
        if input_bytes is not None and len(input_bytes) > SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES:
            resource_limit("output_budget")
            return None
        process = None
        selector = selectors.DefaultSelector()
        stdout_buffer = bytearray()
        stderr_buffer = bytearray()
        input_offset = 0
        try:
            process = subprocess.Popen(
                [*git_prefix, *arguments],
                env=git_env,
                pass_fds=(binding["gitdir_fd"],),
                stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            for stream, label in ((process.stdout, "stdout"), (process.stderr, "stderr")):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, label)
            if process.stdin is not None:
                os.set_blocking(process.stdin.fileno(), False)
                selector.register(process.stdin, selectors.EVENT_WRITE, "stdin")

            while selector.get_map() or process.poll() is None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    resource_limit("deadline")  # SECURITY_RULE:source_history_total_deadline
                    terminate_process_group(process)
                    return None
                if not selector.get_map():
                    try:
                        process.wait(timeout=min(0.05, remaining))
                    except subprocess.TimeoutExpired:
                        continue
                    break
                for key, _ in selector.select(timeout=min(0.05, remaining)):
                    stream = key.fileobj
                    label = key.data
                    if label == "stdin":
                        try:
                            written = os.write(stream.fileno(), input_bytes[input_offset:input_offset + 65536])
                        except (BrokenPipeError, OSError):
                            written = 0
                            selector.unregister(stream)
                            stream.close()
                        input_offset += written
                        if input_offset >= len(input_bytes) and not stream.closed:
                            selector.unregister(stream)
                            stream.close()
                        continue

                    target = stdout_buffer if label == "stdout" else stderr_buffer
                    limit = output_limit if label == "stdout" else SOURCE_HISTORY_MAX_STDERR_BYTES
                    try:
                        chunk = os.read(stream.fileno(), min(65536, max(1, limit - len(target) + 1)))
                    except BlockingIOError:
                        continue
                    except OSError:
                        terminate_process_group(process)
                        return None
                    if not chunk:
                        selector.unregister(stream)
                        stream.close()
                        continue
                    if len(target) + len(chunk) > limit:
                        if label == "stdout":
                            resource_limit("output_budget")  # SECURITY_RULE:source_history_stdout_stream_cap
                        else:
                            resource_limit("output_budget")  # SECURITY_RULE:source_history_stderr_stream_cap
                        terminate_process_group(process)
                        return None
                    target.extend(chunk)

            returncode = process.wait(timeout=max(0.001, deadline - time.monotonic()))
            if not repository_identity_valid():
                return None
            return returncode, bytes(stdout_buffer)
        except subprocess.TimeoutExpired:
            resource_limit("deadline")
            if process is not None:
                terminate_process_group(process)
            return None
        except (OSError, subprocess.SubprocessError):
            if process is not None:
                terminate_process_group(process)
            return None
        finally:
            selector.close()
            if process is not None:
                for stream in (process.stdin, process.stdout, process.stderr):
                    if stream is not None and not stream.closed:
                        stream.close()

    try:
        git_metadata = os.lstat(PINNED_GIT)
    except OSError:
        add("source_history_untrusted_git")
        return
    if (
        not os.path.isabs(PINNED_GIT)
        or not stat.S_ISREG(git_metadata.st_mode)
        or not os.access(PINNED_GIT, os.X_OK)
    ):
        add("source_history_untrusted_git")
        return
    version = run_git(["--version"])
    if version is None:
        if not resource_limited:
            add("source_history_untrusted_git")
        return
    try:
        version_stdout = version[1].decode("ascii", errors="strict")
    except UnicodeError:
        add("source_history_untrusted_git")
        return
    if version[0] != 0 or re.fullmatch(r"git version [0-9]+\.[0-9]+(?:\.[0-9]+)?\n?", version_stdout) is None:
        add("source_history_untrusted_git")  # SECURITY_RULE:git_binary_pinned
        return

    def reject_snapshot(context):
        add(f"source_history_parse:{context}")  # SECURITY_RULE:source_history_parse_closed
        return None

    def source_records(snapshot, context):
        if not isinstance(snapshot, dict):
            return reject_snapshot(context)
        records = snapshot.get("source_remarks")
        if not isinstance(records, list):
            return reject_snapshot(context)
        by_digest = {}
        source_ids = set()
        for record in records:
            if not isinstance(record, dict):
                return reject_snapshot(context)
            source_id = record.get("source_id")
            digest = record.get("source_digest")
            supersedes = record.get("supersedes_source_digest")
            if (
                not isinstance(source_id, str)
                or re.fullmatch(r"source-[0-9]{4}", source_id) is None
                or not isinstance(digest, str)
                or re.fullmatch(r"sha256:[0-9a-f]{64}", digest) is None
                or (
                    supersedes is not None
                    and (
                        not isinstance(supersedes, str)
                        or re.fullmatch(r"sha256:[0-9a-f]{64}", supersedes) is None
                    )
                )
            ):
                return reject_snapshot(context)
            try:
                jcs_bytes(record)
            except (TypeError, UnicodeError, ValueError):
                return reject_snapshot(context)
            if digest in by_digest or source_id in source_ids:
                return reject_snapshot(context)
            by_digest[digest] = record
            source_ids.add(source_id)
        return by_digest

    probe = run_git(["rev-parse", "--git-dir"])
    try:
        probe_stdout = probe[1].decode("utf-8", errors="strict") if probe is not None else ""
    except UnicodeError:
        probe_stdout = ""
    if (
        probe is None
        or probe[0] != 0
        or not probe_stdout.strip()
    ):
        if not resource_limited:
            add("source_history_unavailable")  # SECURITY_RULE:source_history_repo_required
        return
    shallow = run_git(["rev-parse", "--is-shallow-repository"])
    try:
        shallow_stdout = shallow[1].decode("ascii", errors="strict").strip() if shallow is not None else ""
    except UnicodeError:
        shallow_stdout = ""
    if shallow is None or shallow[0] != 0 or shallow_stdout not in {"true", "false"}:
        if not resource_limited:
            add("source_history_unavailable")
        return
    if shallow_stdout == "true":
        add("source_history_shallow_repository")  # SECURITY_RULE:source_history_shallow_rejected
        return
    graft_path_result = run_git(["rev-parse", "--git-path", "info/grafts"])
    try:
        graft_stdout = graft_path_result[1].decode("utf-8", errors="strict").strip() if graft_path_result is not None else ""
    except UnicodeError:
        graft_stdout = ""
    if graft_path_result is None or graft_path_result[0] != 0 or not graft_stdout:
        if not resource_limited:
            add("source_history_unavailable")
        return
    graft_path = graft_stdout
    if not os.path.isabs(graft_path):
        graft_path = os.path.join(gitdir_fd_path, graft_path)
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
    history = run_git([
        "log",
        f"--max-count={SOURCE_HISTORY_MAX_COMMITS + 1}",
        "--format=%H",
        "--follow",
        "--",
        relative,
    ])
    try:
        history_stdout = history[1].decode("ascii", errors="strict") if history is not None else ""
    except UnicodeError:
        history_stdout = ""
    if history is None or history[0] != 0 or not history_stdout.strip():
        if not resource_limited:
            add("source_history_unavailable")  # SECURITY_RULE:source_history_document_required
        return
    commits = history_stdout.splitlines()
    if len(commits) > SOURCE_HISTORY_MAX_COMMITS:
        resource_limit("commit_budget")  # SECURITY_RULE:source_history_commit_budget
        return
    if any(re.fullmatch(r"[0-9a-f]{40,64}", commit) is None for commit in commits):
        add("source_history_unavailable")
        return
    current_records = source_records(requirements_doc, "current")
    if current_records is None:
        return
    snapshots = [(requirements_doc, current_records)]

    specs = [f"{commit}:{relative}" for commit in commits]
    spec_input = ("\n".join(specs) + "\n").encode("utf-8")
    info = run_git(
        ["cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)"],
        input_bytes=spec_input,
    )
    if info is None or info[0] != 0:
        if not resource_limited:
            for commit in commits:
                reject_snapshot(commit)
        return
    try:
        info_lines = info[1].decode("ascii", errors="strict").splitlines()
    except UnicodeError:
        for commit in commits:
            reject_snapshot(commit)
        return
    if len(info_lines) != len(commits):
        for commit in commits:
            reject_snapshot(commit)
        return
    expected_objects = []
    total_blob_bytes = 0
    for commit, line in zip(commits, info_lines):
        match = re.fullmatch(r"([0-9a-f]{40,64}) blob ([0-9]+)", line)
        if match is None:
            reject_snapshot(commit)
            expected_objects.append(None)
            continue
        size = int(match.group(2))
        total_blob_bytes += size
        expected_objects.append((match.group(1), size))
    if any(expected is None for expected in expected_objects):
        return
    if total_blob_bytes > SOURCE_HISTORY_MAX_TOTAL_BLOB_BYTES:
        resource_limit("output_budget")  # SECURITY_RULE:source_history_output_budget
        return

    batch = run_git(
        ["cat-file", "--batch"],
        input_bytes=spec_input,
        output_limit=SOURCE_HISTORY_MAX_TOTAL_BLOB_BYTES + SOURCE_HISTORY_MAX_CONTROL_OUTPUT_BYTES,
    )
    if batch is None or batch[0] != 0:
        if not resource_limited:
            for commit in commits:
                reject_snapshot(commit)
        return
    cursor = 0
    blobs = []
    for commit, expected in zip(commits, expected_objects):
        newline = batch[1].find(b"\n", cursor)
        if newline < 0 or expected is None:
            reject_snapshot(commit)
            blobs.append(None)
            continue
        try:
            header = batch[1][cursor:newline].decode("ascii", errors="strict")
        except UnicodeError:
            reject_snapshot(commit)
            blobs.append(None)
            cursor = newline + 1
            continue
        header_match = re.fullmatch(r"([0-9a-f]{40,64}) blob ([0-9]+)", header)
        if header_match is None or (header_match.group(1), int(header_match.group(2))) != expected:
            reject_snapshot(commit)
            blobs.append(None)
            cursor = newline + 1
            continue
        start = newline + 1
        end = start + expected[1]
        if end >= len(batch[1]) or batch[1][end:end + 1] != b"\n":
            reject_snapshot(commit)
            blobs.append(None)
            cursor = len(batch[1])
            continue
        blobs.append(batch[1][start:end])
        cursor = end + 1
    if cursor != len(batch[1]):
        for commit in commits:
            reject_snapshot(commit)
        return

    for commit, blob_bytes in zip(commits, blobs):
        if blob_bytes is None:
            continue
        try:
            prior = yaml.load(blob_bytes.decode("utf-8", errors="strict"), Loader=UniqueKeyLoader)
        except (UnicodeError, yaml.YAMLError):
            reject_snapshot(commit)
            continue
        prior_records = source_records(prior, commit)
        if prior_records is None:
            continue
        if prior != snapshots[-1][0]:
            snapshots.append((prior, prior_records))
    for (_, new_by_digest), (_, old_by_digest) in zip(snapshots, snapshots[1:]):
        for digest, prior in old_by_digest.items():
            if digest not in new_by_digest:
                add(f"source_history_prior_digest_deleted:{digest}")
            elif new_by_digest[digest] != prior:
                add(f"source_history_prior_record_mutated:{prior['source_id']}")  # SECURITY_RULE:source_history
        for digest, source in new_by_digest.items():
            superseded = source.get("supersedes_source_digest")
            if digest not in old_by_digest and superseded is not None and superseded not in old_by_digest:
                add(f"source_history_correction_not_linked:{source['source_id']}")


def validate_source_history():
    try:
        _validate_source_history()
    finally:
        issue = repository_identity_issue()
        if issue not in (None, "unavailable"):
            finding = f"source_history_repository_identity_changed:{issue}"
            if finding not in findings:
                add(finding)  # SECURITY_RULE:source_history_repository_identity


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
    if {delta["task_id"]} != signed_prework_tasks_by_requirement.get(requirement_id, set()):
        add(f"receipt_prework_task_mismatch:{requirement_id}")  # SECURITY_RULE:receipt_prework_task_binding
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


def validate_u4_nonblank_fields(requirement_id, chain):
    values = []
    selected = chain["selected_knowledge"]
    for category in (
        "roles", "skills", "blueprints", "constraints", "policies", "success_criteria"
    ):
        for index, item in enumerate(selected[category]):
            values.extend((
                (f"selected_knowledge.{category}[{index}].id", item["id"]),
                (f"selected_knowledge.{category}[{index}].revision", item["revision"]),
            ))
    delta = chain["implementation_delta"]
    for category in ("enabling_changes", "visitor_visible_changes"):
        for index, item in enumerate(delta[category]):
            values.extend((
                (f"implementation_delta.{category}[{index}].description", item["description"]),
                (f"implementation_delta.{category}[{index}].artifact_ref", item["artifact_ref"]),
            ))
    for colour in ("red", "green"):
        evidence = chain["red_green"][colour]
        values.extend((
            (f"red_green.{colour}.command", evidence["command"]),
            (f"red_green.{colour}.evidence_ref", evidence["evidence_ref"]),
        ))
    for edge in ("merged_revision", "deployed_revision"):
        values.append((f"{edge}.evidence_ref", chain[edge]["evidence_ref"]))
    live = chain["live_evidence"]
    values.extend((
        ("live_evidence.owner", live["owner"]),
        ("live_evidence.evidence_ref", live["evidence_ref"]),
    ))
    if "not_applicable_reason" in live:
        values.append(("live_evidence.not_applicable_reason", live["not_applicable_reason"]))
    for index, cell in enumerate(live["painted_matrix"]):
        values.append((f"live_evidence.painted_matrix[{index}].evidence_ref", cell["evidence_ref"]))
    disposition = chain["customer_disposition"]
    values.extend((
        ("customer_disposition.evidence_ref", disposition["evidence_ref"]),
        ("customer_disposition.authority_approval.evidence_ref", disposition["authority_approval"]["evidence_ref"]),
    ))
    if "note" in disposition:
        values.append(("customer_disposition.note", disposition["note"]))
    for path, value in values:
        if not value.strip():
            add(f"u4_nonblank_required:{requirement_id}:{path}")  # SECURITY_RULE:u4_nonblank


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


def validate_epic_identity_binding(receipt_epics, review_epics, signed_epics):
    canonical_epics = set(signed_epics)

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
source-prework-assignment-canonical-signed source-prework-assignment-requirement-set-exact
tier1-assertion-canonical-digest-valid tier1-assertion-approval-digest-equals-assertion-digest
tier1-assertion-approval-payload-canonical-digest-valid tier1-assertion-signature-valid
tier1-assertion-signature-over-approval-payload-digest-valid tier1-assertion-approval-key-known
tier1-assertion-approval-key-authority-id-equal tier1-assertion-approval-key-role-authorized
tier1-assertion-approval-key-active tier1-assertion-approval-key-valid-at-approval
tier1-assertion-prework-assignment-canonical-signed
tier1-assertion-prework-assignment-equals-source
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
acceptance-task-equals-signed-prework-assignment prework-task-epic-canonical
prework-knowledge-selection-digest-equals-acceptance
prework-implementation-started-at-equals-acceptance
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
receipt-task-equals-signed-prework-assignment
receipt-epic-parent-equals-signed-prework-assignment
originating-review-receipt-id-equals-top-receipt-id
originating-review-requirement-set-transitively-bound-by-disposition
originating-review-inventory-manifest-authenticated
originating-review-inventory-pair-set-exact
originating-review-inventory-requirement-coverage-complete
originating-review-canonical-digest-valid
originating-review-approval-digest-equals-review-digest
originating-review-approval-payload-canonical-digest-valid
originating-review-signature-valid originating-review-approval-key-known
originating-review-approval-key-authority-id-equal
originating-review-approval-key-role-authorized originating-review-approval-key-active
originating-review-approval-key-valid-at-approval
originating-review-observed-at-not-after-reviewed-at
originating-review-task-parent-equals-signed-prework-assignment
originating-review-epic-parent-equals-signed-prework-assignment
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
        elif "prework" in identifier:
            requirement_map[identifier] = validate_requirements_contract
        elif identifier.startswith("supersession-"):
            requirement_map[identifier] = check_supersession_cycles
    for identifier in receipt_ids:
        if identifier in (
            "receipt-epic-parent-equals-signed-prework-assignment",
            "originating-review-epic-parent-equals-signed-prework-assignment",
        ):
            receipt_map[identifier] = validate_epic_identity_binding
        elif identifier == "receipt-task-equals-signed-prework-assignment":
            receipt_map[identifier] = validate_implementation_delta_edge
        elif identifier == "originating-review-task-parent-equals-signed-prework-assignment":
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
    validate_u4_nonblank_fields(requirement_id, chain)  # U4_RULE:nonblank
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
signed_prework_tasks = {
    task_id
    for task_ids in signed_prework_tasks_by_requirement.values()
    for task_id in task_ids
}
signed_prework_epics = {
    epic_id
    for epic_ids in signed_prework_epics_by_requirement.values()
    for epic_id in epic_ids
}
receipt_sets = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "requirement_set"
}
expected_task_links = signed_prework_tasks
review_links = {(link["relation"], link["id"]) for link in review_doc["parent_links"]}
review_epics = {identifier for relation, identifier in review_links if relation == "epic"}
review_tasks = {identifier for relation, identifier in review_links if relation == "task"}
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
    receipt_epics, review_epics, signed_prework_epics
)
if not receipt_epics:
    add("dangling_parent_ref:epic")
if receipt_tasks != expected_task_links:
    add("parent_link_set_mismatch:task")  # SECURITY_RULE:receipt_prework_parent_binding
if review_tasks != expected_task_links:
    add("review_task_identity_mismatch")  # SECURITY_RULE:review_prework_task_binding
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
validator_status=$?
set -e

validate_text_response() {
    local first_line decision_field stage_field task_field status_field findings_field epic_field extra
    local decision_value findings_value line recomputed_findings=''
    IFS= read -r first_line <"$validator_output" || return 1
    IFS=' ' read -r decision_field stage_field task_field status_field epic_field findings_field extra <<<"$first_line"
    [[ -z "${extra:-}" ]] || return 1
    [[ "$decision_field" == decision=MET || "$decision_field" == decision=NOT_MET \
        || "$decision_field" == decision=ERROR ]] || return 1
    decision_value="${decision_field#decision=}"
    [[ "$stage_field" == "stage=${stage}" && "$task_field" == "task=${task}" ]] || return 1
    [[ "$status_field" == "status=${decision_value}" ]] || return 1
    findings_value="${findings_field#findings=}"
    [[ "$findings_field" == findings=* ]] || return 1
    [[ "$epic_field" == epic_status=MET || "$epic_field" == epic_status=NOT_MET ]] || return 1
    while IFS= read -r line; do
        [[ "$line" == finding=?* && "$line" != *[$'\001'-$'\037'$'\177']* ]] || return 1
        if [[ -n "$recomputed_findings" ]]; then
            recomputed_findings+=','
        fi
        recomputed_findings+="${line#finding=}"
    done < <(/usr/bin/tail -n +2 -- "$validator_output")
    [[ "$recomputed_findings" == "$findings_value" ]] || return 1
    [[ ("$decision_value" == MET && "$validator_status" -eq 0) \
        || ("$decision_value" == NOT_MET && "$validator_status" -eq 1) \
        || ("$decision_value" == ERROR && "$validator_status" -eq 2) ]]
}

validator_output_size() {
    case "$platform" in
        Linux) /usr/bin/stat -c '%s' "$validator_output" 2>/dev/null ;;
        Darwin) /usr/bin/stat -f '%z' "$validator_output" 2>/dev/null ;;
    esac
}

validate_json_response() {
    run_trusted_python_stdlib "${python_isolation_args[@]}" - "$validator_output" "$task" "$stage" "$validator_status" <<'PY'
import json
import sys

path, task, stage, raw_status = sys.argv[1:]
with open(path, "rb") as handle:
    raw = handle.read(1048577)
if not raw or len(raw) > 1048576 or raw.count(b"\n") != 1 or not raw.endswith(b"\n"):
    raise SystemExit(1)
try:
    document = json.loads(raw)
except (UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
decision = document.get("decision") if isinstance(document, dict) else None
expected_keys = {"decision", "epic_status", "findings", "stage", "status", "task"}
valid = (
    isinstance(document, dict)
    and set(document) == expected_keys
    and decision in {"MET", "NOT_MET", "ERROR"}
    and document["status"] == decision
    and document["epic_status"] in {"MET", "NOT_MET"}
    and document["task"] == task
    and document["stage"] == stage
    and isinstance(document["findings"], list)
    and all(isinstance(item, str) for item in document["findings"])
    and {"MET": 0, "NOT_MET": 1, "ERROR": 2}[decision] == int(raw_status)
)
raise SystemExit(0 if valid else 1)
PY
}

response_valid=false
output_size="$(validator_output_size || true)"
if [[ "$platform" == Darwin && ! -s "$validator_output" && "$validator_status" -ne 0 ]]; then
    emit_config_error 'untrusted_python_runtime'
    exit 2
fi
if [[ -s "$validator_output" && "$output_size" =~ ^[0-9]+$ && "$output_size" -le 1048576 ]]; then
    if [[ "$format" == json ]]; then
        if validate_json_response; then
            response_valid=true
        fi
    elif validate_text_response; then
        response_valid=true
    fi
fi
if [[ "$response_valid" != true ]]; then
    emit_config_error 'invalid_validator_response'
    exit 2
fi
/usr/bin/cat -- "$validator_output"
exit "$validator_status"

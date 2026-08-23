#!/usr/bin/env bash
set -euo pipefail

python_bin="${1:-}"
if [[ "$python_bin" != /* || ! -x "$python_bin" || -d "$python_bin" ]]; then
    printf 'runtime_preflight=ERROR reason=invalid_candidate\n' >&2
    exit 2
fi

platform="$(/usr/bin/uname -s)"
stat_identity() {
    case "$platform" in
        Linux) /usr/bin/stat -L -c '%d|%i|%u|%a|%F' "$1" ;;
        Darwin) /usr/bin/stat -L -f '%d|%i|%u|%Lp|%HT' "$1" ;;
        *) return 2 ;;
    esac
}

secure_root_path() {
    local candidate="$1" required_root="$2" final_kind="$3"
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
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
        current="${current}/${component}"
        metadata="$(stat_identity "$current")"
        IFS='|' read -r _ _ uid mode type <<<"$metadata"
        [[ "$uid" == 0 && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
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

diagnose_path() {
    local label="$1" candidate="$2" current='' component metadata
    local -a components=()
    printf 'runtime_preflight_%s_path=%s\n' "$label" "$candidate"
    [[ "$candidate" == /* ]] || return 0
    IFS='/' read -r -a components <<<"${candidate#/}"
    for component in "${components[@]}"; do
        current="${current}/${component}"
        metadata="$(stat_identity "$current" 2>/dev/null || printf missing)"
        printf 'runtime_preflight_%s_component=%s identity=%s\n' "$label" "$current" "$metadata"
    done
}

anchor='/usr/bin/python3'
candidate_identity="$(stat_identity "$python_bin")"
anchor_identity="$(stat_identity "$anchor")"
printf 'runtime_preflight_candidate=%s\n' "$candidate_identity"
printf 'runtime_preflight_anchor=%s\n' "$anchor_identity"
[[ "$candidate_identity" == "$anchor_identity" ]] || {
    printf 'runtime_preflight=ERROR reason=candidate_anchor_identity_mismatch\n' >&2
    exit 2
}

developer_root=''
if [[ "$platform" == Darwin ]]; then
    active_developer_root="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin /usr/bin/xcode-select -p)"
    diagnose_path active_developer "$active_developer_root"
    developer_root='/Library/Developer/CommandLineTools'
    diagnose_path selected_developer "$developer_root"
    secure_root_path "$developer_root" '' directory
    printf 'runtime_preflight_developer_root=%s\n' "$developer_root"
fi
if [[ "$platform" == Darwin ]]; then
    runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        DEVELOPER_DIR="$developer_root" \
        "$anchor" -I -c 'import sys; print(sys.executable)')"
    resolver_version="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        DEVELOPER_DIR="$developer_root" \
        "$anchor" -I -c 'import sys; print(f"{sys.version_info.major}|{sys.version_info.minor}")')"
else
    runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        "$anchor" -I -c 'import sys; print(sys.executable)')"
    resolver_version="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \
        "$anchor" -I -c 'import sys; print(f"{sys.version_info.major}|{sys.version_info.minor}")')"
fi
diagnose_path resolved_runtime "$runtime_path"
secure_root_path "$runtime_path" "$developer_root" file
runtime_identity="$(stat_identity "$runtime_path")"
expected_prefix="${python_bin%/bin/python}"
probe_program='
import os
import sys
from importlib import metadata as importlib_metadata
import jsonschema
import rfc3339_validator
import yaml
import cryptography

metadata = os.stat(sys.executable)
dependencies = "ok" if "date-time" in jsonschema.FormatChecker().checkers else "missing"
expected_prefix = sys.argv[1]
assert sys.prefix == expected_prefix, (sys.prefix, expected_prefix)
assert sys.base_prefix != sys.prefix, (sys.base_prefix, sys.prefix)
expected_versions = {
    "cryptography": "43.0.3",
    "jsonschema": "4.23.0",
    "rfc3339-validator": "0.1.4",
    "PyYAML": "6.0.2",
}
for distribution, version in expected_versions.items():
    assert importlib_metadata.version(distribution) == version, distribution
for module in (cryptography, jsonschema, rfc3339_validator, yaml):
    origin = os.path.realpath(module.__file__)
    assert os.path.commonpath((origin, expected_prefix)) == expected_prefix, origin
print(f"{metadata.st_dev}|{metadata.st_ino}|{sys.implementation.name}|{sys.version_info.major}|{sys.version_info.minor}|{dependencies}|{sys.prefix}|{sys.base_prefix}")
'
if [[ "$platform" == Darwin ]]; then
    probe="$(/usr/bin/env -i LC_ALL=C __PYVENV_LAUNCHER__="$python_bin" \
        "$runtime_path" -I -c "$probe_program" "$expected_prefix")"
else
    probe="$(/usr/bin/env -i LC_ALL=C "$python_bin" -I -c "$probe_program" "$expected_prefix")"
fi
IFS='|' read -r probe_device probe_inode probe_implementation probe_major probe_minor \
    probe_dependencies probe_prefix probe_base_prefix <<<"$probe"
IFS='|' read -r resolver_major resolver_minor <<<"$resolver_version"
IFS='|' read -r runtime_device runtime_inode _ <<<"$runtime_identity"
printf 'runtime_preflight_runtime=%s path=%s\n' "$runtime_identity" "$runtime_path"
printf 'runtime_preflight_probe=%s\n' "$probe"

[[ "$probe_device" == "$runtime_device" && "$probe_inode" == "$runtime_inode" \
    && "$probe_implementation" == cpython && "$probe_major" == 3 \
    && "$probe_major" == "$resolver_major" && "$probe_minor" == "$resolver_minor" \
    && "$probe_minor" =~ ^[0-9]+$ && "$probe_dependencies" == ok \
    && "$probe_prefix" == "$expected_prefix" && "$probe_base_prefix" != "$probe_prefix" ]] || {
    printf 'runtime_preflight=ERROR reason=runtime_or_dependency_mismatch\n' >&2
    exit 2
}
printf 'runtime_preflight=OK\n'

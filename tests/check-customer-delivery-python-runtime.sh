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
IFS='|' read -r resolver_major resolver_minor <<<"$resolver_version"
expected_site="${expected_prefix}/lib/python${resolver_major}.${resolver_minor}/site-packages"
[[ -d "$expected_site" && ! -L "$expected_site" ]] || {
    printf 'runtime_preflight=ERROR reason=invalid_site_packages\n' >&2
    exit 2
}
for pth_file in "$expected_site"/*.pth; do
    if [[ -e "$pth_file" || -L "$pth_file" ]]; then
        printf 'runtime_preflight=ERROR reason=untrusted_pth_file path=%s\n' "$pth_file" >&2
        exit 2
    fi
done
site_identity="$(stat_identity "$expected_site")"
IFS='|' read -r site_device site_inode _ <<<"$site_identity"
original_cwd="$PWD"
probe_program='
import os
import sys
from importlib import metadata as importlib_metadata
from importlib import util as importlib_util

expected_prefix = sys.argv[1]
runtime_path = sys.argv[2]
expected_executable = sys.argv[3]
original_cwd = os.path.realpath(sys.argv[4])
probe_platform = sys.argv[5]
expected_site = os.path.realpath(sys.argv[6])
print(f"runtime_preflight_child_executable={sys.executable} prefix={sys.prefix} base_prefix={sys.base_prefix} path={sys.path}", file=sys.stderr)
if probe_platform == "Darwin":
    assert sys.executable == runtime_path, (sys.executable, runtime_path)
    assert sys.prefix == sys.base_prefix, (sys.prefix, sys.base_prefix)
    assert os.getcwd() == "/", os.getcwd()
    assert sys.path[0].startswith("/dev/fd/"), sys.path
else:
    assert sys.executable == expected_executable, (sys.executable, expected_executable)
    assert sys.prefix == expected_prefix, (sys.prefix, expected_prefix)
    assert sys.base_prefix != sys.prefix, (sys.base_prefix, sys.prefix)
for entry in sys.path:
    resolved = os.path.realpath(entry or os.getcwd())
    assert resolved != original_cwd and not resolved.startswith(original_cwd + os.sep), resolved
for module_name in ("cryptography", "jsonschema", "rfc3339_validator", "yaml"):
    spec = importlib_util.find_spec(module_name)
    assert spec is not None and spec.origin is not None, module_name
    if probe_platform == "Darwin":
        assert spec.origin.startswith(sys.path[0].rstrip("/") + "/"), spec.origin
    else:
        resolved_origin = os.path.realpath(spec.origin)
        assert os.path.commonpath((resolved_origin, expected_site)) == expected_site, spec.origin
import jsonschema
import rfc3339_validator
import yaml
import cryptography

metadata = os.stat(runtime_path)
dependencies = "ok" if "date-time" in jsonschema.FormatChecker().checkers else "missing"
expected_versions = {
    "cryptography": "43.0.3",
    "jsonschema": "4.23.0",
    "rfc3339-validator": "0.1.4",
    "PyYAML": "6.0.2",
}
for distribution, version in expected_versions.items():
    assert importlib_metadata.version(distribution) == version, distribution
for module in (cryptography, jsonschema, rfc3339_validator, yaml):
    origin = module.__file__
    if probe_platform == "Darwin":
        assert origin.startswith(sys.path[0].rstrip("/") + "/"), origin
    else:
        resolved_origin = os.path.realpath(origin)
        assert os.path.commonpath((resolved_origin, expected_site)) == expected_site, origin
print(f"{metadata.st_dev}|{metadata.st_ino}|{sys.implementation.name}|{sys.version_info.major}|{sys.version_info.minor}|{dependencies}|{sys.prefix}|{sys.base_prefix}")
'
if [[ "$platform" == Darwin ]]; then
    bootstrap_program=$'import importlib.metadata,importlib.util,os,sys\nsite_path=sys.argv[1]\nexpected_device=int(sys.argv[2])\nexpected_inode=int(sys.argv[3])\nflags=os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW\nsite_fd=os.open(site_path, flags)\nmetadata=os.fstat(site_fd)\nassert (metadata.st_dev, metadata.st_ino)==(expected_device, expected_inode)\nassert not any(name.endswith(".pth") for name in os.listdir(site_fd))\nbound_site=f"/dev/fd/{site_fd}"\nassert os.path.isdir(bound_site)\npending=[bound_site]\nscanned=0\nwhile pending:\n current=pending.pop()\n with os.scandir(current) as entries:\n  for entry in entries:\n   scanned+=1\n   assert scanned<=20000\n   assert not entry.is_symlink()\n   if entry.is_dir(follow_symlinks=False):\n    pending.append(entry.path)\nsys.path.insert(0, bound_site)\nprogram=sys.argv[4]\nsys.argv=["-c"]+sys.argv[5:]\nexec(compile(program, "<string>", "exec"), globals(), globals())'
    probe="$(/usr/bin/env -i LC_ALL=C \
        /bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash \
        "$python_bin" "$runtime_path" -I -S -c "$bootstrap_program" \
        "$expected_site" "$site_device" "$site_inode" "$probe_program" \
        "$expected_prefix" "$runtime_path" \
        "$python_bin" "$original_cwd" "$platform" "$expected_site")"
else
    probe="$(/usr/bin/env -i LC_ALL=C /bin/bash -p -c \
        'exec -a "$1" "$2" "${@:3}"' bash \
        "$python_bin" "$runtime_path" -I -c "$probe_program" \
        "$expected_prefix" "$runtime_path" "$python_bin" "$original_cwd" "$platform" "$expected_site")"
fi
IFS='|' read -r probe_device probe_inode probe_implementation probe_major probe_minor \
    probe_dependencies probe_prefix probe_base_prefix <<<"$probe"
IFS='|' read -r runtime_device runtime_inode _ <<<"$runtime_identity"
printf 'runtime_preflight_runtime=%s path=%s\n' "$runtime_identity" "$runtime_path"
printf 'runtime_preflight_site=%s path=%s\n' "$site_identity" "$expected_site"
printf 'runtime_preflight_probe=%s\n' "$probe"

[[ "$(stat_identity "$runtime_path")" == "$runtime_identity" \
    && "$(stat_identity "$expected_site")" == "$site_identity" \
    && "$probe_device" == "$runtime_device" && "$probe_inode" == "$runtime_inode" \
    && "$probe_implementation" == cpython && "$probe_major" == 3 \
    && "$probe_major" == "$resolver_major" && "$probe_minor" == "$resolver_minor" \
    && "$probe_minor" =~ ^[0-9]+$ && "$probe_dependencies" == ok \
    && (("$platform" == Darwin && "$probe_prefix" == "$probe_base_prefix") \
        || ("$platform" != Darwin && "$probe_prefix" == "$expected_prefix" \
            && "$probe_base_prefix" != "$probe_prefix")) ]] || {
    printf 'runtime_preflight=ERROR reason=runtime_or_dependency_mismatch\n' >&2
    exit 2
}
printf 'runtime_preflight=OK\n'

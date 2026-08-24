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
late_import_cwd="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/customer-delivery-late-import.XXXXXX")"
trap '/bin/rm -rf -- "$late_import_cwd"' EXIT
printf '%s\n' 'raise RuntimeError("HOSTILE_LATE_IMPORT_EXECUTED")' \
    >"${late_import_cwd}/customer_delivery_late_shadow.py"
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
late_import_cwd = os.path.realpath(sys.argv[7])
print(f"runtime_preflight_child_executable={sys.executable} prefix={sys.prefix} base_prefix={sys.base_prefix} path={sys.path}", file=sys.stderr)
if probe_platform == "Darwin":
    assert sys.executable == runtime_path, (sys.executable, runtime_path)
    assert sys.prefix == sys.base_prefix, (sys.prefix, sys.base_prefix)
    assert os.getcwd() == "/", os.getcwd()
    assert all(os.path.realpath(entry or os.getcwd()) != expected_site for entry in sys.path), sys.path
    os.chdir(late_import_cwd)
    assert importlib_util.find_spec("customer_delivery_late_shadow") is None
    try:
        import customer_delivery_late_shadow
    except ModuleNotFoundError:
        pass
    else:
        raise AssertionError("late hostile import became reachable")
    os.chdir("/")
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
        assert os.path.realpath(spec.origin).startswith(expected_site.rstrip("/") + "/"), spec.origin
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
if probe_platform == "Darwin":
    assert trusted_dependency_versions == expected_versions, trusted_dependency_versions
else:
    for distribution, version in expected_versions.items():
        assert importlib_metadata.version(distribution) == version, distribution
for module in (cryptography, jsonschema, rfc3339_validator, yaml):
    origin = module.__file__
    if probe_platform == "Darwin":
        assert os.path.realpath(origin).startswith(expected_site.rstrip("/") + "/"), origin
    else:
        resolved_origin = os.path.realpath(origin)
        assert os.path.commonpath((resolved_origin, expected_site)) == expected_site, origin
print(f"{metadata.st_dev}|{metadata.st_ino}|{sys.implementation.name}|{sys.version_info.major}|{sys.version_info.minor}|{dependencies}|{sys.prefix}|{sys.base_prefix}")
'
if [[ "$platform" == Darwin ]]; then
    bootstrap_program="$(/bin/cat <<'PY'
import importlib
import importlib.util
import os
import re
import stat
import sys
from email.parser import Parser

site_path = os.path.realpath(sys.argv[1])
expected_identity = (int(sys.argv[2]), int(sys.argv[3]))
flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
site_fd = os.open(site_path, flags)
metadata = os.fstat(site_fd)
assert (metadata.st_dev, metadata.st_ino) == expected_identity
assert not any(name.endswith(".pth") for name in os.listdir(site_fd))
os.fchdir(site_fd)
assert (os.stat(".").st_dev, os.stat(".").st_ino) == expected_identity
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

def normalize(value):
    return re.sub(r"[-_.]+", "_", value).lower()

def authenticated_version(distribution, expected_version):
    expected_name = f"{normalize(distribution)}-{expected_version}.dist-info"
    candidates = [name for name in os.listdir(site_fd) if name.lower() == expected_name]
    if len(candidates) != 1:
        raise RuntimeError("dist_info_inventory_invalid")
    entry = os.stat(candidates[0], dir_fd=site_fd, follow_symlinks=False)
    if not stat.S_ISDIR(entry.st_mode):
        raise RuntimeError("dist_info_not_directory")
    dist_fd = os.open(candidates[0], flags, dir_fd=site_fd)
    try:
        opened = os.fstat(dist_fd)
        if (opened.st_dev, opened.st_ino) != (entry.st_dev, entry.st_ino):
            raise RuntimeError("dist_info_identity_changed")
        os.fchdir(dist_fd)
        dist_cwd = os.stat(".")
        dist_cwd_identity = (dist_cwd.st_dev, dist_cwd.st_ino)
        if (dist_cwd.st_dev, dist_cwd.st_ino) != (opened.st_dev, opened.st_ino):
            raise RuntimeError("dist_info_cwd_identity_changed")
        metadata_entry = os.stat("METADATA", follow_symlinks=False)
        if (
            not stat.S_ISREG(metadata_entry.st_mode)
            or not 0 < metadata_entry.st_size <= 1048576
        ):
            raise RuntimeError("metadata_invalid")
        metadata_fd = os.open(
            "METADATA",
            os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
        )
        try:
            before = os.fstat(metadata_fd)
            if (
                not stat.S_ISREG(before.st_mode)
                or not 0 < before.st_size <= 1048576
                or (before.st_dev, before.st_ino, before.st_size)
                != (metadata_entry.st_dev, metadata_entry.st_ino, metadata_entry.st_size)
            ):
                raise RuntimeError("metadata_invalid")
            remaining = before.st_size
            chunks = []
            while remaining:
                chunk = os.read(metadata_fd, min(remaining, 65536))
                if not chunk:
                    raise RuntimeError("metadata_truncated")
                chunks.append(chunk)
                remaining -= len(chunk)
            if os.read(metadata_fd, 1):
                raise RuntimeError("metadata_oversized")
            after = os.fstat(metadata_fd)
            if (
                not stat.S_ISREG(after.st_mode)
                or (after.st_dev, after.st_ino, after.st_size)
                != (before.st_dev, before.st_ino, before.st_size)
            ):
                raise RuntimeError("metadata_identity_changed")
        finally:
            os.close(metadata_fd)
        os.fchdir(site_fd)
        site_cwd = os.stat(".")
        site_opened = os.fstat(site_fd)
        if (site_cwd.st_dev, site_cwd.st_ino) != (
            site_opened.st_dev,
            site_opened.st_ino,
        ):
            raise RuntimeError("dependency_site_cwd_identity_changed")
        closed = os.fstat(dist_fd)
        if (closed.st_dev, closed.st_ino) != (entry.st_dev, entry.st_ino):
            raise RuntimeError("dist_info_identity_changed")
    finally:
        os.close(dist_fd)
    parsed = Parser().parsestr(b"".join(chunks).decode("utf-8", "strict"))
    names = parsed.get_all("Name", [])
    versions = parsed.get_all("Version", [])
    if (
        len(names) != 1
        or len(versions) != 1
        or normalize(names[0]) != normalize(distribution)
        or versions[0] != expected_version
    ):
        raise RuntimeError(
            "metadata_mismatch:"
            f"{distribution}:{candidates[0]}:cwd={dist_cwd_identity}:"
            f"opened={(opened.st_dev, opened.st_ino)}:{names!r}:{versions!r}"
        )
    return versions[0]

sys.path.insert(0, ".")
trusted_dependency_versions = {}
expected = {
    "cryptography": ("cryptography", "43.0.3"),
    "jsonschema": ("jsonschema", "4.23.0"),
    "rfc3339_validator": ("rfc3339-validator", "0.1.4"),
    "yaml": ("PyYAML", "6.0.2"),
}
for module_name, (distribution, version) in expected.items():
    spec = importlib.util.find_spec(module_name)
    assert spec is not None and spec.origin is not None
    assert os.path.commonpath((os.path.realpath(spec.origin), site_path)) == site_path
    trusted_dependency_versions[distribution] = authenticated_version(distribution, version)
    module = importlib.import_module(module_name)
    assert os.path.commonpath((os.path.realpath(module.__file__), site_path)) == site_path
metadata = os.fstat(site_fd)
cwd_metadata = os.stat(".")
assert (cwd_metadata.st_dev, cwd_metadata.st_ino) == (
    metadata.st_dev, metadata.st_ino
) == expected_identity
sys.path.remove(".")
os.chdir("/")
program = sys.argv[4]
sys.argv = ["-c"] + sys.argv[5:]
exec(compile(program, "<string>", "exec"), globals(), globals())
PY
)"
    probe="$(/usr/bin/env -i LC_ALL=C \
        /bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash \
        "$python_bin" "$runtime_path" -I -S -c "$bootstrap_program" \
        "$expected_site" "$site_device" "$site_inode" "$probe_program" \
        "$expected_prefix" "$runtime_path" \
        "$python_bin" "$original_cwd" "$platform" "$expected_site" "$late_import_cwd")"
else
    probe="$(/usr/bin/env -i LC_ALL=C /bin/bash -p -c \
        'exec -a "$1" "$2" "${@:3}"' bash \
        "$python_bin" "$runtime_path" -I -c "$probe_program" \
        "$expected_prefix" "$runtime_path" "$python_bin" "$original_cwd" "$platform" "$expected_site" "$late_import_cwd")"
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

#!/usr/bin/env bash
# tests/ci-install-bats-deps.sh — reproducible toolchain for the bats CI jobs.
#
# GitHub Actions has no YAML anchors, so without this script every shard job
# would duplicate the same install block and the pins would drift apart. Keep
# the pins here, in one place.
#
# Security posture (CLAUDE.md § Security Mandate S4 — supply chain):
#   - bats-core is installed from a commit SHA, not a floating tag or an apt
#     package whose version varies per runner image.
#   - yq is downloaded from a versioned release URL and its sha256 is verified
#     before the binary is made executable. No `curl | bash`.
#   - Python packages are version-pinned.
#   - apt packages (jq, shellcheck, socat) are stock distro tooling used only as
#     test fixtures; they are not part of any shipped artefact.
#
# Usage: ci-install-bats-deps.sh [--prefix DIR] [--no-sudo] [--python-only] [--python-bin PATH] [--python-site DIR]
#   --prefix DIR   where to install bats + yq (default /usr/local)
#   --no-sudo      never invoke sudo or install system fixture packages

set -euo pipefail
IFS=$'\n\t'

# Never adopt an inherited temporary-directory variable. Cleanup is authorized
# only for the directory this process creates with mktemp.
CI_INSTALLER_WORKDIR=""
CI_INSTALLER_WORKDIR_CREATED=false
cleanup_ci_installer_workdir() {
    if [[ "$CI_INSTALLER_WORKDIR_CREATED" == true && -n "$CI_INSTALLER_WORKDIR" ]]; then
        rm -rf -- "$CI_INSTALLER_WORKDIR"
    fi
}
create_ci_installer_workdir() {
    if [[ "$CI_INSTALLER_WORKDIR_CREATED" != true ]]; then
        CI_INSTALLER_WORKDIR="$(mktemp -d)"
        CI_INSTALLER_WORKDIR_CREATED=true
        trap cleanup_ci_installer_workdir EXIT
    fi
}

# --- pins -------------------------------------------------------------------
# bats-core v1.11.1 (peeled tag object). Re-resolve with:
#   git ls-remote --tags https://github.com/bats-core/bats-core.git 'v*^{}'
BATS_REPO="https://github.com/bats-core/bats-core.git"
BATS_SHA="b640ec3cf2c7c9cfc9e6351479261186f76eeec8"
BATS_HUMAN_VERSION="v1.11.1"

# yq v4.44.3 linux/amd64. Re-resolve the digest with:
#   curl -fsSL https://github.com/mikefarah/yq/releases/download/<ver>/checksums \
#     | awk '$1=="yq_linux_amd64"{print $19}'
# (column 19 is SHA-256 per that release's checksums_hashes_order manifest)
YQ_VERSION="v4.44.3"
YQ_SHA256="a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7"

# jsonschema 4.23.0's platform-independent wheel, pinned to its canonical
# PyPI-hosted artifact. Keep the installer independent of index candidate
# selection and verify the downloaded bytes before pip receives the wheel.
PY_JSONSCHEMA_WHEEL_URL="https://files.pythonhosted.org/packages/69/4a/4f9dbeb84e8850557c02365a0eee0649abe5eb1d84af92a25731c6c0f922/jsonschema-4.23.0-py3-none-any.whl"
PY_JSONSCHEMA_WHEEL_SHA256="fbadb6f8b144a8f8cf9f0b89ba94501d143e50411a1278633f56a7acf7fd5566"
PYPI_INDEX_URL="https://pypi.org/simple"
PY_RFC3339_VALIDATOR="rfc3339-validator==0.1.4"
PY_PYYAML="pyyaml==6.0.2"
PY_CRYPTOGRAPHY="cryptography==43.0.3"

PREFIX="/usr/local"
PYTHON_ONLY=false
NO_SUDO=false
PYTHON_BIN="python3"
PYTHON_SITE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "ERROR: --prefix requires an argument" >&2; exit 2; }
            PREFIX="$2"; shift ;;
        --no-sudo)
            NO_SUDO=true ;;
        --python-only)
            PYTHON_ONLY=true ;;
        --python-bin)
            [ $# -ge 2 ] || { echo "ERROR: --python-bin requires an argument" >&2; exit 2; }
            PYTHON_BIN="$2"; shift ;;
        --python-site)
            [ $# -ge 2 ] || { echo "ERROR: --python-site requires an argument" >&2; exit 2; }
            PYTHON_SITE="$2"; shift ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--prefix DIR] [--no-sudo] [--python-only] [--python-bin PATH] [--python-site DIR]"; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Point one private socat at the libwrap copied beside it. The prefix path is
# restricted to characters mktemp produces so the generated wrapper cannot
# break out of its assignments.
write_private_socat_wrapper() {
    local wrapper
    wrapper="$PREFIX/bin/socat"
    [[ "$PREFIX" =~ ^/[A-Za-z0-9._+/-]+$ ]] || return 1
    [[ "$PREFIX" != *..* ]] || return 1
    if ! cat > "$wrapper" << EOF
#!/bin/sh
set -eu
libdir=$(printf '%q' "$PREFIX/lib")
binary=$(printf '%q' "$PREFIX/libexec/socat")
if [ -n "\${LD_LIBRARY_PATH:-}" ]; then
    LD_LIBRARY_PATH="\$libdir:\$LD_LIBRARY_PATH"
else
    LD_LIBRARY_PATH="\$libdir"
fi
export LD_LIBRARY_PATH
exec "\$binary" "\$@"
EOF
    then
        return 1
    fi
    chmod 0755 "$wrapper" || return 1
}

# libwrap0 is not part of the minimized runner package list. Download the
# release that matches the socat archive, verify it, and install a wrapper
# only after the extracted binary actually loads against that library.
install_private_socat_with_libwrap() {
    local package_root socat_bin libwrap_url libwrap_digest lib_link
    package_root="$1"
    socat_bin="$2"
    libwrap_url="$3"
    libwrap_digest="$4"
    if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 \
            -o "$package_root/libwrap.deb" "$libwrap_url" \
        || ! echo "$libwrap_digest  $package_root/libwrap.deb" | sha256sum -c - \
        || ! dpkg-deb -x "$package_root/libwrap.deb" "$package_root/libwrap-extracted"; then
        return 1
    fi
    lib_link="$package_root/libwrap-extracted/usr/lib/x86_64-linux-gnu/libwrap.so.0"
    [[ -e "$lib_link" ]] || return 1
    mkdir -p "$package_root/lib"
    cp -L -- "$lib_link" "$package_root/lib/libwrap.so.0" || return 1
    [[ -f "$package_root/lib/libwrap.so.0" && ! -L "$package_root/lib/libwrap.so.0" ]] || return 1
    if ! LD_LIBRARY_PATH="$package_root/lib" "$socat_bin" -V >/dev/null 2>&1; then
        return 1
    fi
    mkdir -p "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/libexec"
    if ! install -m 0755 "$socat_bin" "$PREFIX/libexec/socat" \
        || ! install -m 0644 "$package_root/lib/libwrap.so.0" "$PREFIX/lib/libwrap.so.0" \
        || ! write_private_socat_wrapper \
        || ! "$PREFIX/bin/socat" -V >/dev/null 2>&1; then
        rm -f -- "$PREFIX/bin/socat" "$PREFIX/libexec/socat" "$PREFIX/lib/libwrap.so.0"
        return 1
    fi
}

# Measured Ubuntu amd64 socat packages only. Each digest was checked against
# the downloaded archive file. Extract data into the caller-owned prefix:
# no dpkg install and no maintainer scripts. Any other distro stays unqualified.
# A binary that already loads is copied alone. A binary that cannot load
# because libwrap.so.0 is absent gets the matching hash-pinned libwrap0.
install_private_socat() {
    local distro package_root url digest libwrap_url libwrap_digest socat_bin
    for tool in curl dpkg dpkg-deb sha256sum mktemp install awk tar cp; do
        command -v "$tool" >/dev/null 2>&1 || return 1
    done
    [[ "$PREFIX" == /* && "$PREFIX" != /usr/local ]] || return 1
    [[ -r /etc/os-release ]] || return 1
    distro="$(awk -F= '/^ID=/{gsub(/"/,"",$2); id=$2} /^VERSION_ID=/{gsub(/"/,"",$2); ver=$2} END{printf "%s:%s",id,ver}' /etc/os-release)"
    [[ "$(dpkg --print-architecture)" == amd64 ]] || return 1
    case "$distro" in
        ubuntu:24.04)
            url="https://archive.ubuntu.com/ubuntu/pool/main/s/socat/socat_1.8.0.0-4ubuntu0.1_amd64.deb"
            digest="46e854289b6b1c97e28be5d9293bea61e8633d00d6a65d9513f019c7232696fe"
            libwrap_url="https://archive.ubuntu.com/ubuntu/pool/main/t/tcp-wrappers/libwrap0_7.6.q-33_amd64.deb"
            libwrap_digest="36118b862539868408ee056411d6e470068d14c46e5296b29bfb744770f5d2ce"
            ;;
        ubuntu:26.04)
            url="https://archive.ubuntu.com/ubuntu/pool/main/s/socat/socat_1.8.1.1-1_amd64.deb"
            digest="08f77c85ba1f399c8b21bc098afbce0dea90529e80c9673b7df9bc391bd3f001"
            libwrap_url="https://archive.ubuntu.com/ubuntu/pool/main/t/tcp-wrappers/libwrap0_7.6.q-36build2_amd64.deb"
            libwrap_digest="a3784ca083c626c3ae41cdd32d4c5898554650dc77d2b54dbb1197a38198adf8"
            ;;
        *)
            return 1
            ;;
    esac
    package_root="$(mktemp -d)" || return 1
    socat_bin="$package_root/extracted/usr/bin/socat"
    if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 \
            -o "$package_root/socat.deb" "$url" \
        || ! echo "$digest  $package_root/socat.deb" | sha256sum -c - \
        || ! dpkg-deb -x "$package_root/socat.deb" "$package_root/extracted" \
        || ! [[ -x "$socat_bin" ]]; then
        rm -rf -- "$package_root"
        return 1
    fi
    if "$socat_bin" -V >/dev/null 2>&1; then
        mkdir -p "$PREFIX/bin"
        if ! install -m 0755 "$socat_bin" "$PREFIX/bin/socat"; then
            rm -rf -- "$package_root"
            return 1
        fi
    elif ! install_private_socat_with_libwrap "$package_root" "$socat_bin" "$libwrap_url" "$libwrap_digest"; then
        rm -rf -- "$package_root"
        return 1
    fi
    rm -rf -- "$package_root"
    export PATH="$PREFIX/bin:$PATH"
}

if [ "$PYTHON_ONLY" != true ]; then
    # Install only what is missing, and only when this account can actually
    # install. A self-hosted runner is a long-lived machine whose tools are
    # already there: measured on a shared dev host, the ci-runner account already
    # had jq, shellcheck and bats under ~/.local/bin and has no passwordless
    # sudo, so the unconditional `sudo apt-get` failed the job before a single
    # test ran -- over packages that did not need installing.
    # An array, so the package list carries no leading blank. Built as a string
    # it started with a space, and the unquoted expansion then handed apt-get an
    # empty first argument: "E: Unable to locate package  socat".
    if [ "$NO_SUDO" = true ] && ! command -v socat >/dev/null 2>&1; then
        install_private_socat || echo "ERROR: private socat fixture unavailable or unqualified" >&2
    fi
    missing=()
    for tool in jq shellcheck socat; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    # An array, not a string: `SUDO="sudo -n"` expands to a single word and is
    # looked up as a command named "sudo -n", which does not exist. The old code
    # happened to survive `SUDO="sudo"` only because that is one word.
    #
    # Resolved here rather than inside the apt branch: the bats-core and yq
    # installs below write to $PREFIX and need the same elevation even when no
    # apt package is missing. Scoping it to the apt branch left those two
    # commands running unelevated.
    sudo_cmd=()
    if [ "$NO_SUDO" != true ] && [ "$(id -u)" -ne 0 ] && sudo -n true 2>/dev/null; then
        # `sudo -n` fails rather than prompting, so a runner without passwordless
        # sudo never hangs on a password prompt no one can answer.
        sudo_cmd=(sudo -n)
    fi

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "==> apt fixtures (jq, shellcheck, socat): already present"
    else
        if [ "$NO_SUDO" = true ] || { [ "$(id -u)" -ne 0 ] && [ "${#sudo_cmd[@]}" -eq 0 ]; }; then
            echo "ERROR: missing fixtures: ${missing[*]}" >&2
            echo "       system fixture installation is unavailable (unprivileged mode or no passwordless sudo)." >&2
            echo "       Install them on the runner, or run as root." >&2
            exit 1
        fi
        echo "==> apt fixtures (installing: ${missing[*]})"
        "${sudo_cmd[@]}" apt-get update -qq
        "${sudo_cmd[@]}" apt-get install -y --no-install-recommends "${missing[@]}"
    fi

    echo "==> bats-core ${BATS_HUMAN_VERSION} @ ${BATS_SHA}"
    create_ci_installer_workdir
    git -C "$CI_INSTALLER_WORKDIR" init -q bats-core
    git -C "$CI_INSTALLER_WORKDIR/bats-core" remote add origin "$BATS_REPO"
    # Fetch exactly the pinned object; a tag rewrite upstream cannot change it.
    git -C "$CI_INSTALLER_WORKDIR/bats-core" fetch -q --depth 1 origin "$BATS_SHA"
    git -C "$CI_INSTALLER_WORKDIR/bats-core" checkout -q FETCH_HEAD
    actual_sha="$(git -C "$CI_INSTALLER_WORKDIR/bats-core" rev-parse HEAD)"
    if [ "$actual_sha" != "$BATS_SHA" ]; then
        echo "ERROR: bats-core checkout is ${actual_sha}, expected ${BATS_SHA}" >&2
        exit 1
    fi
    "${sudo_cmd[@]}" "$CI_INSTALLER_WORKDIR/bats-core/install.sh" "$PREFIX"

    echo "==> yq ${YQ_VERSION}"
    yq_tmp="${CI_INSTALLER_WORKDIR}/yq_linux_amd64"
    curl -fsSL --proto '=https' --tlsv1.2 \
        -o "$yq_tmp" \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
    echo "${YQ_SHA256}  ${yq_tmp}" | sha256sum -c -
    "${sudo_cmd[@]}" install -m 0755 "$yq_tmp" "${PREFIX}/bin/yq"
fi

echo "==> python test deps"
if [[ -n "$PYTHON_SITE" ]]; then
    [[ "$PYTHON_SITE" == /* && -d "$PYTHON_SITE" && ! -L "$PYTHON_SITE" ]] || {
        echo "ERROR: --python-site must be an absolute existing directory" >&2
        exit 2
    }
fi
create_ci_installer_workdir
jsonschema_wheel="${CI_INSTALLER_WORKDIR}/jsonschema-4.23.0-py3-none-any.whl"
if ! curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 \
    -o "$jsonschema_wheel" "$PY_JSONSCHEMA_WHEEL_URL"; then
    echo "ERROR: unable to download the pinned jsonschema wheel" >&2
    exit 1
fi
if ! "$PYTHON_BIN" -I -S -c '
import hashlib
import sys

path, expected = sys.argv[1:]
digest = hashlib.sha256()
with open(path, "rb") as wheel:
    for block in iter(lambda: wheel.read(1024 * 1024), b""):
        digest.update(block)
if digest.hexdigest() != expected:
    print("jsonschema wheel SHA-256 mismatch", file=sys.stderr)
    raise SystemExit(1)
' "$jsonschema_wheel" "$PY_JSONSCHEMA_WHEEL_SHA256"; then
    echo "ERROR: pinned jsonschema wheel failed SHA-256 verification" >&2
    exit 1
fi
python_install_options=(--no-cache-dir --isolated --index-url "$PYPI_INDEX_URL")
python_install_packages=("$jsonschema_wheel" "$PY_RFC3339_VALIDATOR" "$PY_PYYAML" "$PY_CRYPTOGRAPHY")
if [[ -n "$PYTHON_SITE" ]]; then
    "$PYTHON_BIN" -I -S -c '
import runpy
import sys

target = sys.argv[1]
sys.path.insert(0, target)
sys.argv = ["pip", "install", "--quiet", "--disable-pip-version-check", "--upgrade", "--target", target] + sys.argv[2:]
runpy.run_module("pip", run_name="__main__")
' "$PYTHON_SITE" "${python_install_packages[@]}" "${python_install_options[@]}"
    python_site="$PYTHON_SITE"
else
    "$PYTHON_BIN" -m pip install --quiet --disable-pip-version-check \
        "${python_install_options[@]}" "${python_install_packages[@]}"
    python_site="$("$PYTHON_BIN" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
fi
# Apple CLT Python 3.9 seeds setuptools and its executable
# distutils-precedence.pth into a fresh venv. None of the pinned validator
# dependencies needs that startup hook; remove only this known installer file
# and fail if any other .pth authority remains.
for pth_file in "$python_site"/*.pth; do
    [[ -e "$pth_file" || -L "$pth_file" ]] || continue
    if [[ "${pth_file##*/}" == distutils-precedence.pth ]]; then
        /bin/rm -f -- "$pth_file"
    else
        echo "ERROR: unexpected executable Python path file: $pth_file" >&2
        exit 1
    fi
done
if [[ -n "$PYTHON_SITE" ]]; then
    "$PYTHON_BIN" -I -S -c 'import sys; sys.path.insert(0, sys.argv[1]); import cryptography, jsonschema, rfc3339_validator, yaml; assert "date-time" in jsonschema.FormatChecker().checkers; jsonschema.FormatChecker().check("2026-01-01T00:00:00Z", "date-time")' "$PYTHON_SITE"
else
    "$PYTHON_BIN" -c 'import cryptography, jsonschema, rfc3339_validator, yaml; assert "date-time" in jsonschema.FormatChecker().checkers; jsonschema.FormatChecker().check("2026-01-01T00:00:00Z", "date-time")'
fi

echo "==> versions"
if [ "$PYTHON_ONLY" != true ]; then
    "${PREFIX}/bin/bats" --version
    "${PREFIX}/bin/yq" --version
    jq --version
    shellcheck --version | sed -n '2p'
fi
"$PYTHON_BIN" --version
echo "toolchain ready"

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
# Usage: ci-install-bats-deps.sh [--prefix DIR] [--python-only] [--python-bin PATH] [--python-site DIR]
#   --prefix DIR   where to install bats + yq (default /usr/local)

set -euo pipefail
IFS=$'\n\t'

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

PY_JSONSCHEMA="jsonschema==4.23.0"
PY_RFC3339_VALIDATOR="rfc3339-validator==0.1.4"
PY_PYYAML="pyyaml==6.0.2"
PY_CRYPTOGRAPHY="cryptography==43.0.3"

PREFIX="/usr/local"
PYTHON_ONLY=false
PYTHON_BIN="python3"
PYTHON_SITE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "ERROR: --prefix requires an argument" >&2; exit 2; }
            PREFIX="$2"; shift ;;
        --python-only)
            PYTHON_ONLY=true ;;
        --python-bin)
            [ $# -ge 2 ] || { echo "ERROR: --python-bin requires an argument" >&2; exit 2; }
            PYTHON_BIN="$2"; shift ;;
        --python-site)
            [ $# -ge 2 ] || { echo "ERROR: --python-site requires an argument" >&2; exit 2; }
            PYTHON_SITE="$2"; shift ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--prefix DIR] [--python-only] [--python-bin PATH] [--python-site DIR]"; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$PYTHON_ONLY" != true ]; then
    # Install only what is missing, and only when this account can actually
    # install. A self-hosted runner is a long-lived machine whose tools are
    # already there: measured on host-devs-3, the ci-runner account already
    # had jq, shellcheck and bats under ~/.local/bin and has no passwordless
    # sudo, so the unconditional `sudo apt-get` failed the job before a single
    # test ran -- over packages that did not need installing.
    # An array, so the package list carries no leading blank. Built as a string
    # it started with a space, and the unquoted expansion then handed apt-get an
    # empty first argument: "E: Unable to locate package  socat".
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
    if [ "$(id -u)" -ne 0 ] && sudo -n true 2>/dev/null; then
        # `sudo -n` fails rather than prompting, so a runner without passwordless
        # sudo never hangs on a password prompt no one can answer.
        sudo_cmd=(sudo -n)
    fi

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "==> apt fixtures (jq, shellcheck, socat): already present"
    else
        if [ "$(id -u)" -ne 0 ] && [ "${#sudo_cmd[@]}" -eq 0 ]; then
            echo "ERROR: missing fixtures: ${missing[*]}" >&2
            echo "       this account cannot apt-get install (no passwordless sudo)." >&2
            echo "       Install them on the runner, or run as root." >&2
            exit 1
        fi
        echo "==> apt fixtures (installing: ${missing[*]})"
        "${sudo_cmd[@]}" apt-get update -qq
        "${sudo_cmd[@]}" apt-get install -y --no-install-recommends "${missing[@]}"
    fi

echo "==> bats-core ${BATS_HUMAN_VERSION} @ ${BATS_SHA}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
git -C "$workdir" init -q bats-core
git -C "$workdir/bats-core" remote add origin "$BATS_REPO"
# Fetch exactly the pinned object; a tag rewrite upstream cannot change it.
git -C "$workdir/bats-core" fetch -q --depth 1 origin "$BATS_SHA"
git -C "$workdir/bats-core" checkout -q FETCH_HEAD
actual_sha="$(git -C "$workdir/bats-core" rev-parse HEAD)"
if [ "$actual_sha" != "$BATS_SHA" ]; then
    echo "ERROR: bats-core checkout is ${actual_sha}, expected ${BATS_SHA}" >&2
    exit 1
fi
"${sudo_cmd[@]}" "$workdir/bats-core/install.sh" "$PREFIX"

echo "==> yq ${YQ_VERSION}"
yq_tmp="${workdir}/yq_linux_amd64"
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
    "$PYTHON_BIN" -I -S -c '
import runpy
import sys

target = sys.argv[1]
sys.path.insert(0, target)
sys.argv = ["pip", "install", "--quiet", "--disable-pip-version-check", "--upgrade", "--target", target] + sys.argv[2:]
runpy.run_module("pip", run_name="__main__")
' "$PYTHON_SITE" "$PY_JSONSCHEMA" "$PY_RFC3339_VALIDATOR" "$PY_PYYAML" "$PY_CRYPTOGRAPHY"
    python_site="$PYTHON_SITE"
else
    "$PYTHON_BIN" -m pip install --quiet --disable-pip-version-check \
        "$PY_JSONSCHEMA" "$PY_RFC3339_VALIDATOR" "$PY_PYYAML" "$PY_CRYPTOGRAPHY"
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

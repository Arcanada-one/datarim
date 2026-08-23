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
# Usage: ci-install-bats-deps.sh [--prefix DIR] [--python-only] [--python-bin PATH]
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
        --help|-h)
            echo "Usage: $(basename "$0") [--prefix DIR] [--python-only] [--python-bin PATH]"; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$PYTHON_ONLY" != true ]; then
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO="sudo"
    fi

    echo "==> apt fixtures (jq, shellcheck, socat)"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y --no-install-recommends jq shellcheck socat

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
$SUDO "$workdir/bats-core/install.sh" "$PREFIX"

echo "==> yq ${YQ_VERSION}"
yq_tmp="${workdir}/yq_linux_amd64"
curl -fsSL --proto '=https' --tlsv1.2 \
     -o "$yq_tmp" \
     "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
echo "${YQ_SHA256}  ${yq_tmp}" | sha256sum -c -
    $SUDO install -m 0755 "$yq_tmp" "${PREFIX}/bin/yq"
fi

echo "==> python test deps"
"$PYTHON_BIN" -m pip install --quiet --disable-pip-version-check \
    "$PY_JSONSCHEMA" "$PY_RFC3339_VALIDATOR" "$PY_PYYAML" "$PY_CRYPTOGRAPHY"
# Apple CLT Python 3.9 seeds setuptools and its executable
# distutils-precedence.pth into a fresh venv. None of the pinned validator
# dependencies needs that startup hook; remove only this known installer file
# and fail if any other .pth authority remains.
python_site="$("$PYTHON_BIN" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
for pth_file in "$python_site"/*.pth; do
    [[ -e "$pth_file" || -L "$pth_file" ]] || continue
    if [[ "${pth_file##*/}" == distutils-precedence.pth ]]; then
        /bin/rm -f -- "$pth_file"
    else
        echo "ERROR: unexpected executable Python path file: $pth_file" >&2
        exit 1
    fi
done
"$PYTHON_BIN" -c 'import cryptography, jsonschema, rfc3339_validator, yaml; assert "date-time" in jsonschema.FormatChecker().checkers; jsonschema.FormatChecker().check("2026-01-01T00:00:00Z", "date-time")'

echo "==> versions"
if [ "$PYTHON_ONLY" != true ]; then
    "${PREFIX}/bin/bats" --version
    "${PREFIX}/bin/yq" --version
    jq --version
    shellcheck --version | sed -n '2p'
fi
"$PYTHON_BIN" --version
echo "toolchain ready"

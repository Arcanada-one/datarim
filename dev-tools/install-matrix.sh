#!/usr/bin/env bash
# install-matrix.sh — multi-distro install.sh verification harness.
#
# Runs install.sh inside Docker containers for a pinned list of OS images,
# then executes the post-install assertions bats suite in each container.
# Produces a structured pass/fail table and writes a Markdown report.
#
# Usage:
#   dev-tools/install-matrix.sh [--report <file>] [--images <img,...>] [--vendor <flag>]
#
# Options:
#   --report <file>   Write Markdown report to <file> (default: stdout only)
#   --images <list>   Comma-separated list of Docker images to test
#                     (default: the pinned 7-image canonical list)
#   --vendor <flag>   install.sh vendor flag (default: --with-claude)
#   --no-pull         Skip docker pull (use cached images)
#   --help            Print this help and exit 0
#
# Portability:
#   - Requires bash >= 4, docker, git.
#   - Does NOT require bats on the host — bats is installed inside each container.
#   - No grep -P, no \x{} character classes (BSD-safe).
#   - stat mode: GNU -c '%a' first, BSD -f '%Lp' fallback (not used here but
#     consistent with project policy).
#
# Exit codes:
#   0  All lanes passed
#   1  One or more lanes failed
#   2  Pre-flight check failed (docker/git absent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- defaults ----------------------------------------------------------

REPORT_FILE=""
VENDOR_FLAG="--with-claude"
NO_PULL=false
GIT_CLONE=false   # set --git-clone to do a real `git clone` instead of cp from mount

# Canonical pinned image list (V-AC-1: minimum 7 images).
DEFAULT_IMAGES=(
    "rockylinux:9"
    "almalinux:9"
    "fedora:latest"
    "redhat/ubi9-minimal"
    "debian:stable-slim"
    "ubuntu:latest"
    "alpine:latest"
)

IMAGES=()

# ---------- parse args --------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --report)    REPORT_FILE="$2"; shift 2 ;;
        --images)    IFS=',' read -ra IMAGES <<< "$2"; shift 2 ;;
        --vendor)    VENDOR_FLAG="$2"; shift 2 ;;
        --no-pull)   NO_PULL=true; shift ;;
        --git-clone) GIT_CLONE=true; shift ;;
        --help)
            sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done

[ "${#IMAGES[@]}" -eq 0 ] && IMAGES=("${DEFAULT_IMAGES[@]}")

# ---------- pre-flight --------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found on PATH — cannot run matrix" >&2
    exit 2
fi

if ! command -v git >/dev/null 2>&1; then
    echo "error: git not found on PATH — cannot build matrix rig" >&2
    exit 2
fi

if ! docker info >/dev/null 2>&1; then
    echo "error: Docker daemon not reachable — is Docker running?" >&2
    exit 2
fi

# ---------- helpers -----------------------------------------------------------

HOST=""
HOST="$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "unknown")"

timestamp() { date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u; }

pad_right() {
    local s="$1" w="$2"
    printf "%-${w}s" "$s"
}

# ---------- lane runner -------------------------------------------------------
# run_lane IMAGE VENDOR_FLAG
# Returns: sets LANE_STATUS (PASS|FAIL), LANE_OUTPUT (log text)
run_lane() {
    local image="$1" vendor="$2"
    local cname
    cname="datarim-matrix-$$-$(echo "$image" | tr '/:' '--')"
    local lane_log=""
    local exit_code=0

    # Pull image unless --no-pull
    if [ "$NO_PULL" = false ]; then
        docker pull --quiet "$image" >/dev/null 2>&1 || {
            LANE_STATUS="FAIL"
            LANE_OUTPUT="docker pull failed for $image"
            return
        }
    fi

    # Build the full in-container script.
    local container_script
    container_script=$(cat <<'CONTAINERSCRIPT'
#!/bin/sh
set -e

_install_bats_from_git() {
    if command -v bats >/dev/null 2>&1; then return; fi
    tmpd="$(mktemp -d)"
    git clone --depth=1 --quiet https://github.com/bats-core/bats-core.git "$tmpd/bats" >/dev/null 2>&1
    "$tmpd/bats/install.sh" /usr/local >/dev/null 2>&1
}

# ---- package setup ----
if command -v dnf >/dev/null 2>&1; then
    dnf install -y -q git bash >/dev/null 2>&1 || true
    _install_bats_from_git
elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y git bash >/dev/null 2>&1 || true
    _install_bats_from_git
elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -q git bats bash >/dev/null 2>&1 || true
    _install_bats_from_git
elif command -v apk >/dev/null 2>&1; then
    apk add --quiet git bash bats >/dev/null 2>&1 || true
    _install_bats_from_git
fi

echo "[lane] package setup done"

# ---- get repo ----
# GIT_CLONE_MODE placeholder is substituted by the harness at runtime.
if [ "GIT_CLONE_PLACEHOLDER" = "true" ]; then
    git clone --quiet file:///host-repo /opt/datarim >/dev/null 2>&1
    echo "[lane] repo cloned via git: $(ls /opt/datarim/install.sh)"
else
    cp -r /host-repo /opt/datarim
    echo "[lane] repo copied from mount: $(ls /opt/datarim/install.sh)"
fi

# ---- vendor-aware target dir setup ----
# Each vendor installs into a different directory.  The harness must set the
# correct env var so install.sh writes to a known scratch path, then expose
# TARGET_DIR so post-install.bats knows where to look.
VENDOR_FLAG_VALUE="VENDOR_FLAG_PLACEHOLDER"
case "$VENDOR_FLAG_VALUE" in
    --with-claude)
        export CLAUDE_DIR=/tmp/fake-claude
        mkdir -p "$CLAUDE_DIR"
        export TARGET_DIR="$CLAUDE_DIR"
        ;;
    --with-codex)
        # fanout_runtime codex resolves the target as: ${CODEX_DIR:-~/.codex}.
        # Set CODEX_DIR to a scratch path and leave CLAUDE_DIR unset (or
        # pointing elsewhere) so the two runtimes never share a dir.
        export CODEX_DIR=/tmp/fake-codex
        mkdir -p "$CODEX_DIR"
        export TARGET_DIR="$CODEX_DIR"
        ;;
    --with-cursor)
        # setup_cursor_runtime uses ${CURSOR_DIR:-~/.cursor}.
        export CURSOR_DIR=/tmp/fake-cursor
        mkdir -p "$CURSOR_DIR"
        export TARGET_DIR="$CURSOR_DIR"
        ;;
    *)
        # Unknown vendor — fall back to claude semantics.
        export CLAUDE_DIR=/tmp/fake-claude
        mkdir -p "$CLAUDE_DIR"
        export TARGET_DIR="$CLAUDE_DIR"
        ;;
esac

# ---- run install ----
bash /opt/datarim/install.sh VENDOR_FLAG_PLACEHOLDER
echo "[lane] install.sh exited: $?"

# ---- run post-install assertions ----
export INSTALL_REPO=/opt/datarim
export VENDOR_FLAG="VENDOR_FLAG_PLACEHOLDER"
# TARGET_DIR already exported above — bats reads it instead of CLAUDE_DIR.
bats /opt/datarim/tests/install-matrix/post-install.bats
CONTAINERSCRIPT
)

    # Substitute the vendor flag placeholder and git-clone mode.
    container_script="${container_script//VENDOR_FLAG_PLACEHOLDER/$vendor}"
    container_script="${container_script//GIT_CLONE_PLACEHOLDER/$GIT_CLONE}"

    # Write script to a temp file so we can mount it.
    local script_tmp
    script_tmp="$(mktemp)"
    printf '%s\n' "$container_script" > "$script_tmp"
    chmod +x "$script_tmp"

    # Run container: mount the repo as read-only so git clone works via file://.
    lane_log="$(
        docker run --rm \
            --name "$cname" \
            -v "${REPO_ROOT}:/host-repo:ro" \
            -v "${script_tmp}:/run-lane.sh:ro" \
            "$image" \
            sh /run-lane.sh 2>&1
    )" || exit_code=$?

    rm -f "$script_tmp"

    if [ "$exit_code" -eq 0 ]; then
        LANE_STATUS="PASS"
    else
        LANE_STATUS="FAIL"
    fi
    LANE_OUTPUT="$lane_log"
}

# ---------- main loop ---------------------------------------------------------

declare -a RESULTS_IMAGE RESULTS_STATUS RESULTS_SUMMARY
PASS_COUNT=0
FAIL_COUNT=0
RUN_TS="$(timestamp)"

echo "Datarim install-matrix — $(timestamp)"
echo "Vendor flag: $VENDOR_FLAG"
echo "Images: ${IMAGES[*]}"
echo "Host: $HOST"
echo "---"

for img in "${IMAGES[@]}"; do
    printf "  %-38s  " "$img"
    LANE_STATUS=""
    LANE_OUTPUT=""
    run_lane "$img" "$VENDOR_FLAG"
    printf "%s\n" "$LANE_STATUS"

    RESULTS_IMAGE+=("$img")
    RESULTS_STATUS+=("$LANE_STATUS")

    # Extract bats pass/fail counts from output.
    bats_summary=""
    if printf '%s' "$LANE_OUTPUT" | grep -qE '^[0-9]+\.\.[0-9]+'; then
        bats_total_raw="$(printf '%s' "$LANE_OUTPUT" | grep -E '^[0-9]+\.\.[0-9]+' | tail -1)"
        bats_total="${bats_total_raw##*..}"
        bats_total="${bats_total%%[!0-9]*}"   # strip any trailing non-digits
        bats_fail=0
        # count 'not ok' lines safely
        while IFS= read -r _line; do
            case "$_line" in "not ok "*) bats_fail=$(( bats_fail + 1 ));; esac
        done <<< "$LANE_OUTPUT"
        if [ -n "$bats_total" ] && [ "$bats_total" -gt 0 ] 2>/dev/null; then
            bats_pass=$(( bats_total - bats_fail ))
            bats_summary="${bats_pass}/${bats_total} assertions"
        fi
    fi
    RESULTS_SUMMARY+=("${LANE_STATUS}${bats_summary:+ — $bats_summary}")

    if [ "$LANE_STATUS" = "PASS" ]; then
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        # Print lane log on failure for immediate debugging.
        printf '%s\n' "$LANE_OUTPUT" | sed 's/^/    | /' | head -40
    fi
done

echo "---"
echo "Result: $PASS_COUNT passed, $FAIL_COUNT failed"

# ---------- write Markdown report ---------------------------------------------

write_report() {
    local target="$1"
    {
        echo "# Install Matrix Report"
        echo ""
        echo "| field | value |"
        echo "|-------|-------|"
        echo "| run_at | $RUN_TS |"
        echo "| host | $HOST |"
        echo "| vendor | $VENDOR_FLAG |"
        echo "| pass | $PASS_COUNT |"
        echo "| fail | $FAIL_COUNT |"
        echo ""
        echo "## Results"
        echo ""
        echo "| image | status | detail |"
        echo "|-------|--------|--------|"
        local i
        for i in "${!RESULTS_IMAGE[@]}"; do
            echo "| ${RESULTS_IMAGE[$i]} | ${RESULTS_STATUS[$i]} | ${RESULTS_SUMMARY[$i]} |"
        done
        echo ""
        echo "## Lane Logs"
        echo ""
        # (Detailed per-lane logs omitted from this summary report; captured
        # separately per lane if needed via --report with per-image suffix.)
    } > "$target"
}

if [ -n "$REPORT_FILE" ]; then
    mkdir -p "$(dirname "$REPORT_FILE")"
    write_report "$REPORT_FILE"
    echo "Report written: $REPORT_FILE"
fi

# Exit with failure if any lane failed.
[ "$FAIL_COUNT" -eq 0 ]

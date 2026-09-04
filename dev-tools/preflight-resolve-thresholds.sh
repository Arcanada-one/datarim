#!/usr/bin/env bash
# Resolve composite-action disk thresholds without overwriting values exported
# from the validated severity-overrides input via GITHUB_ENV.

set -euo pipefail

: "${PREFLIGHT_DEFAULT_MIN_FREE_DISK_GB:?missing default min-free-disk-gb}"
: "${PREFLIGHT_DEFAULT_DISK_WARN_PERCENT:?missing default disk-warn-percent}"
: "${PREFLIGHT_DEFAULT_DISK_FAIL_PERCENT:?missing default disk-fail-percent}"

export PREFLIGHT_MIN_FREE_DISK_GB="${PREFLIGHT_MIN_FREE_DISK_GB:-$PREFLIGHT_DEFAULT_MIN_FREE_DISK_GB}"
export PREFLIGHT_DISK_WARN_PERCENT="${PREFLIGHT_DISK_WARN_PERCENT:-$PREFLIGHT_DEFAULT_DISK_WARN_PERCENT}"
export PREFLIGHT_DISK_FAIL_PERCENT="${PREFLIGHT_DISK_FAIL_PERCENT:-$PREFLIGHT_DEFAULT_DISK_FAIL_PERCENT}"

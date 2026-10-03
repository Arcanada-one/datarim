#!/usr/bin/env bash
# tests/run-bats-discovery.sh — glob-based discovery runner for every bats suite
# in the repository.
#
# WHY THIS EXISTS
# ---------------
# CI previously named bats suites in explicit lists (`bats dev-tools/tests/a.bats`,
# `bats dev-tools/tests/b.bats`, ...) and in non-recursive directory invocations
# (`bats tests/` does NOT descend into `tests/security/`). Both patterns fail
# open: a suite added later is simply never named, and nothing reports the gap.
# A gate that no CI job runs is not a gate.
#
# This runner inverts the default: every *.bats file in the repo runs UNLESS it
# is listed in the exclusion registry with an explicit, dated reason. Adding a
# new suite anywhere requires zero CI changes.
#
# USAGE
#   run-bats-discovery.sh [--list] [--shard N/M] [--check-registry]
#                         [--root DIR] [--registry FILE] [--timeout SECS]
#                         [--help]
#
#   --list             print the discovered (non-excluded) suite paths, one per
#                      line, sorted; exit 0.
#   --shard N/M        run only shard N of M (1-based). Round-robin over the
#                      sorted suite list, so shards stay balanced as suites are
#                      added.
#   --check-registry   validate the exclusion registry: every entry must have a
#                      path that exists on disk, plus non-empty reason / owner /
#                      follow_up / added fields. Exits 1 on drift (a stale
#                      exclusion is how a fixed suite silently stays dark).
#   --root DIR         repository root to scan (default: the repo containing
#                      this script).
#   --registry FILE    exclusion registry (default: <root>/tests/bats-exclusions.yml).
#   --timeout SECS     per-suite wall-clock ceiling (default 600, env
#                      BATS_SUITE_TIMEOUT). A suite that exceeds it is reported
#                      as a failure, not skipped.
#
# EXIT CODES
#   0  every executed suite passed (or --list / --check-registry succeeded)
#   1  at least one suite failed, or the registry is invalid
#   2  usage error / bats not installed

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY=""
MODE="run"
SHARD_N=1
SHARD_M=1
# Per-suite wall-clock ceiling. Generous on purpose: the slowest suite in the
# repo takes ~200 s standalone and more under parallel load, and a slow suite
# must not be mistaken for a hung one. This exists so that a genuinely hung
# suite fails its shard in minutes instead of consuming the job's whole budget.
SUITE_TIMEOUT="${BATS_SUITE_TIMEOUT:-600}"

usage() {
    sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list)           MODE="list" ;;
        --check-registry) MODE="check-registry" ;;
        --root)
            [ $# -ge 2 ] || { echo "ERROR: --root requires an argument" >&2; exit 2; }
            ROOT="$2"; shift ;;
        --registry)
            [ $# -ge 2 ] || { echo "ERROR: --registry requires an argument" >&2; exit 2; }
            REGISTRY="$2"; shift ;;
        --shard)
            [ $# -ge 2 ] || { echo "ERROR: --shard requires an argument" >&2; exit 2; }
            case "$2" in
                [0-9]*/[0-9]*) ;;
                *) echo "ERROR: --shard expects N/M (e.g. 2/8), got '$2'" >&2; exit 2 ;;
            esac
            SHARD_N="${2%%/*}"
            SHARD_M="${2##*/}"
            shift ;;
        --timeout)
            [ $# -ge 2 ] || { echo "ERROR: --timeout requires an argument" >&2; exit 2; }
            case "$2" in
                ''|*[!0-9]*) echo "ERROR: --timeout expects seconds, got '$2'" >&2; exit 2 ;;
            esac
            SUITE_TIMEOUT="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[ -d "$ROOT" ] || { echo "ERROR: root not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$REGISTRY" ] || REGISTRY="${ROOT}/tests/bats-exclusions.yml"

if [ "$SHARD_M" -lt 1 ] || [ "$SHARD_N" -lt 1 ] || [ "$SHARD_N" -gt "$SHARD_M" ]; then
    echo "ERROR: invalid shard ${SHARD_N}/${SHARD_M}" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Registry parsing.
#
# Deliberately pure bash + grep/sed: the repo's other validators
# (check-security-policy.sh, check-body-english.sh) carry zero runtime
# dependencies so they run identically on a developer laptop and a bare CI
# runner. Pulling in yq here would make the test gate itself depend on a
# network install.
#
# Recognised shape (schema_version: 1):
#   entries:
#     - path: <repo-relative path>
#       reason: "<why>"
#       owner: <who>
#       follow_up: <task/issue ref>
#       added: YYYY-MM-DD
# ---------------------------------------------------------------------------

EXCLUDED_PATHS=()

parse_registry() {
    [ -f "$REGISTRY" ] || return 0
    local line key val
    while IFS= read -r line; do
        # Strip a trailing comment only when it is not inside quotes; entries
        # keep reasons quoted, so a naive strip would corrupt them. We only
        # need `path:` values here, which are never quoted.
        case "$line" in
            *-\ path:*|*path:*)
                key="${line%%:*}"
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key#- }"
                [ "$key" = "path" ] || continue
                val="${line#*:}"
                val="${val#"${val%%[![:space:]]*}"}"
                val="${val%"${val##*[![:space:]]}"}"
                val="${val%\"}"; val="${val#\"}"
                val="${val%\'}"; val="${val#\'}"
                [ -n "$val" ] && EXCLUDED_PATHS+=("$val")
                ;;
        esac
    done <"$REGISTRY"
}

is_excluded() {
    local candidate="$1" ex
    for ex in ${EXCLUDED_PATHS[@]+"${EXCLUDED_PATHS[@]}"}; do
        [ "$candidate" = "$ex" ] && return 0
    done
    return 1
}

# These suites are not excluded: their exact test inventory is partitioned by
# tests/customer-delivery-shards.tsv and executed by dedicated Linux/macOS
# matrices. Running the monolithic files here would reintroduce the >2 minute
# command the shard registry exists to eliminate.
is_managed_shard_suite() {
    case "$1" in
        dev-tools/tests/check-customer-delivery.bats|\
        dev-tools/tests/customer-delivery-schema.bats|\
        dev-tools/tests/customer-delivery-mutation.bats) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Registry validation. A stale entry (suite deleted or renamed) means a real
# suite may be silently skipped under a path nobody checks any more, so this is
# fail-closed.
# ---------------------------------------------------------------------------

check_registry() {
    local rc=0

    if [ ! -f "$REGISTRY" ]; then
        echo "ERROR: exclusion registry not found: $REGISTRY" >&2
        return 1
    fi

    if ! grep -qE '^schema_version:[[:space:]]*1[[:space:]]*$' "$REGISTRY"; then
        echo "ERROR: registry must declare 'schema_version: 1'" >&2
        rc=1
    fi

    local ex
    for ex in ${EXCLUDED_PATHS[@]+"${EXCLUDED_PATHS[@]}"}; do
        case "$ex" in
            /*|*..*)
                echo "ERROR: registry path must be repo-relative without '..': $ex" >&2
                rc=1
                continue ;;
        esac
        if [ ! -f "${ROOT}/${ex}" ]; then
            echo "ERROR: stale registry entry — no such suite: $ex" >&2
            echo "       Delete the entry (the suite is gone) or fix the path." >&2
            rc=1
        fi
    done

    # Every entry needs the full field set. Count field occurrences and compare
    # against the number of entries: a missing field shows up as a shortfall.
    local n_path n_reason n_owner n_follow n_added
    n_path=$(grep -cE '^[[:space:]]*-[[:space:]]+path:' "$REGISTRY" || true)
    n_reason=$(grep -cE '^[[:space:]]+reason:[[:space:]]*\S' "$REGISTRY" || true)
    n_owner=$(grep -cE '^[[:space:]]+owner:[[:space:]]*\S' "$REGISTRY" || true)
    n_follow=$(grep -cE '^[[:space:]]+follow_up:[[:space:]]*\S' "$REGISTRY" || true)
    n_added=$(grep -cE '^[[:space:]]+added:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$REGISTRY" || true)

    local field
    for field in "reason:$n_reason" "owner:$n_owner" "follow_up:$n_follow" "added:$n_added"; do
        if [ "${field##*:}" -ne "$n_path" ]; then
            echo "ERROR: registry has $n_path entries but ${field%%:*} appears ${field##*:} time(s)" >&2
            echo "       Every exclusion needs path + reason + owner + follow_up + added." >&2
            rc=1
        fi
    done

    if [ "$rc" -eq 0 ]; then
        echo "registry OK: $n_path exclusion(s), all paths resolve, all fields present"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
# Discovery.
# ---------------------------------------------------------------------------

discover() {
    local f rel
    while IFS= read -r f; do
        rel="${f#"${ROOT}"/}"
        is_excluded "$rel" && continue
        is_managed_shard_suite "$rel" && continue
        printf '%s\n' "$rel"
    # NOTE: filters are anchored to $ROOT. Do NOT add unanchored patterns like
    # `! -path '*/.worktrees/*'` — a checkout may itself live under such a
    # directory (git worktrees commonly do), in which case an unanchored filter
    # silently matches every file and discovery returns nothing.
    done < <(find "$ROOT" -type f -name '*.bats' \
                  ! -path "${ROOT}/.git/*" \
                  ! -path "${ROOT}/node_modules/*" | LC_ALL=C sort)
}

parse_registry

case "$MODE" in
    check-registry)
        check_registry
        exit $?
        ;;
    list)
        discover
        exit 0
        ;;
esac

command -v bats >/dev/null 2>&1 || {
    echo "ERROR: bats not installed" >&2
    exit 2
}

mapfile -t ALL_SUITES < <(discover)

if [ "${#ALL_SUITES[@]}" -eq 0 ]; then
    echo "ERROR: discovery found no bats suites under $ROOT — this is almost" >&2
    echo "       certainly a broken invocation, not an empty repo." >&2
    exit 2
fi

SUITES=()
for i in "${!ALL_SUITES[@]}"; do
    if [ $(( i % SHARD_M + 1 )) -eq "$SHARD_N" ]; then
        SUITES+=("${ALL_SUITES[$i]}")
    fi
done

echo "discovery: ${#ALL_SUITES[@]} suite(s) total, ${#SUITES[@]} in shard ${SHARD_N}/${SHARD_M}"
echo "excluded : ${#EXCLUDED_PATHS[@]} suite(s) per ${REGISTRY#"${ROOT}"/}"
echo "managed  : 3 suite(s) via tests/customer-delivery-shards.tsv"
echo

cd "$ROOT" || exit 2

FAILED=()
TIMED_OUT=()
PASSED=0
for suite in ${SUITES[@]+"${SUITES[@]}"}; do
    echo "--- bats ${suite}"
    timeout --signal=TERM --kill-after=30s "$SUITE_TIMEOUT" bats "$suite"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        PASSED=$(( PASSED + 1 ))
    elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "::error::suite exceeded ${SUITE_TIMEOUT}s: ${suite}"
        TIMED_OUT+=("$suite")
        FAILED+=("$suite")
    else
        FAILED+=("$suite")
    fi
done

echo
echo "==================== shard ${SHARD_N}/${SHARD_M} summary ===================="
echo "passed: ${PASSED}"
echo "failed: ${#FAILED[@]}"
echo "timeout: ${#TIMED_OUT[@]} (ceiling ${SUITE_TIMEOUT}s)"
if [ "${#FAILED[@]}" -gt 0 ]; then
    for suite in "${FAILED[@]}"; do
        echo "  FAIL ${suite}"
    done
    exit 1
fi
echo "OK"
exit 0

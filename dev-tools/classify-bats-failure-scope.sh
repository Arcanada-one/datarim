#!/usr/bin/env bash
# dev-tools/classify-bats-failure-scope.sh — workspace-hygiene auto-classifier
# for failing regression-invariant tests (deterministic, git-based).
#
# Compliance Step 6 (Test Execution) observes that a regression-invariant bats
# test failed — a test asserting that some scope directory is gate-clean (e.g.
# "skills/ scope is English-only"). The question is whether THIS task introduced
# the failure or whether it is foreign / parallel-session noise that landed in
# the shared workspace independently.
#
# Given the framework repo, a base ref (or explicit range), and one or more
# scope directories (the dir whose regression invariant the failing test
# asserts), this helper runs `git log <merge-base>..HEAD -- <scope>` per scope:
#
#   * EMPTY  -> the task's own commits did NOT touch that scope -> the failure is
#              pre-existing / foreign noise (auto-classify, NOT a block).
#   * NON-EMPTY -> the task DID commit into that scope -> the failure stays a
#              real regression (block). A real regression is never masked.
#
# Aggregate verdict / exit code:
#   0  every queried scope is "pre-existing" -> safe to auto-classify as foreign.
#   1  at least one scope is "regression"    -> at least one real block remains.
#   2  usage error OR a git probe could not be evaluated for a scope (fail-CLOSED:
#      an undeterminable scope is NEVER auto-classified as foreign, because this
#      classifier gates a verdict — an unknown must not relax a block).
#
# This is a pure read-only git/text classifier. No network calls, no eval.
# Portable ERE only (grep -E; no grep -P). shellcheck-clean.
#
# Usage:
#   classify-bats-failure-scope.sh [--repo <path>] [--base <ref> | --range <git-range>] \
#                                  --scope <dir> [--scope <dir> ...] [--quiet]
#   classify-bats-failure-scope.sh --help
#
# Flags:
#   --repo <path>    Framework repo to inspect (default: current directory).
#   --base <ref>     Base ref; range is merge-base(<ref>,HEAD)..HEAD (default: origin/main).
#   --range <range>  Explicit git range, overrides --base (e.g. abc123..HEAD).
#   --scope <dir>    Scope directory of a failing regression-invariant test.
#                    Repeatable; at least one is required.
#   --quiet          Suppress the per-scope report; exit code still carries the verdict.

set -eu

usage() {
    cat <<'EOF'
classify-bats-failure-scope.sh — git-based classifier for failing regression-invariant tests.

Usage:
  classify-bats-failure-scope.sh [--repo <path>] [--base <ref> | --range <git-range>] \
                                 --scope <dir> [--scope <dir> ...] [--quiet]

Flags:
  --repo <path>    Framework repo to inspect (default: current directory).
  --base <ref>     Base ref; range is merge-base(<ref>,HEAD)..HEAD (default: origin/main).
  --range <range>  Explicit git range, overrides --base.
  --scope <dir>    Scope directory of a failing regression-invariant test (repeatable, >=1 required).
  --quiet          Suppress the per-scope report; exit code still carries the verdict.

Exit:
  0  every scope pre-existing (auto-classify as foreign noise)
  1  >=1 scope is a real regression (block)
  2  usage error or undeterminable git probe (fail-closed: never auto-classify an unknown)
EOF
}

repo="."
base="origin/main"
range=""
quiet=0
scopes=()
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)  repo="${2:-}"; shift 2 ;;
        --base)  base="${2:-}"; shift 2 ;;
        --range) range="${2:-}"; shift 2 ;;
        --scope) scopes+=("${2:-}"); shift 2 ;;
        --quiet) quiet=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'classify-bats-failure-scope: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$repo" ] || { printf 'classify-bats-failure-scope: --repo cannot be empty\n' >&2; exit 2; }
[ -d "$repo" ] || { printf 'classify-bats-failure-scope: repo not found: %s\n' "$repo" >&2; exit 2; }
[ "${#scopes[@]}" -gt 0 ] || { printf 'classify-bats-failure-scope: at least one --scope is required\n' >&2; usage >&2; exit 2; }

# Resolve the range. Explicit --range wins; otherwise compute merge-base(base,HEAD)..HEAD.
# Fail closed (exit 2) if the range cannot be resolved — an unknown range must
# never let a scope be silently auto-classified as foreign.
if [ -z "$range" ]; then
    [ -n "$base" ] || { printf 'classify-bats-failure-scope: --base cannot be empty\n' >&2; exit 2; }
    if ! mb="$(git -C "$repo" merge-base "$base" HEAD 2>/dev/null)"; then
        printf 'classify-bats-failure-scope: cannot compute merge-base(%s, HEAD) in %s (fail-closed)\n' \
            "$base" "$repo" >&2
        exit 2
    fi
    range="$mb..HEAD"
fi

verdict_block=0   # set to 1 if any scope is a real regression

for scope in "${scopes[@]}"; do
    [ -n "$scope" ] || { printf 'classify-bats-failure-scope: --scope cannot be empty\n' >&2; exit 2; }
    # git log of commits in the range that touched this scope path. A git error
    # (bad range, unknown ref) is fail-CLOSED: we cannot prove the scope is
    # untouched, so we must not auto-classify it as foreign noise.
    if ! log="$(git -C "$repo" log --oneline "$range" -- "$scope" 2>/dev/null)"; then
        printf 'classify-bats-failure-scope: git log failed for scope %s over range %s in %s (fail-closed)\n' \
            "$scope" "$range" "$repo" >&2
        exit 2
    fi

    if [ -z "$log" ]; then
        [ "$quiet" -eq 0 ] && printf 'pre-existing  %s  (0 task commits in %s)\n' "$scope" "$range"
    else
        verdict_block=1
        if [ "$quiet" -eq 0 ]; then
            n_commits="$(printf '%s\n' "$log" | grep -Ec '.')"
            printf 'regression    %s  (%s task commit(s) in %s)\n' "$scope" "$n_commits" "$range"
        fi
    fi
done

# Defensive invariant: wording above is bound to verdict_block; the exit code
# below must match (per CLAUDE.md § Defensive Invariants for state<->wording
# contracts).
if [ "$verdict_block" -ne 0 ] && [ "$verdict_block" -ne 1 ]; then
    printf 'classify-bats-failure-scope: internal invariant violated: verdict_block=%s\n' "$verdict_block" >&2
    exit 2
fi

exit "$verdict_block"

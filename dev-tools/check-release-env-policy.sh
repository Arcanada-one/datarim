#!/usr/bin/env bash
#
# check-release-env-policy.sh — validate the version-controlled GitHub
# deployment-environment policy declaration and (optionally) detect drift
# against the live repo.
#
# COMPANION DATA FILE: .github/environments-policy.yml — the declared
# source of truth for the release environments' deployment-branch-policy
# (both release environments must allow the `v*` TAG pattern, else every
# tagged release is rejected at job start). Repo-recreate recipe lives in
# that file's header; the apply-side tool is
# dev-tools/provision-release-env.sh.
#
# MODES
#   --check              Validate the policy file only (pure shell, no
#                        network). Exit 0 PASS / 1 FAIL. Checks:
#                          - file exists, schema_version: 1
#                          - both release-auto and release-manual declared
#                          - each has custom_branch_policies: true
#                          - each has at least one tag pattern, incl. v*
#   --live               Additionally compare the live policy via `gh api
#                        repos/<owner/name>/environments/<env>/deployment-branch-policies`.
#                        ADVISORY (fail-soft): missing gh, missing token, or
#                        API failure prints a NOTE and exits 0; detected
#                        drift prints DRIFT lines and exits 0 unless
#                        --strict is given (then exit 1).
#   --repo <owner/name>  Repo slug for --live (default: $GITHUB_REPOSITORY).
#   --strict             Make live drift a hard failure (exit 1).
#
# Testability: the GitHub API command is injected via GH_API_CMD (default
# `gh api`), mirroring provision-release-env.sh.
#
# Exit: 0 PASS/advisory, 1 FAIL (file invalid, or drift under --strict),
#       2 usage error.

set -euo pipefail

POLICY_FILE=".github/environments-policy.yml"
DO_LIVE=0
STRICT=0
REPO="${GITHUB_REPOSITORY:-}"
GH_API_CMD="${GH_API_CMD:-gh api}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)  shift ;;
        --live)   DO_LIVE=1; shift ;;
        --strict) STRICT=1; shift ;;
        --repo)   REPO="${2:-}"; shift 2 ;;
        --file)   POLICY_FILE="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

fail=0

if [[ ! -f "$POLICY_FILE" ]]; then
    echo "FAIL: policy file missing: $POLICY_FILE"
    exit 1
fi

# ── File validation (pure shell) ─────────────────────────────────────────────

if ! grep -qE '^schema_version:[[:space:]]*1[[:space:]]*$' "$POLICY_FILE"; then
    echo "FAIL: schema_version: 1 not declared in $POLICY_FILE"
    fail=1
fi

# extract_env_block <env-name> → the indented block under `  <env-name>:`.
extract_env_block() {
    awk -v env="  $1:" '
        $0 == env { in_env = 1; next }
        in_env && /^  [a-zA-Z]/ { in_env = 0 }
        in_env { print }
    ' "$POLICY_FILE"
}

for env_name in release-auto release-manual; do
    block="$(extract_env_block "$env_name")"
    if [[ -z "$block" ]]; then
        echo "FAIL: environment '$env_name' not declared in $POLICY_FILE"
        fail=1
        continue
    fi
    if ! grep -qE '^[[:space:]]+custom_branch_policies:[[:space:]]*true' <<< "$block"; then
        echo "FAIL: $env_name: custom_branch_policies must be true (tags cannot deploy under protected-branches-only)"
        fail=1
    fi
    if ! grep -qE '^[[:space:]]+-[[:space:]]*"?v\*"?[[:space:]]*$' <<< "$block"; then
        echo "FAIL: $env_name: tag_patterns must include the v* pattern"
        fail=1
    fi
done

if [[ "$fail" -ne 0 ]]; then
    echo "RESULT: FAIL — $POLICY_FILE does not declare a valid release environment policy"
    exit 1
fi
echo "policy file OK: $POLICY_FILE"

# ── Live drift comparison (advisory by default) ──────────────────────────────

if [[ "$DO_LIVE" -eq 1 ]]; then
    drift=0
    live_skipped=0
    gh_bin="${GH_API_CMD%% *}"
    if ! command -v "$gh_bin" >/dev/null 2>&1; then
        echo "NOTE: '$gh_bin' not available — skipping live drift comparison (advisory)."
        live_skipped=1
    elif [[ -z "$REPO" ]]; then
        echo "NOTE: no --repo and GITHUB_REPOSITORY unset — skipping live drift comparison (advisory)."
        live_skipped=1
    elif [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        echo "FAIL: --repo must be <owner/name>: '$REPO'" >&2
        exit 2
    fi

    if [[ "$live_skipped" -eq 0 ]]; then
        for env_name in release-auto release-manual; do
            # shellcheck disable=SC2086  # GH_API_CMD is a trusted, space-split command prefix
            if ! live="$($GH_API_CMD "repos/${REPO}/environments/${env_name}/deployment-branch-policies" 2>/dev/null)"; then
                echo "NOTE: could not read live policy for '$env_name' (no token / no access) — advisory skip."
                continue
            fi
            # Expect a policy entry {"name":"v*","type":"tag"} (key order and
            # whitespace vary; match both fields independently on one entry).
            if grep -qE '"name":[[:space:]]*"v\*"' <<< "$live" \
               && grep -qE '"type":[[:space:]]*"tag"' <<< "$live"; then
                echo "live OK: $env_name allows the v* tag pattern"
            else
                echo "DRIFT: $env_name live deployment-branch-policy lacks the v* TAG pattern declared in $POLICY_FILE"
                echo "       fix: dev-tools/provision-release-env.sh --repo $REPO --env $env_name --apply"
                drift=1
            fi
        done
    fi

    if [[ "$drift" -eq 1 && "$STRICT" -eq 1 ]]; then
        echo "RESULT: FAIL — live policy drifted (strict mode)"
        exit 1
    fi
    if [[ "$drift" -eq 1 ]]; then
        echo "RESULT: PASS (advisory — drift reported above; re-run with --strict to fail)"
        exit 0
    fi
fi

echo "RESULT: PASS"
exit 0

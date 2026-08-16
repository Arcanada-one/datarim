#!/usr/bin/env bash
# check-class-b-not-shipped.sh — ship-time gate: class-b ops scripts MUST NOT
# live in the framework tree.
#
# Background. Consumer workspaces classify Datarim-adjacent scripts by owner:
#
#   class-a  framework-owned, ships here, installed by install.sh
#   class-b  workspace-owned ops scripts (site policy, host topology, dispatch)
#            -- canonical in the consumer's own repo, NEVER shipped from here
#
# The rule already existed as prose and was silently violated: an
# execution-host PreToolUse guard was added to this repo, so two writable
# copies of one ENFORCEMENT artefact existed with no sync mechanism. They
# drifted. The stale public copy then shadowed the good private one on a
# consumer host and denied every task ON ITS OWN declared execution host,
# while a second host had no protection at all. A rule with no enforcement
# is not a control -- hence this gate.
#
# The distinction this encodes: MECHANISM ships, POLICY does not.
# A resolver that answers "which host is declared for this workspace" is
# generic and useful to any consumer. A hook that DECIDES that work on
# another host is forbidden encodes one operator's topology, and for a
# single-machine user it can only ever deny.
#
# Scope: this repo's dev-tools/ tree. The denylist below is intentionally
# explicit rather than pattern-based -- a heuristic ("anything named
# *-guard.sh") would misfire on legitimate class-a validators such as
# branch-integration-guard.sh, which IS framework-generic.
#
# Usage:
#   check-class-b-not-shipped.sh [--root <repo-root>]
#
# Exit codes:
#   0  PASS -- no class-b script present in the framework tree
#   1  FAIL -- at least one class-b script found (prints each)
#   2  usage error
# shellcheck shell=bash
set -euo pipefail

ROOT=""

usage() {
    cat <<'EOF'
Usage: check-class-b-not-shipped.sh [--root <repo-root>]

Fails when a workspace-owned (class-b) ops script is present in the
framework's dev-tools/ tree. Such scripts are canonical in the consumer
workspace repo; shipping a second copy here creates an unsynchronised
duplicate of an enforcement artefact.

Exit: 0 PASS | 1 FAIL (class-b script shipped) | 2 usage error
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'check-class-b-not-shipped: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
[ -d "$ROOT" ] || { printf 'check-class-b-not-shipped: not a directory: %s\n' "$ROOT" >&2; exit 2; }

# Class-b denylist. Keep in sync with the consumer-side declaration
# (`space.yml § datarim_fleet.class_b_scripts` in the Arcanada workspace).
# Each entry is a basename that must NOT exist under <root>/dev-tools/.
CLASS_B_SCRIPTS=(
    datarim-exec-guard.sh
    datarim-dispatch.sh
    datarim-dispatch-wrapper.sh
    check-dispatch-drift.sh
)

FINDINGS=0
for name in "${CLASS_B_SCRIPTS[@]}"; do
    path="$ROOT/dev-tools/$name"
    if [ -e "$path" ]; then
        FINDINGS=$((FINDINGS + 1))
        printf 'FINDING: class-b script shipped by the framework: dev-tools/%s\n' "$name" >&2
    fi
done

if [ "$FINDINGS" -gt 0 ]; then
    cat >&2 <<'EOF'

Class-b scripts are owned by the consumer workspace, not by this framework.
Shipping a copy here creates a second writable copy of an enforcement
artefact with no sync mechanism -- the defect this gate exists to prevent.

Fix: delete the file from this repo. The canonical copy lives in the
consumer workspace's own dev-tools/. If a consumer needs it on a host that
has no workspace checkout, deliver it from the workspace, not from here.

Generic mechanism (resolver, drift checker, tests) stays here by design.
EOF
    exit 1
fi

printf 'OK: no class-b script shipped by the framework (%d checked)\n' "${#CLASS_B_SCRIPTS[@]}"
exit 0

#!/usr/bin/env bash
# dev-tools/check-deploy-class.sh — deploy-class classifier (the prod-readiness gate trigger).
#
# Decides whether a task touches a deployment surface that warrants the
# prod-readiness gate (skills/prod-readiness-probe/SKILL.md). It inspects the
# task-description text and, optionally, a list of changed paths for
# deploy-surface indicators: systemd unit files, sudoers fragments, CI cutover
# jobs, or .env-deploy templates.
#
# This is a pure read-only text classifier. It performs no network calls and
# evaluates no input as code.
#
# Usage:
#   check-deploy-class.sh --task-description <path> [--changed-paths <file>]
#   check-deploy-class.sh --help
#
# Exit codes:
#   0   deploy-class   (gate MUST arm)
#   1   not deploy-class (gate SKIP)
#   2   usage error

set -eu

usage() {
    cat <<'EOF'
check-deploy-class.sh — classify whether a task touches a deploy surface.

Usage:
  check-deploy-class.sh --task-description <path> [--changed-paths <file>]

Exit: 0 deploy-class | 1 not deploy-class | 2 usage error
EOF
}

td=""
changed=""
while [ $# -gt 0 ]; do
    case "$1" in
        --task-description) td="${2:-}"; shift 2 ;;
        --changed-paths) changed="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'check-deploy-class: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$td" ] || { printf 'check-deploy-class: --task-description is required\n' >&2; exit 2; }
[ -f "$td" ] || { printf 'check-deploy-class: file not found: %s\n' "$td" >&2; exit 2; }

# Deploy-surface indicators (case-insensitive, fixed-string-ish ERE). Keep this
# list in sync with the prod-readiness-probe skill's "deploy surface" definition.
# Each pattern is a literal substring matched anywhere in the inspected text.
indicators='sudoers|systemd|\.service\b|systemctl|\.env-deploy|deploy:production|cutover|deploy-runner|prod-runner|/etc/sudoers'

matches() {
    # grep over a file as DATA (-F-like safety via -E with a fixed pattern var,
    # no expansion of the file content as code). -i case-insensitive, -q quiet.
    grep -Eiq -- "$indicators" "$1"
}

if matches "$td"; then
    exit 0
fi

if [ -n "$changed" ] && [ -f "$changed" ] && matches "$changed"; then
    exit 0
fi

exit 1

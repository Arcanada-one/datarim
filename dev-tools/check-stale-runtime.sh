#!/usr/bin/env bash
# dev-tools/check-stale-runtime.sh — stale-runtime reminder (advisory, non-blocking).
#
# Single source of truth for the "your other Datarim installs are now stale"
# advisory. Given a framework repo and a commit range, it detects whether the
# range touched a shipped script (scripts/lib/*.sh) or a shipped skill
# (skills/*/SKILL.md). If so, it prints a generic, infra-agnostic advisory and
# exits 0. If nothing shipped changed, it is silent and exits 0.
#
# The advisory is intentionally infra-agnostic for public-OSS consumers: it
# names NO hosts and NO specific update command. Each consumer owns its own
# topology and update mechanism.
#
# This is a pure read-only git/text detector. It performs no network calls and
# evaluates no input as code. Portable ERE only (grep -E; no grep -P).
#
# Usage:
#   check-stale-runtime.sh [--repo <path>] [--range <git-range>] [--quiet]
#   check-stale-runtime.sh --help
#
# Flags:
#   --repo <path>    Framework repo to inspect (default: current directory).
#   --range <range>  Git commit range to diff (default: HEAD~1..HEAD).
#   --quiet          Suppress the advisory text; exit code still reflects detection.
#
# Exit codes:
#   0   normal (advisory printed when a shipped surface changed, else silent).
#   3   git probe failed (range/repo unreadable) — fail-open: advisory NOT emitted,
#       caller should treat as "could not determine" and proceed (non-blocking).
#   2   usage error.

set -eu

usage() {
    cat <<'EOF'
check-stale-runtime.sh — advisory when a shipped script/skill changed in a range.

Usage:
  check-stale-runtime.sh [--repo <path>] [--range <git-range>] [--quiet]

Flags:
  --repo <path>    Framework repo to inspect (default: current directory).
  --range <range>  Git commit range to diff (default: HEAD~1..HEAD).
  --quiet          Suppress advisory text; exit code still reflects detection.

Exit: 0 normal (silent or advisory) | 3 git probe failed (fail-open) | 2 usage error
EOF
}

repo="."
range="HEAD~1..HEAD"
quiet=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)  repo="${2:-}"; shift 2 ;;
        --range) range="${2:-}"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'check-stale-runtime: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$repo" ]  || { printf 'check-stale-runtime: --repo cannot be empty\n' >&2; exit 2; }
[ -n "$range" ] || { printf 'check-stale-runtime: --range cannot be empty\n' >&2; exit 2; }
[ -d "$repo" ]  || { printf 'check-stale-runtime: repo not found: %s\n' "$repo" >&2; exit 2; }

# Collect changed paths for the range. Fail-open: any git error (not a repo,
# unknown range, shallow clone without HEAD~1) is a non-blocking "unknown" —
# we must never hard-block an otherwise-clean pipeline step on a git hiccup.
if ! changed="$(git -C "$repo" diff --name-only "$range" 2>/dev/null)"; then
    printf 'check-stale-runtime: git diff failed for range %s in %s (fail-open, advisory skipped)\n' \
        "$range" "$repo" >&2
    exit 3
fi

# Shipped-surface detector. Portable ERE (no grep -P). Matches a shipped script
# under scripts/lib/ or a shipped skill SKILL.md, anchored to a path segment so
# nested or top-level occurrences both match.
shipped_re='(^|/)scripts/lib/[^/]+\.sh$|(^|/)skills/[^/]+/SKILL\.md$'

if printf '%s\n' "$changed" | grep -Eq "$shipped_re"; then
    if [ "$quiet" -eq 0 ]; then
        cat <<'EOF'
Advisory — update your Datarim installs.
This task changed one or more shipped scripts or skills. If you run Datarim on
multiple machines, the change is currently present only where you committed it.
Update your Datarim install(s) on every machine per your topology so the change
is not stranded on a single box. This reminder is non-blocking — proceed after
noting it.
EOF
    fi
    exit 0
fi

# Nothing shipped changed: silent success.
exit 0

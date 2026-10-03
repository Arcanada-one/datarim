#!/usr/bin/env bash
# dev-tools/check-db-relocation-class.sh — DB relocation/decommission task classifier.
#
# Decides whether a task is a DB relocation or decommission task, which arms
# the dead-IP consumer sweep gate. Inspects the task-description text for
# type-field or keyword+DB-host co-occurrence indicators.
#
# Mirrors check-deploy-class.sh idiom: pure read-only text classifier,
# no network calls, no eval of input content.
#
# Usage:
#   check-db-relocation-class.sh --task-description <path>
#   check-db-relocation-class.sh --help
#
# Exit codes:
#   0   db-relocation-class   (dead-IP sweep gate MUST arm)
#   1   not db-relocation-class (gate SKIP)
#   2   usage error

set -eu

usage() {
    cat <<'EOF'
check-db-relocation-class.sh — classify whether a task is a DB relocation/decommission.

Usage:
  check-db-relocation-class.sh --task-description <path>

Exit: 0 db-relocation-class | 1 not db-relocation-class | 2 usage error
EOF
}

td=""
while [ $# -gt 0 ]; do
    case "$1" in
        --task-description) td="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'check-db-relocation-class: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$td" ] || { printf 'check-db-relocation-class: --task-description is required\n' >&2; exit 2; }
[ -f "$td" ] || { printf 'check-db-relocation-class: file not found: %s\n' "$td" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Prong 1: type field match in frontmatter.
# Matches: type: db-relocation  OR  type: db-decommission
# ---------------------------------------------------------------------------
type_pattern='^type:[[:space:]]*(db-relocation|db-decommission)[[:space:]]*$'
if grep -Eiq -- "$type_pattern" "$td"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Prong 2: explicit decommissioned_ip frontmatter field.
# This is the authoritative real-relocation signal. A task that genuinely
# retires a DB host declares the dead address as structured frontmatter, and
# the sweep needs that field anyway (Step 0.35.1). Keying arming on the field
# — rather than on relocate/decommission keywords co-occurring with a port in
# free prose — prevents a gate/runbook task that merely *describes* the
# relocation pattern from arming the sweep against itself (false positive).
# ---------------------------------------------------------------------------
decommissioned_ip_pattern='^decommissioned_ip:[[:space:]]*[^[:space:]]'
if grep -Eiq -- "$decommissioned_ip_pattern" "$td"; then
    exit 0
fi

exit 1

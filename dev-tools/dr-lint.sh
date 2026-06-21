#!/usr/bin/env bash
# dr-lint.sh — umbrella façade over the spec-traceability rule registry (R4).
#
# One public entry point over the named-rule registry (dr-spec-rules.yaml) and
# the validators that implement those rules. Today it dispatches to dr-spec-lint;
# future validators register their rules in the same yaml and plug in here by
# rule namespace — the registry, mandatory-rule config, and exit contract are
# shared, so callers (CI, pre-commit) target one surface.
#
# Subcommands / usage:
#   dr-lint.sh rules [--format json|text]      # introspect the registry
#   dr-lint.sh --task <ID> [--root <path>] [--format json|text]
#              [--rules a,b] [--ignore c,d] [--advisory] [--dry-run]
#              [--scope all|git-diff]
#
# Configuration-error semantics (R4): unknown rule id, an empty effective rule
# set after --rules/--ignore filtering, or an attempt to --ignore a mandatory
# rule all exit 2 — NEVER reported as "0 violations". These are enforced in the
# shared loader (effective_ruleset) so every façade caller inherits them.
#
# Exit: 0 clean / 1 violations (hard) / 2 usage-or-configuration error.
# Contract: docs/validator-contract.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/../scripts/lib/spec-graph.sh"
RULES_FILE="${SCRIPT_DIR}/dr-spec-rules.yaml"
SPEC_LINT="${SCRIPT_DIR}/dr-spec-lint.sh"

if [ ! -f "$LIB" ]; then
    echo "ERROR: shared lib not found: $LIB" >&2
    exit 2
fi
# shellcheck source=scripts/lib/spec-graph.sh
. "$LIB"

load_rules "$RULES_FILE"

# ---------------------------------------------------------------------------
# `rules` introspection subcommand.
# ---------------------------------------------------------------------------

if [ "${1:-}" = "rules" ]; then
    shift
    fmt="text"
    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                shift
                [ $# -gt 0 ] || usage_die "--format requires a value (json|text)"
                case "$1" in json|text) fmt="$1" ;; *) usage_die "invalid --format: $1" ;; esac
                shift ;;
            *) usage_die "unknown argument to 'rules': $1" ;;
        esac
    done

    if [ "$fmt" = "json" ]; then
        # Build a JSON array from the parallel registry arrays.
        out='{"rules":['
        first=1
        for i in "${!SPEC_RULE_IDS[@]}"; do
            rid="${SPEC_RULE_IDS[$i]}"
            sev="${SPEC_RULE_SEVERITY[$i]}"
            man="${SPEC_RULE_MANDATORY[$i]}"
            [ "$man" = "true" ] && manj="true" || manj="false"
            entry="$(python3 - "$rid" "$sev" "$manj" <<'PYEOF'
import json, sys
rid, sev, man = sys.argv[1:4]
print(json.dumps({"id": rid, "severity": sev, "mandatory": man == "true"}))
PYEOF
)"
            if [ "$first" -eq 1 ]; then first=0; else out="${out},"; fi
            out="${out}${entry}"
        done
        out="${out}]}"
        printf '%s\n' "$out"
    else
        printf '%-24s %-9s %s\n' "RULE" "SEVERITY" "MANDATORY"
        for i in "${!SPEC_RULE_IDS[@]}"; do
            printf '%-24s %-9s %s\n' \
                "${SPEC_RULE_IDS[$i]}" "${SPEC_RULE_SEVERITY[$i]}" "${SPEC_RULE_MANDATORY[$i]}"
        done
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Lint dispatch. Parse the shared flags to validate the rule selection up front
# (mandatory-rule guard / unknown rule / empty effective set all exit 2 here),
# then delegate the actual graph check to dr-spec-lint with the same selection.
# ---------------------------------------------------------------------------

parse_common_flags "$@"
if [ "${#SPEC_REMAINING_ARGS[@]}" -gt 0 ]; then
    usage_die "unexpected argument: ${SPEC_REMAINING_ARGS[0]}"
fi
[ -n "$SPEC_TASK" ] || usage_die "--task <ID> is required (or use the 'rules' subcommand)"

# Validate rule selection against the registry — this is the R4 fail-closed gate.
effective_ruleset

if [ ! -f "$SPEC_LINT" ]; then
    usage_die "dr-spec-lint.sh not found: $SPEC_LINT"
fi

# Re-build the delegate argv (the registry validation above already vetted the
# selection; dr-spec-lint re-validates via the same shared loader).
delegate=(--task "$SPEC_TASK" --format "$SPEC_FORMAT")
[ -n "$SPEC_ROOT" ] && delegate+=(--root "$SPEC_ROOT")
[ -n "$SPEC_RULES_INCLUDE" ] && delegate+=(--rules "$SPEC_RULES_INCLUDE")
[ -n "$SPEC_RULES_IGNORE" ] && delegate+=(--ignore "$SPEC_RULES_IGNORE")
[ "$SPEC_ADVISORY" -eq 1 ] && delegate+=(--advisory)
[ "$SPEC_DRY_RUN" -eq 1 ] && delegate+=(--dry-run)
[ "$SPEC_SCOPE" = "git-diff" ] && delegate+=(--scope git-diff)
[ "$SPEC_STAGE" != "all" ] && delegate+=(--stage "$SPEC_STAGE")
[ "$SPEC_REPORT" -eq 1 ] && delegate+=(--report)

bash "$SPEC_LINT" "${delegate[@]}"
exit $?

#!/usr/bin/env bash
# dev-tools/check-deploy-readiness.sh — validator for the project-authored
# deploy-readiness.yml contract consumed by the prod-readiness gate.
#
# The contract is OPTIONAL and PROJECT-AUTHORED (not shipped by the framework).
# Schema and rationale: skills/prod-readiness-probe/SKILL.md § Contract schema.
# Precedent: accepted-risk.yml + ecosystem-sync/registry.yml (awk-friendly,
# shell-validated, secrets-forbidden).
#
# SECURITY: the file is untrusted input. It is read line-by-line as DATA only —
# no eval, no command substitution, no expansion of file content. (Security
# Mandate S1/S5.)
#
# Usage:
#   check-deploy-readiness.sh --validate-yaml <path>
#   check-deploy-readiness.sh --help
#
# Exit codes:
#   0   valid contract
#   1   validation failure
#   2   usage error

set -eu

usage() {
    cat <<'EOF'
check-deploy-readiness.sh — validate a project-local deploy-readiness.yml.

Usage:
  check-deploy-readiness.sh --validate-yaml <path>

Exit: 0 valid | 1 invalid | 2 usage error
EOF
}

mode=""
file=""
while [ $# -gt 0 ]; do
    case "$1" in
        --validate-yaml) mode="validate"; file="${2:-}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'check-deploy-readiness: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ "$mode" = "validate" ] || { usage >&2; exit 2; }
[ -n "$file" ] || { printf 'check-deploy-readiness: --validate-yaml requires a path\n' >&2; exit 2; }
[ -f "$file" ] || { printf 'check-deploy-readiness: file not found: %s\n' "$file" >&2; exit 2; }

fail() { printf 'INVALID: %s\n' "$1" >&2; exit 1; }

# Rule 2 — secret prohibition. Reject credential-like keys anywhere.
if grep -Eiq -- '(^|[[:space:]])(password|secret|token|private_key|api[_-]?key|passwd|credential)[[:space:]]*:' "$file"; then
    fail "secret-like key present (Rule 2: secrets forbidden)"
fi

# Rule 1 (partial) — no inline flow-maps / flow-sequences.
if grep -Eq -- '[:-][[:space:]]*[\[{]' "$file"; then
    fail "inline flow-map/flow-sequence present (Rule 1: awk-friendly block style only)"
fi

# Rule 3 — runner cardinality: top-level runners map MUST contain exactly test + prod.
# Detect 4-space-indented direct children of `runners:` (the runner names).
have_test=0
have_prod=0
in_runners=0
extra_runner=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        "runners:"*) in_runners=1; continue ;;
    esac
    if [ "$in_runners" -eq 1 ]; then
        # a new top-level key (no leading space, ends with ':') closes the runners block
        case "$line" in
            [!\ ]*:*) in_runners=0; continue ;;
        esac
        # runner name = exactly two-space indent + name + ':'
        case "$line" in
            "  "[!\ ]*:*)
                rn="${line#  }"; rn="${rn%%:*}"
                case "$rn" in
                    test) have_test=1 ;;
                    prod) have_prod=1 ;;
                    *) extra_runner="$rn" ;;
                esac
                ;;
        esac
    fi
done < "$file"

[ "$have_test" -eq 1 ] || fail "runner 'test' missing (Rule 3: exactly {test, prod})"
[ "$have_prod" -eq 1 ] || fail "runner 'prod' missing (Rule 3: exactly {test, prod})"
[ -z "$extra_runner" ] || fail "unexpected runner '$extra_runner' (Rule 3: exactly {test, prod})"

# Rule 4 — required_sudoers command-shape allow-list. Every list item under a
# required_sudoers: block must begin with an allow-listed stem. Items are read
# as DATA — never executed.
in_sudoers=0
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        *"required_sudoers:"*) in_sudoers=1; continue ;;
    esac
    if [ "$in_sudoers" -eq 1 ]; then
        # any non-list-item line (next key) ends the block
        case "$line" in
            *"- "*) : ;;            # still a list item
            *) in_sudoers=0; continue ;;
        esac
        item="${line#*- }"
        # strip a single leading quote if present (data only)
        stem="${item%% *}"
        case "$stem" in
            systemctl|cp|mkdir|journalctl) : ;;
            *) fail "disallowed sudoers stem '$stem' (Rule 4: allow-list systemctl|cp|mkdir|journalctl)" ;;
        esac
    fi
done < "$file"

# Rule 6 — version floors must start with '>= '.
if grep -Eq -- '^[[:space:]]+(node|redis|python|go):[[:space:]]' "$file"; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *"node:"*|*"redis:"*|*"python:"*|*"go:"*)
                # value after the colon
                val="${line#*: }"
                # tolerate surrounding quotes
                val="${val%\"}"; val="${val#\"}"
                case "$val" in
                    ">= "*) : ;;
                    *) fail "version floor must start with '>= ': $line (Rule 6)" ;;
                esac
                ;;
        esac
    done < "$file"
fi

printf 'VALID\n'
exit 0

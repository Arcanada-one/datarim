#!/usr/bin/env bash
# dev-tools/check-coworker-file-flags.sh — Security S1 static check.
#
# Verifies that no coworker invocation in the plugin passes free-form DATA
# (skill body, eval dataset, operator text) as an inline string literal.
# Bulk/free-form content MUST travel via file flags: --context (write) /
# --paths (ask). A short constant instruction in --spec/--question is allowed;
# a long inline literal or a variable interpolation is flagged.
#
# argv[1] = plugin root (default: the plugin dir this script lives in).
# exit 0 = clean, exit 1 = a violation found, exit 2 = usage / no dir.

set -o pipefail

PLUGIN_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -d "$PLUGIN_ROOT" ] || { echo "check-coworker-file-flags: not a dir: $PLUGIN_ROOT" >&2; exit 2; }

# A coworker line is suspicious when --spec/--question carries either:
#   - a variable interpolation  ($VAR or ${VAR})  → free-form data inline
#   - a long literal (> 120 chars between the quotes) → likely bulk content
# Short constant instructions are fine.
violations=0
while IFS= read -r script; do
    [ -n "$script" ] || continue
    lineno=0
    while IFS= read -r line; do
        lineno=$((lineno + 1))
        case "$line" in
            *coworker\ write*|*coworker\ ask*) ;;
            *) continue ;;
        esac
        # Extract the argument to --spec or --question, if present.
        arg=$(printf '%s' "$line" | sed -nE 's/.*--(spec|question)[[:space:]]+"([^"]*)".*/\2/p')
        [ -n "$arg" ] || continue
        if printf '%s' "$arg" | grep -q '\$'; then
            echo "$script:$lineno: coworker --spec/--question carries a variable (free-form data must use --context/--paths)" >&2
            violations=$((violations + 1))
        elif [ "${#arg}" -gt 120 ]; then
            echo "$script:$lineno: coworker --spec/--question literal >120 chars (bulk content must use --context/--paths)" >&2
            violations=$((violations + 1))
        fi
    done < "$script"
done < <(find "$PLUGIN_ROOT" -type f -name '*.sh')

[ "$violations" -eq 0 ] || exit 1
exit 0

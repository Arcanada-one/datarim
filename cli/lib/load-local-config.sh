#!/usr/bin/env bash
# cli/lib/load-local-config.sh — generic personal-config loader.
#
# Reads KEY=value pairs from:
#   ${DATARIM_LOCAL:-$HOME/.claude/local}/config/personal.env
#
# Contract:
#   - File absent or unreadable → return 0 silently (fail-soft).
#   - Keys validated against [A-Za-z_][A-Za-z0-9_]* — invalid keys are
#     silently skipped (no exec, no eval, no source).
#   - Values parsed with `while IFS='=' read` — NO shell execution.
#     One layer of surrounding single- or double-quotes is stripped.
#   - shellcheck-clean; safe to source from any parent script.
#
# Usage:
#   source cli/lib/load-local-config.sh
#   load_local_config   # idempotent, no args

load_local_config() {
    local local_root file key val rest
    local_root="${DATARIM_LOCAL:-$HOME/.claude/local}"
    file="${local_root}/config/personal.env"

    # Fail-soft: missing or unreadable file is not an error.
    [ -f "$file" ] && [ -r "$file" ] || return 0

    while IFS= read -r _line || [ -n "$_line" ]; do
        # Skip blank lines and comments.
        case "$_line" in
            ''|'#'*) continue ;;
        esac

        # Split on first '=' only.
        key="${_line%%=*}"
        val="${_line#*=}"

        # Validate key: must match [A-Za-z_][A-Za-z0-9_]*
        # Use a case-match that avoids grep -P (BSD incompatible).
        case "$key" in
            [A-Za-z_]*) : ;;
            *) continue ;;
        esac
        # Reject keys with non-identifier characters after first char.
        # Strip valid chars; if anything remains, key is invalid.
        rest="$(printf '%s' "$key" | tr -d 'A-Za-z0-9_')"
        [ -n "$rest" ] && continue

        # Strip one layer of surrounding quotes (single or double).
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac

        export "$key=$val"
    done < "$file"

    return 0
}

# Allow direct execution for quick smoke test (not normally invoked).
case "${BASH_SOURCE[0]:-$0}" in
    "$0")
        load_local_config
        echo "[load-local-config] done (exit $?)"
        ;;
esac

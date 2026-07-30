#!/usr/bin/env bash
# lib/redact.sh — redaction layer for action traces before they leave the fleet.
#
# The audit-log source-adapter feeds agent action traces to an external LLM via
# `coworker`. Those traces (reason/command fields) may embed sensitive material
# — secrets, absolute filesystem paths, mesh hostnames/IPs, ssh targets. This
# layer scrubs them BEFORE emission (Security S1), modelled on the deny-pattern
# style of the coworker hook-guard: fail-closed and conservative — over-redaction
# is safe, a leaked token is not.
#
# Function:
#   redact_trace <string>   — print the string with sensitive tokens replaced by
#                             <REDACTED> / <PATH> / <HOST> placeholders and the
#                             result capped at 1000 chars.
#
# Portability: character-class key spelling instead of the GNU-only `s///I`
# flag, and no `\b` word boundaries — both diverge on BSD/macOS sed.

set -o pipefail

# Ordered passes matter: secrets first (so a `token=/a/path` value is elided
# whole before the path pass runs), then paths, then network identifiers, then
# ssh user@host targets, then bare mesh hostnames.
redact_trace() {
    local s="${1:-}"
    s="${s:0:1000}"
    printf '%s' "$s" \
        | sed -E \
            -e 's/([Pp][Aa][Ss][Ss][Ww]?[Oo]?[Rr]?[Dd]?|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Kk][Ee][Yy])[[:space:]]*[=:][[:space:]]*[^[:space:]"'"'"']+/\1=<REDACTED>/g' \
            -e 's/[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+[^[:space:]"'"'"']+/Bearer <REDACTED>/g' \
            -e 's/(ghp_|gho_|ghs_|ghr_|ghu_|github_pat_|xox[baprs]-|sk-|AKIA|ASIA)[A-Za-z0-9_-]+/<REDACTED>/g' \
            -e 's#(/(home|Users|root|var|etc|opt|tmp|usr|srv|mnt|private|data)/[^[:space:]"'"'"']*)#<PATH>#g' \
            -e 's#~/[^[:space:]"'"'"']*#<PATH>#g' \
            -e 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/<HOST>/g' \
            -e 's/[A-Za-z0-9._-]+@[A-Za-z0-9._-]+/<HOST>/g' \
            -e 's/[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(ai|com|club|org|net|group|online|app|wiki|io|dev|local)([:/][^[:space:]]*)?/<HOST>/g' \
            -e 's/arcana-[A-Za-z0-9-]+/<HOST>/g'
}

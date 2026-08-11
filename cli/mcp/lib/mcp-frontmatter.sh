#!/usr/bin/env bash
# mcp-frontmatter.sh — tolerant YAML-frontmatter field extraction for the
# Datarim MCP server (TUNE-0301).
#
# Datarim artefact frontmatter is NOT strictly YAML-parseable: several skill
# descriptions carry unquoted colons ("gate: verify …") and some blocks have
# trailing HTML comments, which break `yaml.safe_load`. This awk extractor is
# ported from install.sh `extract_frontmatter_field` (proven to generate 64
# valid SKILL.md wrappers) and reads a single scalar field line-by-line,
# supporting inline scalars (quoted or bare) and block scalars (| / >).
#
# Public API:
#   mcp_fm_field <file> <field>   — echo the field value (single line), or "".
#
# Bash 3.2-compatible. Dependency: awk. No network, no exec of input.

[[ -n "${_MCP_FRONTMATTER_LOADED:-}" ]] && return 0
_MCP_FRONTMATTER_LOADED=1

mcp_fm_field() {
    local src="$1" field="$2"
    [[ -f "$src" ]] || return 0
    awk -v field="$field" '
        BEGIN { in_fm = 0; fm_count = 0; collecting = 0; block_indent = 0; out = "" }
        /^---[[:space:]]*$/ {
            fm_count++
            if (fm_count == 1) { in_fm = 1; next }
            if (fm_count == 2) { if (collecting) print out; exit }
        }
        in_fm == 1 && collecting == 1 {
            if (match($0, "^[[:space:]]+")) {
                if (block_indent == 0) block_indent = RLENGTH
                line = substr($0, block_indent + 1)
                sub(/[[:space:]]+$/, "", line)
                if (out == "") out = line
                else out = out " " line
                next
            }
            print out
            exit
        }
        in_fm == 1 {
            if (match($0, "^" field ":[[:space:]]*")) {
                val = substr($0, RLENGTH + 1)
                sub(/[[:space:]]+$/, "", val)
                if (val == "|" || val == ">" || val == "|-" || val == ">-" || val == "|+" || val == ">+") {
                    collecting = 1
                    block_indent = 0
                    next
                }
                if (val ~ /^".*"$/) val = substr(val, 2, length(val) - 2)
                else if (val ~ /^'\''.*'\''$/) val = substr(val, 2, length(val) - 2)
                print val
                exit
            }
        }
    ' "$src" 2>/dev/null || true
}

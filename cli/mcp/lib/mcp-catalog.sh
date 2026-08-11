#!/usr/bin/env bash
# mcp-catalog.sh — enumeration + safe name→body resolution for the Datarim MCP
# server (TUNE-0301). Security-critical: `name` args originate from an
# untrusted model (Codex); this file is the sole trust boundary.
#
# Layered defence (creative-TUNE-0301-design.md § D5):
#   1. allowlist charset  ^[a-z0-9][a-z0-9._-]{0,63}$  AND no ".." substring
#   2. path must resolve to a regular file under the exact subdir
#   3. realpath-confinement — canonical file under canonical subdir prefix
#      (defeats in-tree symlink escape); symlinks excluded from enumeration
#   4. reads rooted ONLY at commands/ | skills/ | agents/ (never DATARIM_ROOT
#      itself) so a misconfigured root cannot expose sibling dirs
#
# Public API:
#   mcp_guard_root <root>          — startup guard; echoes canonical root or fail
#   mcp_valid_name <name>          — 0 if name passes the allowlist, else 1
#   mcp_list <root> <kind>         — JSON array [{name,description}]
#   mcp_resolve <root> <kind> <n>  — echo absolute body path or return 1
#   mcp_body <root> <kind> <n>     — emit body text (size-capped) or return 1
#
# kind ∈ commands | skills | agents.  Bash 4+. Deps: awk, jq, realpath.
# No network, no exec of artefact content.

[[ -n "${_MCP_CATALOG_LOADED:-}" ]] && return 0
_MCP_CATALOG_LOADED=1

_MCP_CATALOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cli/mcp/lib/mcp-frontmatter.sh
source "$_MCP_CATALOG_DIR/mcp-frontmatter.sh"

# Output body byte cap (defence against a misconfigured/symlinked huge target).
: "${MCP_BODY_CAP:=262144}"   # 256 KiB

# --- name allowlist --------------------------------------------------------

mcp_valid_name() {
    local name="${1-}"
    [[ -n "$name" ]] || return 1
    case "$name" in *".."*) return 1 ;; esac
    [[ "$name" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
    return 0
}

# --- startup root guard ----------------------------------------------------
# Fail-closed unless root is a real framework tree and not a sensitive path.
mcp_guard_root() {
    local root="${1-}"
    [[ -n "$root" && -d "$root" ]] || { echo "mcp: DATARIM_ROOT not a directory" >&2; return 1; }
    local real
    real="$(realpath "$root" 2>/dev/null)" || { echo "mcp: DATARIM_ROOT unresolved" >&2; return 1; }
    # Refuse obviously-wrong roots.
    if [[ "$real" == "/" || "$real" == "$HOME" ]]; then
        echo "mcp: refusing DATARIM_ROOT=$real" >&2; return 1
    fi
    case "$real" in */config/credentials|*/config/credentials/*)
        echo "mcp: refusing credentials path" >&2; return 1 ;;
    esac
    # Framework sentinel: all three artefact dirs must exist.
    [[ -d "$real/commands" && -d "$real/skills" && -d "$real/agents" ]] || {
        echo "mcp: DATARIM_ROOT missing commands/skills/agents sentinel" >&2; return 1; }
    printf '%s\n' "$real"
}

# --- internal: subdir for a kind ------------------------------------------
_mcp_subdir() {
    case "$1" in
        commands) printf 'commands\n' ;;
        skills)   printf 'skills\n' ;;
        agents)   printf 'agents\n' ;;
        *) return 1 ;;
    esac
}

# --- enumeration -----------------------------------------------------------
# Emits a JSON array of {name, description}. Symlinks excluded. name = basename
# (path component), guaranteeing a list→get round-trip. Uses `find` (not shell
# globs) so it is correct even under `set -f` (noglob) in the server; find does
# not descend symlinked dirs and `-type f` excludes symlinked files.
mcp_list() {
    local root="$1" kind="$2"
    local sub; sub="$(_mcp_subdir "$kind")" || return 1
    local dir="$root/$sub"
    [[ -d "$dir" ]] || { printf '[]\n'; return 0; }
    local -a items=()
    local f name desc obj
    if [[ "$kind" == "skills" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            name="$(basename "$(dirname "$f")")"
            desc="$(mcp_fm_field "$f" description)"
            obj="$(jq -cn --arg n "$name" --arg d "$desc" '{name:$n, description:$d}')"
            items+=("$obj")
        done < <(find "$dir" -maxdepth 2 -name 'SKILL.md' -type f 2>/dev/null | sort)
    else
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            name="$(basename "$f" .md)"
            desc="$(mcp_fm_field "$f" description)"
            obj="$(jq -cn --arg n "$name" --arg d "$desc" '{name:$n, description:$d}')"
            items+=("$obj")
        done < <(find "$dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
    fi
    if [[ ${#items[@]} -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "${items[@]}" | jq -cs '.'
    fi
}

# --- safe resolution -------------------------------------------------------
# Echoes the absolute, realpath-confined body path, or returns 1 (generic).
mcp_resolve() {
    local root="$1" kind="$2" name="$3"
    mcp_valid_name "$name" || return 1
    local sub; sub="$(_mcp_subdir "$kind")" || return 1
    local subdir_real; subdir_real="$(realpath "$root/$sub" 2>/dev/null)" || return 1
    local candidate
    if [[ "$kind" == "skills" ]]; then
        candidate="$subdir_real/$name/SKILL.md"
    else
        candidate="$subdir_real/$name.md"
    fi
    local file_real; file_real="$(realpath "$candidate" 2>/dev/null)" || return 1
    # Confinement: canonical file must live under the canonical subdir.
    case "$file_real" in
        "$subdir_real"/*) ;;
        *) return 1 ;;
    esac
    [[ -f "$file_real" ]] || return 1
    printf '%s\n' "$file_real"
}

# Emit the resolved body, size-capped. Returns 1 on any resolution failure.
mcp_body() {
    local root="$1" kind="$2" name="$3"
    local path; path="$(mcp_resolve "$root" "$kind" "$name")" || return 1
    head -c "$MCP_BODY_CAP" -- "$path"
}

#!/usr/bin/env bash
# check-repo-site-sync.sh — ecosystem repo↔site drift detector.
#
# Reads a machine-readable registry (documentation/ecosystem-sync/registry.yml)
# and, for every product whose local source is resolvable, checks four drift
# classes between the repository and its public site:
#
#   (1) version parity        repo version-file  vs  site version-file
#   (2) feature-list parity   count of repo feature dir *.md  vs  site rendered count
#   (3) footer-SHA staleness  site build-stamp  vs  newer content commits in repo
#   (4) head-site linkage      site→head-site link  AND  repo README→site link
#
# Severity contract (consumed by the auto-task generator): a site that is AHEAD
# of its repo (newer version) is HIGH — it means the repo-first ordering was
# violated. All other findings (site behind, stale stamp, missing link, count
# mismatch) are MEDIUM.
#
# Dependency floor: pure bash + awk + grep + git. No yq, no python — this is a
# shipped Datarim artifact that must run on any consumer. The registry is parsed
# with awk (precedent: check-security-policy.sh).
#
# Usage:
#   check-repo-site-sync.sh [--check | --report] [--product <id>] [--root <dir>]
#
# Exit codes:
#   0  clean (or all products' sources unavailable / skipped)
#   1  drift found in at least one product
#   2  usage error
#   3  registry missing or unparseable
#
# Read-only: no writes, no network. Untrusted registry paths are quoted and
# `..`-rejected (Security Mandate S1/S5).

set -uo pipefail

SCRIPT_NAME="check-repo-site-sync.sh"
MODE="check"            # check | report
PRODUCT_FILTER=""
ROOT=""

print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--check | --report] [--product <id>] [--root <dir>]

  --check        exit 0 = all synced, 1 = drift found (default)
  --report       human-readable per-product findings with severity
  --product <id> scope to one registry product id
  --root <dir>   KB root (default: walk up from cwd to find
                 documentation/ecosystem-sync/registry.yml)
  --help         this message

Exit: 0 clean | 1 drift | 2 usage error | 3 registry missing/unparseable
EOF
}

# ---- arg parse ----
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check"; shift ;;
        --report)  MODE="report"; shift ;;
        --product) PRODUCT_FILTER="${2:-}"; shift 2 ;;
        --root)    ROOT="${2:-}"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; print_usage >&2; exit 2 ;;
    esac
done

# ---- resolve KB root + registry ----
REGISTRY_REL="documentation/ecosystem-sync/registry.yml"
if [ -z "$ROOT" ]; then
    d="$PWD"
    while [ "$d" != "/" ]; do
        if [ -f "$d/$REGISTRY_REL" ]; then ROOT="$d"; break; fi
        d="$(dirname "$d")"
    done
fi
REGISTRY="$ROOT/$REGISTRY_REL"
if [ -z "$ROOT" ] || [ ! -f "$REGISTRY" ]; then
    echo "ERROR: registry not found ($REGISTRY_REL)" >&2
    exit 3
fi

# ---- registry parse (awk) → product|key|value triples ----
# Emits one line per scalar: <product>\t<key>\t<value>. page_bindings list items
# are emitted as <product>\tpage_binding\t<raw>. Two-space indentation contract.
parse_registry() {
    awk '
        function strip(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
        BEGIN { prod=""; in_products=0 }
        /^[[:space:]]*#/ { next }                       # comments
        /^products:[[:space:]]*$/ { in_products=1; next }
        in_products==0 { next }
        # product id: exactly two-space indent, ends with colon, no value
        /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
            line=$0; sub(/:[[:space:]]*$/,"",line); prod=strip(line); next
        }
        # page_bindings list item: 6-space indent dash
        /^      -[[:space:]]/ {
            if (prod=="") next
            v=$0; sub(/^      -[[:space:]]*/,"",v); print prod "\t" "page_binding" "\t" strip(v); next
        }
        # scalar key:value at four-space indent
        /^    [A-Za-z0-9_]+:[[:space:]]/ {
            if (prod=="") next
            line=$0; sub(/^    /,"",line)
            key=line; sub(/:.*$/,"",key); key=strip(key)
            val=line; sub(/^[^:]*:[[:space:]]*/,"",val); val=strip(val)
            # strip surrounding quotes if any
            if (val ~ /^".*"$/ || val ~ /^'\''.*'\''$/) val=substr(val,2,length(val)-2)
            print prod "\t" key "\t" val; next
        }
    ' "$REGISTRY"
}

# Look up a single scalar for a product from the parsed triples.
field() {  # $1=product $2=key   (reads $PARSED)
    printf '%s\n' "$PARSED" | awk -F'\t' -v p="$1" -v k="$2" '$1==p && $2==k {print $3; exit}'
}

# Reject paths that escape the root (Security S5). Returns 0 if safe & exists.
safe_local() {  # $1=relative-path → echoes absolute path if safe+exists, else nothing
    local rel="$1"
    case "$rel" in
        *..*|/*) return 1 ;;                # no parent-escape, no absolute
        "") return 1 ;;
    esac
    local abs="$ROOT/$rel"
    [ -e "$abs" ] || return 1
    printf '%s' "$abs"
}

# ---- per-check helpers ----
# Compare two dotted version strings. Echo: equal | a_ahead | b_ahead
vercmp() {  # $1=a $2=b
    if [ "$1" = "$2" ]; then echo equal; return; fi
    local hi
    hi="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    if [ "$hi" = "$1" ]; then echo a_ahead; else echo b_ahead; fi
}

FINDINGS=""   # accumulates "<product>|<check>|<severity>|<detail>"
add_finding() { FINDINGS="${FINDINGS}${1}|${2}|${3}|${4}"$'\n'; }

check_product() {  # $1=product
    local p="$1"
    local repo_rel site_rel repo site
    repo_rel="$(field "$p" repo_local)"
    site_rel="$(field "$p" site_local)"

    repo="$(safe_local "$repo_rel")" || { add_finding "$p" source "SKIP" "repo source unavailable: ${repo_rel:-<unset>}"; return; }
    site="$(safe_local "$site_rel")" || { add_finding "$p" source "SKIP" "site source unavailable: ${site_rel:-<unset>}"; return; }

    # (1) version parity
    local vrepo vsite repo_ver site_ver
    vrepo="$(field "$p" version_repo)"; vsite="$(field "$p" version_site)"
    if [ -n "$vrepo" ] && [ -n "$vsite" ] && [ -f "$repo/$vrepo" ] && [ -f "$site/$vsite" ]; then
        repo_ver="$(tr -d '[:space:]' < "$repo/$vrepo")"
        # site version: plain file, or 'version' key in a config file
        site_ver="$(grep -oE "'version'[^']*'[^']+'" "$site/$vsite" 2>/dev/null | grep -oE "'[0-9][^']*'$" | tr -d "'[:space:]")"
        [ -z "$site_ver" ] && site_ver="$(tr -d '[:space:]' < "$site/$vsite")"
        if [ -n "$repo_ver" ] && [ -n "$site_ver" ]; then
            case "$(vercmp "$site_ver" "$repo_ver")" in
                equal)   : ;;
                a_ahead) add_finding "$p" version HIGH   "site $site_ver ahead of repo $repo_ver (repo-first violated)" ;;
                b_ahead) add_finding "$p" version MEDIUM "site $site_ver behind repo $repo_ver" ;;
            esac
        fi
    fi

    # (2) feature-list parity
    local fdir fsite repo_n site_n
    fdir="$(field "$p" feature_count_repo)"; fsite="$(field "$p" feature_count_site)"
    if [ -n "$fdir" ] && [ -d "$repo/$fdir" ] && [ -n "$fsite" ] && [ -f "$site/$fsite" ]; then
        repo_n="$(find "$repo/$fdir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
        site_n="$(grep -oE '[0-9]+ commands' "$site/$fsite" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
        if [ -n "$site_n" ] && [ "$repo_n" != "$site_n" ]; then
            add_finding "$p" feature MEDIUM "repo has $repo_n commands, site renders $site_n"
        fi
    fi

    # (3) footer-SHA staleness (stamp produced by the deploy build-stamp step; absent → skip)
    local stamp_file stamp head_sha
    for stamp_file in "$site/.build-sha" "$site/build-info.php"; do
        [ -f "$stamp_file" ] || continue
        stamp="$(grep -oE '[0-9a-f]{7,40}' "$stamp_file" 2>/dev/null | head -1)"
        [ -n "$stamp" ] || continue
        if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            head_sha="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)"
            if [ -n "$head_sha" ] && [ "$stamp" != "$head_sha" ]; then
                # stamp is an ancestor of HEAD with newer commits → stale
                if git -C "$repo" merge-base --is-ancestor "$stamp" HEAD 2>/dev/null; then
                    add_finding "$p" stamp MEDIUM "site stamp $stamp is stale; repo HEAD $head_sha has newer commits"
                fi
            fi
        fi
        break
    done

    # (4) head-site linkage (both directions)
    local head readme
    head="$(field "$p" head_site)"
    if [ -n "$head" ]; then
        if ! grep -rqs "$head" "$site" 2>/dev/null; then
            add_finding "$p" linkage MEDIUM "site does not link to head-site $head"
        fi
    fi
    readme="$(field "$p" readme_repo)"
    local domain; domain="$(field "$p" domain)"
    if [ -n "$readme" ] && [ -n "$domain" ] && [ -f "$repo/$readme" ]; then
        if ! grep -qs "$domain" "$repo/$readme" 2>/dev/null; then
            add_finding "$p" linkage MEDIUM "repo $readme has no reverse link to $domain"
        fi
    fi
}

# ---- main ----
PARSED="$(parse_registry)"
if [ -z "$PARSED" ]; then
    echo "ERROR: registry parsed empty (unparseable or no products)" >&2
    exit 3
fi

PRODUCTS="$(printf '%s\n' "$PARSED" | awk -F'\t' '!seen[$1]++ {print $1}')"
for prod in $PRODUCTS; do
    [ -n "$PRODUCT_FILTER" ] && [ "$prod" != "$PRODUCT_FILTER" ] && continue
    check_product "$prod"
done

# A SKIP finding is not drift. Real drift = any finding whose severity != SKIP.
DRIFT="$(printf '%s' "$FINDINGS" | awk -F'|' 'NF>=3 && $3!="SKIP" {c++} END{print c+0}')"

if [ "$MODE" = "report" ]; then
    if [ -z "$FINDINGS" ]; then
        echo "OK: all registered products synced (or scoped product clean)."
    else
        printf '%s' "$FINDINGS" | awk -F'|' 'NF>=4 {printf "%-12s %-9s %-7s %s\n", $1, $2, $3, $4}'
    fi
fi

[ "$DRIFT" -gt 0 ] && exit 1
exit 0

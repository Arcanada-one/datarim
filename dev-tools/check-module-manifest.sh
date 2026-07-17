#!/usr/bin/env bash
#
# check-module-manifest.sh — structural validator for a skill-pack module.yaml.
#
# STUB by design: a dependency-free (awk/grep/sed, no yq) structural check of
# the module.yaml contract, NOT a full YAML parser or a cross-plugin dependency
# resolver. Schema: documentation/reference/module-manifest.md (schema_version 1).
#
# Usage: check-module-manifest.sh <path-to-module.yaml>
#
# Exit codes:
#   0  structurally valid (warnings may still print to stderr)
#   1  hard-error rule violated (missing field, bad schema_version/id/version,
#      empty skills list)
#   2  usage error (no path / file not found)
#
# Read-only: no writes, no network.

set -euo pipefail

usage() {
    sed -n '2,20p' "$0"
    exit "${1:-2}"
}

case "${1:-}" in
    -h|--help) usage 0 ;;
    "") echo "ERROR: no manifest path given" >&2; usage 2 ;;
esac

MANIFEST="$1"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: $MANIFEST" >&2
    exit 2
fi

KEBAB_RE='^[a-z][a-z0-9-]{0,63}$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

fail=0
err() { echo "FAIL: $1" >&2; fail=1; }
warn() { echo "WARN: $1" >&2; }

# ---- schema_version (top-level) ----
schema_version="$(grep -E '^schema_version:' "$MANIFEST" | head -n1 \
    | sed -E 's/^schema_version:[[:space:]]*//; s/[[:space:]]+$//' || true)"
if [ -z "$schema_version" ]; then
    err "missing required top-level field: schema_version"
elif [ "$schema_version" != "1" ]; then
    err "unsupported schema_version '$schema_version' (this validator handles 1)"
fi

# ---- module block (2-space-indented scalars) ----
_module_scalar() {
    # $1 = key; module.<key> is a 2-space-indented scalar (skills entries are
    # deeper-indented, so ^  <key>: cannot collide with a skills field).
    grep -E "^  $1:" "$MANIFEST" | head -n1 \
        | sed -E "s/^  $1:[[:space:]]*//; s/^\"(.*)\"\$/\1/; s/[[:space:]]+\$//" || true
}

if ! grep -qE '^module:' "$MANIFEST"; then
    err "missing required block: module"
fi

module_id="$(_module_scalar id)"
module_title="$(_module_scalar title)"
module_version="$(_module_scalar version)"
module_description="$(_module_scalar description)"

[ -n "$module_id" ] || err "missing required field: module.id"
[ -n "$module_title" ] || err "missing required field: module.title"
[ -n "$module_version" ] || err "missing required field: module.version"
[ -n "$module_description" ] || err "missing required field: module.description"

if [ -n "$module_id" ] && ! printf '%s' "$module_id" | grep -qE "$KEBAB_RE"; then
    err "module.id '$module_id' is not kebab-case ($KEBAB_RE)"
fi
if [ -n "$module_version" ] && ! printf '%s' "$module_version" | grep -qE "$SEMVER_RE"; then
    err "module.version '$module_version' is not semver (MAJOR.MINOR.PATCH)"
fi

# ---- skills list (per-entry validation via awk) ----
if ! grep -qE '^skills:' "$MANIFEST"; then
    err "missing required block: skills"
fi

# awk emits, for each skill entry: one "SKILL <name>|<version>|<summary-present>|
# <stability>" line + "REQ <name>" lines, and a final "COUNT <n>".
skill_report="$(awk '
    BEGIN { in_skills=0; n=0; name=""; ver=""; summ=0; stab=""; have=0 }
    # leaving the skills block: a new top-level key at column 0.
    /^[A-Za-z_]/ { if (in_skills && $0 !~ /^skills:/) in_skills=0 }
    /^skills:/ { in_skills=1; next }
    in_skills==0 { next }
    # start of a new skill entry ("  - name: X")
    /^  - name:/ {
        if (have) { printf "SKILL %s|%s|%d|%s\n", name, ver, summ, stab }
        n++; have=1
        name=$0; sub(/^  - name:[[:space:]]*/, "", name); gsub(/[[:space:]]+$/, "", name)
        ver=""; summ=0; stab=""
        next
    }
    /^    version:/ { v=$0; sub(/^    version:[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v); ver=v; next }
    /^    summary:/ { summ=1; next }
    /^    stability:/ { s=$0; sub(/^    stability:[[:space:]]*/, "", s); gsub(/[[:space:]]+$/, "", s); stab=s; next }
    /^      - / { r=$0; sub(/^      - [[:space:]]*/, "", r); gsub(/[[:space:]]+$/, "", r); printf "REQ %s|%s\n", name, r; next }
    END { if (have) { printf "SKILL %s|%s|%d|%s\n", name, ver, summ, stab } printf "COUNT %d\n", n }
' "$MANIFEST")"

skill_count="$(printf '%s\n' "$skill_report" | sed -n 's/^COUNT //p')"
if [ "${skill_count:-0}" -eq 0 ]; then
    err "skills list is empty — a pack with no skills has no reason to declare a manifest"
fi

# Collect declared skill names for requires cross-check.
declared_names="$(printf '%s\n' "$skill_report" | sed -n 's/^SKILL \([^|]*\)|.*/\1/p')"

while IFS= read -r line; do
    case "$line" in
        SKILL\ *)
            body="${line#SKILL }"
            s_name="${body%%|*}"; rest="${body#*|}"
            s_ver="${rest%%|*}"; rest="${rest#*|}"
            s_summ="${rest%%|*}"; s_stab="${rest#*|}"
            if [ -z "$s_name" ] || ! printf '%s' "$s_name" | grep -qE "$KEBAB_RE"; then
                err "skills entry name '$s_name' is missing or not kebab-case"
            fi
            if [ -z "$s_ver" ]; then
                err "skills entry '$s_name' missing required field: version"
            elif ! printf '%s' "$s_ver" | grep -qE "$SEMVER_RE"; then
                err "skills entry '$s_name' version '$s_ver' is not semver"
            fi
            if [ "$s_summ" != "1" ]; then
                err "skills entry '$s_name' missing required field: summary"
            fi
            if [ -n "$s_stab" ] && ! printf '%s' "$s_stab" | grep -qE '^(stable|beta|experimental)$'; then
                err "skills entry '$s_name' stability '$s_stab' not in {stable,beta,experimental}"
            fi
            # SHOULD (warn only): declared name resolves to a real skill dir.
            pack_root="$(dirname "$MANIFEST")"
            if [ ! -f "$pack_root/skills/$s_name/SKILL.md" ] && [ ! -f "$pack_root/../skills/$s_name/SKILL.md" ]; then
                warn "skills entry '$s_name' has no matching skills/$s_name/SKILL.md near the manifest (may be authored ahead of the file)"
            fi
            ;;
        REQ\ *)
            body="${line#REQ }"
            r_owner="${body%%|*}"; r_dep="${body#*|}"
            if ! printf '%s\n' "$declared_names" | grep -qxF "$r_dep"; then
                warn "skills entry '$r_owner' requires '$r_dep' which is not declared in this pack (may be satisfied by core or another plugin)"
            fi
            ;;
    esac
done <<EOF
$skill_report
EOF

if [ "$fail" -ne 0 ]; then
    echo "RESULT: INVALID ($MANIFEST)" >&2
    exit 1
fi
echo "RESULT: VALID ($MANIFEST) — schema_version=$schema_version, module=$module_id@$module_version, skills=$skill_count"
exit 0

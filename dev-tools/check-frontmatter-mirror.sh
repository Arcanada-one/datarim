#!/usr/bin/env bash
#
# check-frontmatter-mirror.sh — TUNE-0191 frontmatter-key behaviour-gate mirror
# drift guard (source: reflection-TUNE-0184 § P-6).
#
# Enforces two invariants against dev-tools/rules/frontmatter-key-registry.yaml,
# failing on drift in EITHER direction:
#
#   P1 registry-completeness (instruction surface = commands/skills/agents):
#      - every live top-level frontmatter key is categorised in the registry;
#      - no `status: live` instruction entry has vanished from the surface;
#      - a key registered `status: reserved` must NOT appear live.
#
#   P2 mirror-presence (for `surface: instruction, status: live, mirror: required`
#      entries carrying a `body_marker`):
#      - a file carrying the frontmatter key MUST carry the body marker;
#      - a file carrying the body marker MUST carry the frontmatter key.
#
#   Reserved required-mirror keys (e.g. disable-model-invocation) are guarded by
#   P1 (a live re-introduction fails as "reserved found live"); P2 activates only
#   once the entry is reclassified `status: live`, which then enforces the mirror.
#   Templates (surface: template) are survey-only and NOT drift-gated here.
#
# Usage:
#   check-frontmatter-mirror.sh [--root <repo-root>] [--registry <yaml>] [--quiet]
# Exit codes:  0 PASS · 1 drift · 2 usage/error.
# Read-only. No writes anywhere. Bash 3.2 compatible (no associative arrays).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT=""
REGISTRY=""
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)     ROOT="${2:-}"; shift 2 ;;
        --registry) REGISTRY="${2:-}"; shift 2 ;;
        --quiet)    QUIET=true; shift ;;
        -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$ROOT" ]] && ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -z "$REGISTRY" ]] && REGISTRY="$SCRIPT_DIR/rules/frontmatter-key-registry.yaml"

if [[ ! -d "$ROOT" ]]; then
    echo "ERROR: root not a directory: $ROOT" >&2; exit 2
fi
if [[ ! -f "$REGISTRY" ]]; then
    echo "ERROR: registry not found: $REGISTRY" >&2; exit 2
fi

log() { $QUIET || echo "$@"; }

# ── Extract top-level frontmatter keys from a markdown file's leading block. ──
extract_keys() {
    awk '
        BEGIN { c = 0 }
        /^---$/ { c++; if (c == 2) exit; next }
        c == 1 { print }
    ' "$1" | grep -oE '^[A-Za-z][A-Za-z0-9_-]*:' | sed 's/:$//'
}

# ── Extract the body (everything after the leading frontmatter block). ───────
extract_body() {
    awk '
        BEGIN { c = 0 }
        /^---$/ { c++; next }
        c >= 2 { print }
    ' "$1"
}

# ── Instruction-surface file list. ──────────────────────────────────────────
instruction_files() {
    shopt -s nullglob
    local f
    for f in "$ROOT"/commands/*.md;       do [[ -f "$f" ]] && echo "$f"; done
    for f in "$ROOT"/skills/*.md;         do [[ -f "$f" ]] && echo "$f"; done
    for f in "$ROOT"/skills/*/SKILL.md;   do [[ -f "$f" ]] && echo "$f"; done
    for f in "$ROOT"/agents/*.md;         do [[ -f "$f" ]] && echo "$f"; done
}

# ── Parse the registry into pipe records: key|surface|category|mirror|status|body_marker
parse_registry() {
    awk '
        function flush() {
            if (key != "")
                printf "%s|%s|%s|%s|%s|%s\n", key, surface, category, mirror, status, body_marker
            key=""; surface=""; category=""; mirror=""; status=""; body_marker=""
        }
        /^[[:space:]]*-[[:space:]]+key:[[:space:]]*/ {
            flush()
            v=$0; sub(/^[[:space:]]*-[[:space:]]+key:[[:space:]]*/, "", v)
            gsub(/[[:space:]]*#.*$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v)
            key=v; next
        }
        /^[[:space:]]+surface:[[:space:]]*/     { v=$0; sub(/^[[:space:]]+surface:[[:space:]]*/,"",v);     gsub(/[[:space:]]*#.*$/,"",v); surface=v; next }
        /^[[:space:]]+category:[[:space:]]*/    { v=$0; sub(/^[[:space:]]+category:[[:space:]]*/,"",v);    gsub(/[[:space:]]*#.*$/,"",v); category=v; next }
        /^[[:space:]]+mirror:[[:space:]]*/      { v=$0; sub(/^[[:space:]]+mirror:[[:space:]]*/,"",v);      gsub(/[[:space:]]*#.*$/,"",v); mirror=v; next }
        /^[[:space:]]+status:[[:space:]]*/      { v=$0; sub(/^[[:space:]]+status:[[:space:]]*/,"",v);      gsub(/[[:space:]]*#.*$/,"",v); status=v; next }
        /^[[:space:]]+body_marker:[[:space:]]*/ { v=$0; sub(/^[[:space:]]+body_marker:[[:space:]]*/,"",v); gsub(/[[:space:]]*#.*$/,"",v); gsub(/^["'"'"']|["'"'"']$/,"",v); body_marker=v; next }
        END { flush() }
    ' "$1"
}

REG="$(parse_registry "$REGISTRY")"
if [[ -z "$REG" ]]; then
    echo "ERROR: registry parsed to zero entries: $REGISTRY" >&2; exit 2
fi

# Registry key sets (instruction surface).
INSTR_LIVE_KEYS="$(echo "$REG"     | awk -F'|' '$2=="instruction" && $5=="live"     {print $1}' | sort -u)"
INSTR_RESERVED_KEYS="$(echo "$REG" | awk -F'|' '$2=="instruction" && $5=="reserved" {print $1}' | sort -u)"

# Live surface keys actually present.
SURFACE_KEYS="$(
    while IFS= read -r f; do
        [[ -n "$f" ]] && extract_keys "$f"
    done < <(instruction_files) | sort -u
)"

fail=0
in_list() { grep -Fxq "$1" <<<"$2"; }

# ── P1: registry-completeness (either-side drift) ────────────────────────────
if [[ -n "$SURFACE_KEYS" ]]; then
    while IFS= read -r k; do
        [[ -z "$k" ]] && continue
        if in_list "$k" "$INSTR_LIVE_KEYS"; then
            :
        elif in_list "$k" "$INSTR_RESERVED_KEYS"; then
            log "FAIL P1: key '$k' is registered status:reserved but found live on the surface"
            fail=1
        else
            log "FAIL P1: uncategorised key '$k' — not in registry (add an entry to $(basename "$REGISTRY"))"
            fail=1
        fi
    done <<<"$SURFACE_KEYS"
fi

if [[ -n "$INSTR_LIVE_KEYS" ]]; then
    while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        if ! in_list "$r" "$SURFACE_KEYS"; then
            log "FAIL P1: stale registry entry '$r' (status:live) has vanished from the surface"
            fail=1
        fi
    done <<<"$INSTR_LIVE_KEYS"
fi

# ── P2: mirror-presence for live, required-mirror keys ───────────────────────
while IFS='|' read -r key surface _ mirror status body_marker; do
    [[ "$surface" == "instruction" ]] || continue
    [[ "$status"  == "live" ]]        || continue
    [[ "$mirror"  == "required" ]]    || continue
    [[ -n "$body_marker" ]]           || continue

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        has_key=false; has_marker=false
        extract_keys "$f" | grep -Fxq "$key" && has_key=true
        extract_body "$f" | grep -Fq -- "$body_marker" && has_marker=true

        if $has_key && ! $has_marker; then
            log "FAIL P2: '$key' frontmatter key present without body marker '$body_marker' in ${f#"$ROOT"/}"
            fail=1
        fi
        if $has_marker && ! $has_key; then
            log "FAIL P2: body marker '$body_marker' present without '$key' frontmatter key in ${f#"$ROOT"/}"
            fail=1
        fi
    done < <(instruction_files)
done <<<"$REG"

if [[ $fail -eq 0 ]]; then
    log "RESULT: PASS (frontmatter-key mirror drift guard — P1 + P2)"
    exit 0
else
    log "RESULT: FAIL (frontmatter-key mirror drift)"
    exit 1
fi

#!/usr/bin/env bash
# TUNE-0254 — stage-snapshot presence / schema validator.
#
# Modes:
#   --task <ID>                   presence + light schema check
#   --validate-frontmatter --task <ID>  strict 7-field schema check
#   --self-test                   smoke a synthetic snapshot end-to-end
#
# Exit codes:
#   0  ok
#   1  snapshot missing
#   2  malformed frontmatter (missing mandatory field, bad value)
#   3  usage error

set -euo pipefail

# Mandatory frontmatter fields per skills/stage-snapshot-writer/SKILL.md § Outputs.
# `options` validated separately (list, not scalar).
readonly REQUIRED_SCALAR_FIELDS=(
    task_id
    artifact
    schema_version
    stage
    command
    captured_at
    captured_by
    recommended_next
    size_bytes
    truncated
)

usage() {
    cat >&2 <<'USAGE'
Usage:
  check-stage-snapshot-on-exit.sh --task <TASK-ID> [--root <repo>]
  check-stage-snapshot-on-exit.sh --validate-frontmatter --task <ID> [--root <repo>]
  check-stage-snapshot-on-exit.sh --self-test

Exits 0 ok / 1 missing / 2 malformed / 3 usage.
USAGE
}

snapshot_path() {
    local root="$1" task_id="$2"
    printf '%s/datarim/snapshots/%s.snapshot.md' "$root" "$task_id"
}

extract_frontmatter() {
    local file="$1"
    awk '
        BEGIN { in_fm = 0 }
        /^---[[:space:]]*$/ {
            if (in_fm == 0) { in_fm = 1; next }
            if (in_fm == 1) { exit }
        }
        in_fm == 1 { print }
    ' "$file"
}

frontmatter_has_field() {
    local fm="$1" field="$2"
    printf '%s\n' "$fm" | grep -Eq "^${field}:[[:space:]]+\S"
}

validate_frontmatter() {
    local file="$1"
    [ -r "$file" ] || return 1
    # F9 (TUNE-0254 /dr-verify) — reject symlinks at the snapshot path.
    # Writer-side T-7 pre-unlinks; consumer-side symmetry: a co-agent or
    # attacker substituting a symlink → /etc/passwd would otherwise let
    # /dr-continue inline arbitrary file contents into the replay-prompt.
    # Treat symlink as malformed (exit 2) — caller falls through to legacy.
    if [ -L "$file" ]; then
        printf 'check-stage-snapshot: snapshot path is a symlink (rejected)\n' >&2
        return 2
    fi
    local fm
    fm="$(extract_frontmatter "$file")"
    [ -n "$fm" ] || return 2
    for field in "${REQUIRED_SCALAR_FIELDS[@]}"; do
        if ! frontmatter_has_field "$fm" "$field"; then
            printf 'check-stage-snapshot: missing mandatory field %q\n' "$field" >&2
            return 2
        fi
    done
    # options list — must have at least the `options:` line.
    if ! printf '%s\n' "$fm" | grep -Eq '^options:[[:space:]]*$'; then
        printf 'check-stage-snapshot: missing options list\n' >&2
        return 2
    fi
    return 0
}

self_test() {
    local tmp rc
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/datarim/snapshots"
    cat > "$tmp/datarim/snapshots/SELFTEST-0001.snapshot.md" <<'SNAP'
---
task_id: SELFTEST-0001
artifact: stage-snapshot
schema_version: 1
stage: plan
command: /dr-plan
captured_at: 2026-05-21T00:00:00Z
captured_by: agent
recommended_next: /dr-do
options:
  - "/dr-do SELFTEST-0001 | smoke"
size_bytes: 100
truncated: false
---

Selftest body.
SNAP
    if validate_frontmatter "$tmp/datarim/snapshots/SELFTEST-0001.snapshot.md"; then
        rc=0
    else
        rc=$?
    fi
    rm -rf "$tmp"
    return "$rc"
}

main() {
    local mode=""
    local task_id=""
    local root="$PWD"

    if [ $# -eq 0 ]; then
        usage
        return 3
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --task) task_id="$2"; shift 2 ;;
            --root) root="$2"; shift 2 ;;
            --validate-frontmatter) mode="validate"; shift ;;
            --self-test) mode="selftest"; shift ;;
            -h|--help) usage; return 0 ;;
            *) usage; return 3 ;;
        esac
    done

    if [ "$mode" = "selftest" ]; then
        if self_test; then
            printf 'check-stage-snapshot: self-test OK\n'
            return 0
        else
            return 2
        fi
    fi

    if [ -z "$task_id" ]; then
        usage
        return 3
    fi

    local file
    file="$(snapshot_path "$root" "$task_id")"

    if [ ! -f "$file" ]; then
        return 1
    fi

    if [ "$mode" = "validate" ]; then
        validate_frontmatter "$file"
        return $?
    fi

    # Default (presence) mode — still does light shape check.
    validate_frontmatter "$file"
    return $?
}

main "$@"

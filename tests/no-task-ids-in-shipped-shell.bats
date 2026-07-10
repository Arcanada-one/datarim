#!/usr/bin/env bats
#
# no-task-ids-in-shipped-shell — regression guard for TUNE-0314.
#
# Operator rule (2026-05-26): real task-IDs are forbidden in specs/code
# comments — provenance flavor-text is clutter and, in shipped OSS, a minor
# information leak. scripts/task-id-gate.sh already enforces this on the
# skills/agents/commands/templates *.md scopes; it does not cover the three
# repo-root shell installers (install.sh/update.sh/validate.sh), which had
# accumulated ~30 comment-only citations (v1.17.0/v1.20.0/v2.15.0 version
# anchors already carried the same information without the ID).
#
# Two occurrences are intentionally exempt — they are not provenance
# citations, they are literal on-disk backup-naming tokens baked into
# already-deployed operator installs (renaming them would break restore
# against pre-existing real backups):
#   - install.sh: `bak="$dst.bak-TUNE-0303-$ts"` (single-file backup suffix)
#   - install.sh: `skills.bundled-backup-TUNE-0296-*` (Codex .system/ backup
#     glob, matched against directories created by earlier installer runs)

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
ID_RE='[A-Z]{2,6}-[0-9]{4}'

# Exact allowed occurrences: "<file>:<matched-id>" pairs. Anything else is a
# regression.
is_allowed() {
    local file="$1" id="$2"
    case "$file:$id" in
        "$REPO_ROOT/install.sh:TUNE-0303") return 0 ;;
        "$REPO_ROOT/install.sh:TUNE-0296") return 0 ;;
        *) return 1 ;;
    esac
}

@test "T1: install.sh has no unexpected task-ID citations" {
    run grep -noE "$ID_RE" "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    local bad=0
    while IFS=: read -r lineno id; do
        [ -z "$id" ] && continue
        if ! is_allowed "$REPO_ROOT/install.sh" "$id"; then
            echo "unexpected task-ID at install.sh:$lineno -> $id" >&2
            bad=1
        fi
    done <<< "$output"
    [ "$bad" -eq 0 ]
}

@test "T2: update.sh has zero task-ID citations" {
    run grep -noE "$ID_RE" "$REPO_ROOT/update.sh"
    [ "$status" -eq 1 ]
}

@test "T3: validate.sh has zero task-ID citations" {
    run grep -noE "$ID_RE" "$REPO_ROOT/validate.sh"
    [ "$status" -eq 1 ]
}

@test "T4: install.sh version anchors survived the citation strip" {
    run grep -F "v1.17.0" "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -F "v1.20.0" "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -F "v2.15.0" "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "T5: exempt backup-naming tokens are untouched (restore compat)" {
    run grep -F 'bak="$dst.bak-TUNE-0303-$ts"' "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run grep -F "skills.bundled-backup-TUNE-0296-" "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "T6: install.sh/update.sh/validate.sh remain syntactically valid bash" {
    run bash -n "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run bash -n "$REPO_ROOT/update.sh"
    [ "$status" -eq 0 ]
    run bash -n "$REPO_ROOT/validate.sh"
    [ "$status" -eq 0 ]
}

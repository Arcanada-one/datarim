#!/usr/bin/env bats
#
# T3 (TUNE-0013): sweep regression — /dr-reflect must not resurface anywhere
# in the framework repo outside an explicit historical whitelist.
#
# Contract under test (v1.10.0 pipeline):
#   AC-5: after Phase 2 (cross-reference sweep), every live spec/doc/agent/
#   skill/command/visual-map references the v2 pipeline (8 stages, reflection
#   inside /dr-archive). Only forward-pointer historical annotations remain,
#   and each cites TUNE-0013 / v1.10.0 explicitly.
#
# Whitelist policy:
#   A file may contain "dr-reflect" ONLY if every hit in that file is a
#   historical annotation naming v1.10.0 / TUNE-0013 (forward-pointer).
#   New live spec/doc references fail this test.
#
# Whitelisted files (intentional historical forward-pointers):
#   - CLAUDE.md                   "/dr-reflect command no longer exists"
#   - docs/pipeline.md            "Historical note: prior to v1.10.0..."
#   - commands/dr-archive.md      "Historical: prior to v1.10.0..."
#   - skills/reflecting.md        "former /dr-reflect command was retired..."
#   - skills/evolution.md         forward-pointer note + utilities/recovery ref
#                                 (plan §D5 2c: "keep historical changelog
#                                 paragraph annotated 'prior to v1.10.0'")
#   - skills/evolution/class-ab-gate.md           TUNE-0002/0003 incident
#                                 reconstruction (added by TUNE-0034 — fragment
#                                 split from skills/evolution.md per
#                                 utilities-decomposition; v1.10.0/TUNE-0013
#                                 mentioned inline)
#   - skills/evolution/examples-and-patterns.md   TUNE-0013 case-study +
#                                 commands/dr-reflect.md removal example
#                                 (added by TUNE-0034 — fragment split; v1.10.0
#                                 / TUNE-0013 mentioned inline)
#   - changelog.php (website)     v1.10.0 release entry — not in framework
#                                 repo; covered by Phase 5 website sweep.
#   - documentation/archive/framework/  historical task archives
#
# Anything else that matches "dr-reflect" is a bug.

REPO="${BATS_TEST_DIRNAME}/.."

# Files allowed to mention /dr-reflect (must all be forward-pointer annotations).
WHITELIST=(
    "CLAUDE.md"
    "docs/pipeline.md"
    "commands/dr-archive.md"
    "skills/reflecting.md"
    "skills/evolution.md"
    "skills/evolution/class-ab-gate.md"
    "skills/evolution/examples-and-patterns.md"
)

@test "T3a: every live file referencing dr-reflect is whitelisted" {
    # List every tracked file that mentions dr-reflect (case-sensitive, whole pattern).
    # Exclude git internals, backups, documentation/archive/framework/, and tests dir
    # (tests reference the string as test data).
    cd "$REPO"
    hits=$(grep -rln "dr-reflect" \
             --exclude-dir=.git \
             --exclude-dir=backups \
             --exclude-dir=tests \
             --exclude-dir=node_modules \
             . 2>/dev/null \
             | sed 's|^\./||' \
             | grep -v "^documentation/archive/framework/" \
             || true)

    # Every hit must be on the whitelist.
    violations=""
    for f in $hits; do
        ok=0
        for w in "${WHITELIST[@]}"; do
            if [ "$f" = "$w" ]; then
                ok=1
                break
            fi
        done
        if [ "$ok" -eq 0 ]; then
            violations="$violations $f"
        fi
    done

    if [ -n "$violations" ]; then
        echo "ERROR: files reference /dr-reflect but are not on the T3 whitelist:" >&2
        for f in $violations; do
            echo "  - $f" >&2
        done
        echo "" >&2
        echo "Either (a) remove the /dr-reflect reference, or" >&2
        echo "       (b) add the file to the whitelist with rationale." >&2
        return 1
    fi
}

@test "T3b: each whitelisted reference is a v1.10.0/TUNE-0013 forward-pointer" {
    # Every line matching dr-reflect in a whitelisted file must appear in the
    # vicinity of v1.10.0 or TUNE-0013 (forward-pointer annotation policy).
    # We enforce per-file: at least one v1.10.0 OR TUNE-0013 mention must exist.
    cd "$REPO"
    failures=""
    for f in "${WHITELIST[@]}"; do
        if [ ! -f "$f" ]; then
            continue  # whitelist entry may legitimately not exist in some builds
        fi
        if ! grep -qE "v1\.10\.0|TUNE-0013" "$f"; then
            failures="$failures $f"
        fi
    done

    if [ -n "$failures" ]; then
        echo "ERROR: whitelisted files mention /dr-reflect without a v1.10.0/TUNE-0013 forward-pointer:" >&2
        for f in $failures; do
            echo "  - $f" >&2
        done
        return 1
    fi
}

@test "T3c: commands/dr-reflect.md has been removed from repo" {
    cd "$REPO"
    [ ! -f "commands/dr-reflect.md" ]
}

@test "T3d: visual-maps mermaid diagrams have no dr-reflect nodes" {
    cd "$REPO"
    run grep -lF "dr-reflect" skills/visual-maps/
    [ "$status" -ne 0 ]
}

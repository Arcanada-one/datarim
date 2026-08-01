#!/usr/bin/env bats
#
# tests/personal-id-lint-scope.bats
#
# The personal-id gate has two independent notions of "the shipped surface":
#
#   1. DEFAULT_PATHS in scripts/personal-id-gate.sh — what the gate scans.
#   2. the `paths:` filters in .github/workflows/personal-id-lint.yml — when CI
#      bothers to run the gate at all.
#
# They drifted once already: the workflow filter mirrored an older, narrower
# DEFAULT_PATHS, so the gate never ran on changes to plugins/, config/, tests/,
# .github/ or the root installers. CI was green because it was not looking,
# which is indistinguishable from CI being green because the tree is clean —
# until someone widens the scan and finds real leaks.
#
# These assertions make that drift impossible to reintroduce silently.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    GATE="$ROOT/scripts/personal-id-gate.sh"
    WF="$ROOT/.github/workflows/personal-id-lint.yml"
    export ROOT GATE WF
}

# Extract DEFAULT_PATHS entries from the gate script.
default_paths() {
    awk '/^DEFAULT_PATHS=\(/{f=1; next} f&&/^\)/{f=0} f' "$GATE" \
        | tr -s ' \t' '\n' \
        | grep -v '^$'
}

@test "the gate declares a non-empty DEFAULT_PATHS" {
    local n
    n="$(default_paths | wc -l)"
    # A parse failure here would make every assertion below vacuously true.
    [ "$n" -ge 10 ]
}

@test "every DEFAULT_PATHS entry is covered by the workflow paths filter" {
    # Accept either form: a directory entry may legitimately be written as
    # `'docs/**'` even when docs/ does not exist yet (the gate tolerates absent
    # DEFAULT_PATHS entries, and the filter should already cover the directory
    # for the commit that creates it).
    local missing="" entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if grep -qF "'${entry}'" "$WF" || grep -qF "'${entry}/**'" "$WF"; then
            continue
        fi
        missing="${missing} ${entry}"
    done < <(default_paths)

    [ -z "$missing" ] || {
        echo "DEFAULT_PATHS entries absent from personal-id-lint.yml paths filter:"
        echo "  ${missing}"
        echo "The gate would scan them locally but CI would never trigger on them."
        return 1
    }
}

@test "both the push and pull_request filters carry the same entry count" {
    # GitHub Actions does not support YAML anchors, so the list is duplicated.
    # A widened push filter with a stale pull_request filter is the worst case:
    # green PRs, red main.
    local push_n pr_n
    push_n="$(python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get(True, wf.get("on"))
print(len(on["push"]["paths"]))
PY
)"
    pr_n="$(python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get(True, wf.get("on"))
print(len(on["pull_request"]["paths"]))
PY
)"
    [ "$push_n" -eq "$pr_n" ]
    [ "$push_n" -ge 10 ]
}

@test "the workflow uses no YAML anchors (GitHub Actions does not support them)" {
    run grep -nE '(^|\s)[*&][a-zA-Z_]' "$WF"
    [ "$status" -ne 0 ]
}

@test "the workflow declares least-privilege permissions and a pinned action" {
    grep -qE '^permissions:' "$WF"
    grep -qE '^\s+contents:\s*read' "$WF"
    local bad
    bad="$(grep -E '^\s*(-\s*)?uses:' "$WF" | grep -vE '@[0-9a-f]{40}' || true)"
    [ -z "$bad" ]
}

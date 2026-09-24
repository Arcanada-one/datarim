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
# The gate now scans `git ls-files` and the workflow has no paths filter, so
# there is no second list left to drift. These assertions keep it that way.

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

@test "the gate declares a non-empty DEFAULT_PATHS fallback" {
    local n
    n="$(default_paths | wc -l)"
    # A parse failure here would make the fallback silently empty.
    [ "$n" -ge 10 ]
}

@test "inside a git checkout the gate scans every tracked file, not DEFAULT_PATHS" {
    # The drift this file used to police (workflow filter vs DEFAULT_PATHS) had
    # a second, quieter half: files outside BOTH lists — root-level notes,
    # CHANGELOG.md — were never scanned at all. Tracked-file scope removes the
    # list as the thing that can drift.
    grep -q 'git -C "$FRAMEWORK_ROOT" ls-files -z' "$GATE"
    local tracked scanned
    tracked="$(git -C "$ROOT" ls-files | wc -l | tr -d ' ')"
    run bash "$GATE" --report
    scanned="$(printf '%s\n' "$output" | sed -nE 's/^scope: tracked \(([0-9]+) file.*/\1/p')"
    [ -n "$scanned" ]
    # Every tracked regular file is scanned (symlinks carry no body of their own).
    local links
    links="$(git -C "$ROOT" ls-files -s | awk '$1==120000' | wc -l | tr -d ' ')"
    [ "$scanned" -eq $((tracked - links)) ]
}

@test "the workflow runs on every change (no paths filter can hide a file)" {
    python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get(True, wf.get("on"))
for ev in ("push", "pull_request"):
    assert ev in on, f"workflow does not trigger on {ev}"
    cfg = on[ev] or {}
    assert "paths" not in cfg and "paths-ignore" not in cfg, f"{ev} carries a paths filter"
PY
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

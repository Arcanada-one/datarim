#!/usr/bin/env bats
# tune-0549-framework-hygiene.bats
#
# Regression for the .gitignore ↔ tracked-tree contradiction on
# documentation/. An old ignore rule declared «framework repo MUST NOT
# contain documentation/» while ~44 files under documentation/ were TRACKED
# (the docs migration deliberately force-added the Diátaxis tree, and
# CLAUDE.md § S4/S10 reference documentation/ paths as shipped surfaces).
# The consequence: every new doc needed `git add -f`, and a contributor
# reasonably concluded the path was wrong.
#
# The TREE is canon. These tests pin both halves of the agreement:
#   1. tracked documentation/ files must NOT be gitignored
#      (`git check-ignore` on a tracked doc path must FAIL), and
#   2. the tracked tree itself must still exist (so half 1 cannot pass
#      vacuously against an emptied checkout).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "documentation/ tree is tracked (non-empty git ls-files)" {
    # grep/wc over ls-files — count must be > 0; a zero here means the
    # sibling check-ignore test below would pass vacuously.
    count="$(git -C "$REPO_ROOT" ls-files documentation/ | wc -l)"
    [ "$count" -gt 0 ]
}

@test "no tracked documentation/ file matches an ignore pattern (--no-index)" {
    # LOAD-BEARING SUBTLETY: modern git check-ignore consults the INDEX and
    # never reports a tracked file as ignored, so a plain check-ignore over
    # tracked paths passes even WITH the blanket rule present (verified on
    # git 2.43). `--no-index` tests the pattern set itself — which is what
    # this regression is about.
    ignored="$(git -C "$REPO_ROOT" ls-files documentation/ \
        | git -C "$REPO_ROOT" check-ignore --stdin --no-index 2>/dev/null | wc -l)"
    [ "$ignored" -eq 0 ]
}

@test "a brand-new doc file would NOT need git add -f (the original pain shape)" {
    # The defect's operator-visible symptom: every NEW doc under
    # documentation/ needed `git add -f`. Probe a hypothetical new path —
    # check-ignore matches patterns for paths that do not exist yet, and an
    # untracked path is index-invisible, so no --no-index caveat applies.
    run git -C "$REPO_ROOT" check-ignore -q "documentation/how-to/hypothetical-new-doc-probe.md"
    [ "$status" -eq 1 ]
}

@test "no blanket documentation/ ignore rule survives in .gitignore" {
    # Anchored to a whole-line rule: a negation (`!documentation/...`) or a
    # deliberately narrowed subpath rule would not match this pattern.
    count="$(grep -cE '^documentation/[[:space:]]*$' "$REPO_ROOT/.gitignore" || true)"
    [ "$count" -eq 0 ]
}

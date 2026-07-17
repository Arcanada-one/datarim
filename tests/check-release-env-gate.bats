#!/usr/bin/env bats
# check-release-env-gate.bats — regression guard for the release env-gate refinement
# (TUNE-0415). Patch/minor releases must NOT be routed through an environment whose
# deployment-branch policy could reject tag pushes; only a major bump uses
# `release-manual`. Reintroducing `release-auto` on the fallback branch would revive
# the "every tagged release fails at job start" incident.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
}

@test "release.yml still routes a major bump to release-manual" {
    run grep -Fq "'release-manual'" "$RELEASE_YML"
    [ "$status" -eq 0 ]
}

@test "release.yml no longer routes patch/minor through release-auto" {
    # the environment expression must not select the 'release-auto' env literal
    # (a backtick mention in the explanatory comment is fine)
    run grep -Fq "'release-auto'" "$RELEASE_YML"
    [ "$status" -ne 0 ]
}

@test "release.yml non-major fallback is an empty environment name" {
    # the conditional must fall through to '' (no environment) for non-major
    run grep -Eq "bump_level == 'major' && 'release-manual'\\) \\|\\| ''" "$RELEASE_YML"
    [ "$status" -eq 0 ]
}

@test "release.yml parses as valid YAML" {
    run python3 -c "import sys, yaml; yaml.safe_load(open('$RELEASE_YML'))"
    [ "$status" -eq 0 ]
}

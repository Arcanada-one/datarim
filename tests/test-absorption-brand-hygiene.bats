#!/usr/bin/env bats
#
# test-absorption-brand-hygiene — regression guard for absorbed-skill brand
# hygiene (source: reflection Class A Proposal 3).
#
# Background: several Datarim skills were absorbed/rewritten from external
# frameworks. During that absorption, cross-references to the external
# framework's own brand namespace (its skill-invocation prefix) sometimes
# leaked into the shipped skill/agent/command/template text — e.g. a stray
# "see also: <external-brand>:some-skill" left over from the source
# material. Those references are meaningless (and mildly embarrassing) in
# a fully-absorbed, standalone Datarim artifact: the external skill no
# longer exists in this repo, so the cross-reference is either dead or,
# worse, silently promotes a competing framework's brand inside Datarim's
# own shipped instruction surface.
#
# This test asserts the marker string never reappears in the four shipped
# scopes. It is intentionally a plain grep-count assertion, not a
# structural parser — the goal is a trip-wire against regression, not a
# general brand-reference linter.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
MARKER="superpowers:"

@test "T1: no absorbed-brand cross-references in shipped scopes" {
    run grep -rn "$MARKER" "$REPO_ROOT/skills" "$REPO_ROOT/agents" "$REPO_ROOT/commands" "$REPO_ROOT/templates"
    # grep exit 1 == no matches found, which is the PASS condition here.
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "T2: documents why — marker denotes an external-framework skill prefix, not a Datarim namespace" {
    # Datarim's own skill-reference convention never uses this prefix; any
    # occurrence must be a leftover from absorbed source material, not a
    # legitimate in-repo cross-reference. This case is a no-op assertion
    # that exists to keep the rationale co-located with the enforcement
    # test (T1) for future maintainers.
    run grep -rln "$MARKER" "$REPO_ROOT/skills" "$REPO_ROOT/agents" "$REPO_ROOT/commands" "$REPO_ROOT/templates"
    [ "$status" -eq 1 ]
}

@test "T3: repo root resolves correctly from BATS_TEST_DIRNAME regardless of invocation CWD" {
    [ -d "$REPO_ROOT/skills" ]
    [ -d "$REPO_ROOT/agents" ]
    [ -d "$REPO_ROOT/commands" ]
    [ -d "$REPO_ROOT/templates" ]
}

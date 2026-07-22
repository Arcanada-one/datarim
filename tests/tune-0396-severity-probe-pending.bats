#!/usr/bin/env bats
#
# TUNE-0396 E2 — spec-regression for the severity-probe-pending child-brief
# contract in skills/init-task-persistence/SKILL.md (source: reflection-AUTH-0091
# § E2).
#
# Contract: the init-task-persistence skill MUST carry a dedicated
# `## Severity-probe-pending child-brief contract` subsection that (a) requires
# the spawning task's /dr-archive to record an unprobed blast-radius branch as
# an explicit, mandatory deliverable in the CHILD task's init-task/brief, (b)
# documents the opt-in `severity_probe_pending` frontmatter marker, and (c) ties
# enforcement to the existing expectations/qa gate. Wording MUST be stack-neutral.

FRAGMENT="${BATS_TEST_DIRNAME}/../skills/init-task-persistence/SKILL.md"

@test "init-task-persistence SKILL.md exists" {
    [ -f "$FRAGMENT" ]
}

@test "'## Severity-probe-pending child-brief contract' subsection header is present" {
    run grep -E "^## Severity-probe-pending child-brief contract\b" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

_body() {
    local start next
    start=$(grep -n "^## Severity-probe-pending child-brief contract\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    [ -n "$start" ] || return 1
    next=$(awk -v s="$start" 'NR>s && /^## / {print NR; exit}' "$FRAGMENT")
    [ -z "$next" ] && next=$(wc -l < "$FRAGMENT")
    sed -n "${start},${next}p" "$FRAGMENT"
}

@test "requires recording the unprobed branch in the CHILD init-task/brief" {
    body=$(_body)
    printf '%s' "$body" | grep -qiE "child"
    printf '%s' "$body" | grep -qiE "unprobed|not probed|not.* probed"
    printf '%s' "$body" | grep -qiE "mandatory deliverable|named scope item|MUST NOT close"
}

@test "names /dr-archive as the producer of the child brief item" {
    _body | grep -qE "/dr-archive"
}

@test "documents the severity_probe_pending frontmatter marker" {
    _body | grep -qE "severity_probe_pending"
}

@test "the marker is registered in the Optional fields block" {
    grep -qE "severity_probe_pending:" "$FRAGMENT"
}

@test "ties enforcement to the expectations / qa gate" {
    _body | grep -qiE "expectations|/dr-qa|/dr-compliance|BLOCK"
}

@test "wording is stack-neutral in the new subsection (no project / org names)" {
    ! _body | grep -qiE "Auth Arcana|Arcanada-one"
}

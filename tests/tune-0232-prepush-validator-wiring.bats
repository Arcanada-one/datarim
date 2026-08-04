#!/usr/bin/env bats
# tune-0232-prepush-validator-wiring.bats
#
# Anti-decay wiring for skills/security-baseline/SKILL.md § "Pre-push local
# validation (advisory)". The section instructs an agent bootstrapping a
# brand-new repo (wired to the reusable CI workflows) to run three local
# validators BEFORE the first `git push`:
#
#   1. check-security-policy.sh --validate-yaml   (accepted-risk register)
#   2. check-expectations-checklist.sh --verify   (operator wishlist)
#   3. actionlint                                 (GitHub Actions workflows)
#
# The checklist is prose executed by an LLM — nothing structural breaks when a
# validator name is dropped in an edit, so the decay is silent. This suite is
# the load-bearing regression: it extracts EXACTLY the pre-push section (from
# its heading to the next heading or horizontal rule) and asserts each of the
# three validator invocations still appears inside it — not merely somewhere
# in the file, where e.g. the S7 CI table also cites actionlint.

SKILL="${BATS_TEST_DIRNAME}/../skills/security-baseline/SKILL.md"

# Print only the pre-push section body: start at the section heading, stop at
# the next markdown heading (#..######) or a horizontal rule.
prepush_section() {
    # `#+` not `#{1,6}` — regex intervals are unsupported in historic BSD awk
    # (macOS CI leg); `+` is portable POSIX ERE.
    awk '
        /^#+ .*Pre-push local validation/ { inside = 1; next }
        inside && (/^#+ / || /^---[[:space:]]*$/) { exit }
        inside { print }
    ' "$SKILL"
}

@test "skill file exists and carries the pre-push section heading" {
    [ -f "$SKILL" ]
    # grep -c (not -q) — SIGPIPE-safe under pipefail
    count="$(grep -cE '^#{1,6} .*Pre-push local validation' "$SKILL")"
    [ "$count" -ge 1 ]
}

@test "pre-push section extraction yields a non-empty body" {
    body="$(prepush_section)"
    [ -n "$body" ]
}

@test "pre-push section names check-security-policy.sh --validate-yaml" {
    body="$(prepush_section)"
    count="$(printf '%s\n' "$body" | grep -c 'check-security-policy.sh --validate-yaml')"
    [ "$count" -ge 1 ]
}

@test "pre-push section names check-expectations-checklist.sh --verify" {
    body="$(prepush_section)"
    count="$(printf '%s\n' "$body" | grep -c 'check-expectations-checklist.sh --verify')"
    [ "$count" -ge 1 ]
}

@test "pre-push section names actionlint against the workflows glob" {
    body="$(prepush_section)"
    count="$(printf '%s\n' "$body" | grep -c 'actionlint')"
    [ "$count" -ge 1 ]
}

@test "all three validators appear inside the SECTION, not merely elsewhere in the file" {
    # The specificity guard: mutate the extraction target, not the file scan.
    # If the section were emptied and the names survived only in the S7 table,
    # the three tests above must fail — this test documents that intent by
    # asserting the section body itself carries all three.
    body="$(prepush_section)"
    for needle in 'check-security-policy.sh' 'check-expectations-checklist.sh' 'actionlint'; do
        count="$(printf '%s\n' "$body" | grep -c "$needle")"
        [ "$count" -ge 1 ]
    done
}

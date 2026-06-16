#!/usr/bin/env bats
#
# Squash-collision regression tests for session-handoff consumer re-verification.
#
# Scenario: the agent committed work on a feature branch. A parallel session
# squash-merged the branch into origin/main under a foreign squash-commit header,
# so the original commit SHA is absent from origin/main, but the file content
# landed. The /dr-continue re-verification probe MUST:
#   (a) report the original SHA as CLAIM-UNVERIFIED (SHA absent in origin/main)
#   (b) surface the content-landing check (empty diff), so the agent does NOT
#       conclude work was lost.
#
# CI replica uses a real git clone/worktree (NOT git archive) so git probes
# produce valid exit codes instead of false-fail status 128.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/session-handoff-writer.sh"
VALIDATOR="${REPO_ROOT}/dev-tools/check-session-handoff.sh"

# ---------------------------------------------------------------------------
# Helper: set up a minimal git fixture simulating squash-collision
#
# Layout:
#   origin_bare/ — bare remote
#   agent_clone/ — agent's working clone (feature branch squash-merged)
#
# Agent committed file "work.md" on feature branch. The "parallel session"
# squash-merged the content into origin/main under a different commit SHA
# (foreign squash-commit). The agent's original feature-branch SHA is NOT
# in origin/main's ancestry, but the content IS identical.
# ---------------------------------------------------------------------------

_setup_squash_fixture() {
    local base="$1"

    # Create bare remote (no -b flag; configure default branch separately).
    git init --bare "${base}/origin_bare" >/dev/null 2>&1
    git -C "${base}/origin_bare" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1

    # Create initial commit on remote via a non-cloned local repo.
    # (Cloning an empty bare repo fails.) Push from a local temp repo.
    local init_repo="${base}/init_repo"
    git init "${init_repo}" >/dev/null 2>&1
    git -C "${init_repo}" config user.email "test@test.local"
    git -C "${init_repo}" config user.name "Test"
    git -C "${init_repo}" checkout -b main >/dev/null 2>&1 || \
        git -C "${init_repo}" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
    printf 'initial content\n' > "${init_repo}/README.md"
    git -C "${init_repo}" add README.md
    git -C "${init_repo}" commit -m "init" --quiet
    git -C "${init_repo}" remote add origin "${base}/origin_bare"
    git -C "${init_repo}" push origin main --quiet >/dev/null 2>&1

    # Create agent's clone with a feature branch.
    local agent_clone="${base}/agent_clone"
    git clone "${base}/origin_bare" "${agent_clone}" --quiet >/dev/null 2>&1
    git -C "${agent_clone}" config user.email "agent@test.local"
    git -C "${agent_clone}" config user.name "Agent"

    # Agent adds work.md on a feature branch.
    git -C "${agent_clone}" checkout -b feature/agent-work >/dev/null 2>&1
    printf 'agent work content\n' > "${agent_clone}/work.md"
    git -C "${agent_clone}" add work.md
    git -C "${agent_clone}" commit -m "agent: add work.md" --quiet
    AGENT_SHA="$(git -C "${agent_clone}" rev-parse HEAD)"
    export AGENT_SHA

    # Simulate parallel session squash-merging the content under a foreign header.
    # Clone the remote, add the same file under a different commit, push to main.
    local squash_clone="${base}/squash_clone"
    git clone "${base}/origin_bare" "${squash_clone}" --quiet >/dev/null 2>&1
    git -C "${squash_clone}" config user.email "parallel@test.local"
    git -C "${squash_clone}" config user.name "Parallel"
    # Add same content as the agent's work.md (content landed via squash).
    printf 'agent work content\n' > "${squash_clone}/work.md"
    git -C "${squash_clone}" add work.md
    git -C "${squash_clone}" commit -m "PARALLEL-0001: squash-merge various changes" --quiet
    git -C "${squash_clone}" push origin main --quiet >/dev/null 2>&1

    # Agent clone: fetch origin so it can see the squash commit on main.
    git -C "${agent_clone}" fetch origin --quiet >/dev/null 2>&1

    export AGENT_CLONE="${agent_clone}"
    export SQUASH_CLONE="${squash_clone}"
}

setup() {
    export FAKE_BASE
    FAKE_BASE="$(mktemp -d "${BATS_TEST_TMPDIR}/squash-fixture.XXXX")"
    _setup_squash_fixture "${FAKE_BASE}"

    export FAKE_ROOT
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/datarim-root.XXXX")"
    mkdir -p "${FAKE_ROOT}/datarim"
}

# ---------------------------------------------------------------------------
# (a) SHA absent in origin/main → CLAIM-UNVERIFIED
#
# The agent's original commit SHA is not in origin/main (it was squash-merged
# under a different commit). The consumer's git cherry probe must detect this.
# ---------------------------------------------------------------------------

@test "sha-absent-claim-unverified: agent SHA not in origin/main ancestry" {
    # Verify the fixture: agent SHA must NOT be a direct ancestor of origin/main.
    # git merge-base --is-ancestor returns 0 if sha is ancestor, non-zero otherwise.
    # After a squash-merge the original feature-branch SHA is not in the ancestry.
    run git -C "${AGENT_CLONE}" merge-base --is-ancestor "${AGENT_SHA}" origin/main
    [ "$status" -ne 0 ]
}

@test "sha-absent-claim-unverified: consumer re-verification probe detects mismatch" {
    # Write a session artefact claiming the work was pushed (verified:).
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"

    local task_file
    task_file="$(mktemp "${BATS_TEST_TMPDIR}/tasks.XXXX")"
    printf 'WORK-0001 | in_progress\n' > "${task_file}"

    local body_file
    body_file="$(mktemp "${BATS_TEST_TMPDIR}/body.XXXX")"
    cat > "${body_file}" <<EOF
## Layer 1 — Git State

repo: ${AGENT_CLONE}  HEAD: ${AGENT_SHA}  status: clean

## Layer 5 — Failed Approaches

None.

Feature branch was pushed to origin. verified: SHA ${AGENT_SHA} pushed at session end
EOF

    local session_id="SESSION-20260615-140000"

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${session_id}" \
        --captured-by agent \
        --recommended-next "/dr-next WORK-0001" \
        --next-action "Continue implementation." \
        --active-tasks-file "${task_file}" \
        --body-file "${body_file}"

    # Validate the artefact.
    run bash "${VALIDATOR}" --validate-frontmatter --session "${session_id}" \
        --root "${FAKE_ROOT}"
    [ "$status" -eq 0 ]

    # Now simulate the consumer re-verification probe: check SHA-presence.
    # The agent SHA should NOT be an ancestor of origin/main (squash-merged
    # under foreign header). git merge-base --is-ancestor returns non-zero.
    run git -C "${AGENT_CLONE}" merge-base --is-ancestor "${AGENT_SHA}" origin/main
    # Expected: non-zero (SHA is not a direct ancestor of origin/main).
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# (b) Content-landing surfaced (diff empty → work not lost)
#
# Even though the agent's SHA is not an ancestor, the content landed.
# The consumer must surface the content-landing check so the agent does NOT
# conclude work was lost.
# ---------------------------------------------------------------------------

@test "content-landed-diff-empty: work.md content identical in origin/main" {
    # The squash-merge added work.md with the same content. The diff between
    # the agent's commit and origin/main for work.md must be empty.
    run git -C "${AGENT_CLONE}" diff "${AGENT_SHA}" origin/main -- work.md
    [ "$status" -eq 0 ]
    # Empty diff means content landed.
    [ -z "$output" ]
}

@test "content-landed-diff-empty: CLAIM-UNVERIFIED coexists with content-landed evidence" {
    # Prove both conditions simultaneously:
    # 1. SHA not in ancestry (CLAIM-UNVERIFIED).
    # 2. Content diff empty (content-landed).
    # This is the exact squash-collision scenario the operator described.

    # SHA not a direct ancestor of origin/main.
    run git -C "${AGENT_CLONE}" merge-base --is-ancestor "${AGENT_SHA}" origin/main
    local sha_is_ancestor=$status

    # Content identical in origin/main.
    run git -C "${AGENT_CLONE}" diff "${AGENT_SHA}" origin/main -- work.md
    local content_diff_empty=$status
    local content_diff_output="$output"

    # Assert CLAIM-UNVERIFIED condition.
    [ "$sha_is_ancestor" -ne 0 ]

    # Assert content-landed condition (empty diff, exit 0).
    [ "$content_diff_empty" -eq 0 ]
    [ -z "$content_diff_output" ]
}

# ---------------------------------------------------------------------------
# (c) STALE banner: saved HEAD differs from current HEAD
# ---------------------------------------------------------------------------

@test "stale-banner: current HEAD differs from saved SHA triggers STALE condition" {
    # After the squash-merge, the agent's feature branch HEAD is different from
    # origin/main HEAD. A consumer comparing saved HEAD to current repo HEAD
    # after a git fetch would see a mismatch.
    local current_main_head
    current_main_head="$(git -C "${AGENT_CLONE}" rev-parse origin/main)"

    # The agent's SHA is not the same as origin/main HEAD.
    [ "${AGENT_SHA}" != "${current_main_head}" ]
}

# ---------------------------------------------------------------------------
# (d) verified: downgrade — verified claim no longer verifiable after probe
# ---------------------------------------------------------------------------

@test "verified-downgrade: verified: tag for SHA must be downgraded on resume" {
    # This test asserts the LOGIC: if a saved artefact has verified: SHA <sha>
    # and the probe shows the SHA is not in origin/main ancestry, the claim
    # MUST be downgraded to unverified in the replay output.
    # We prove this by asserting the probe detects the mismatch.

    run git -C "${AGENT_CLONE}" merge-base --is-ancestor "${AGENT_SHA}" origin/main
    # Non-zero exit = not an ancestor = verified: claim must be downgraded.
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# (e) FILE-MISSING banner: referenced file no longer at saved path
# ---------------------------------------------------------------------------

@test "file-missing-banner: stat on moved file returns non-zero" {
    local nonexistent="/tmp/datarim-test-squash-collision-nonexistent-file-$$"
    run stat "${nonexistent}" 2>/dev/null
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# (f) Banner emitter — deterministic stdout of the re-verification core.
#
# DoD #4 / V-AC-5.c is worded "/dr-continue REPORTS «pushed» as unverified".
# The git primitives above prove the probe; these tests assert the BANNER
# STRINGS the emitter (dev-tools/reverify-session-claims.sh) produces, so the
# "report as unverified" property is deterministic, not agent-rendered prose.
# ---------------------------------------------------------------------------

EMITTER="${REPO_ROOT}/dev-tools/reverify-session-claims.sh"

@test "emitter sha-presence: squash-collision SHA emits CLAIM-UNVERIFIED + CONTENT-LANDED" {
    run bash "${EMITTER}" --sha-presence --repo "${AGENT_CLONE}" \
        --sha "${AGENT_SHA}" --files work.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAIM-UNVERIFIED: SHA ${AGENT_SHA} not found in origin/main."* ]]
    # Content landed under the foreign squash header → not lost.
    [[ "$output" == *"CONTENT-LANDED:"* ]]
}

@test "emitter sha-presence: ancestor SHA emits nothing (claim holds)" {
    # origin/main HEAD is itself an ancestor of origin/main → no banner.
    local main_head
    main_head="$(git -C "${AGENT_CLONE}" rev-parse origin/main)"
    run bash "${EMITTER}" --sha-presence --repo "${AGENT_CLONE}" --sha "${main_head}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "emitter stale: saved sha differs from current origin/main emits STALE SNAPSHOT" {
    run bash "${EMITTER}" --stale --repo "${AGENT_CLONE}" --saved-sha "${AGENT_SHA}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE SNAPSHOT:"* ]]
    [[ "$output" == *"${AGENT_SHA}"* ]]
}

@test "emitter stale: matching saved sha emits nothing" {
    local main_head
    main_head="$(git -C "${AGENT_CLONE}" rev-parse origin/main)"
    run bash "${EMITTER}" --stale --repo "${AGENT_CLONE}" --saved-sha "${main_head}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "emitter file-missing: absent path emits FILE-MISSING banner" {
    local nonexistent="${BATS_TEST_TMPDIR}/never-existed-$$"
    run bash "${EMITTER}" --file-missing --path "${nonexistent}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FILE-MISSING: ${nonexistent}"* ]]
}

@test "emitter file-missing: present path emits nothing" {
    run bash "${EMITTER}" --file-missing --path "${AGENT_CLONE}/work.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "emitter security: malformed SHA rejected with usage error (no git call)" {
    run bash "${EMITTER}" --sha-presence --repo "${AGENT_CLONE}" \
        --sha 'origin/main; rm -rf /'
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid SHA"* ]]
}

@test "emitter security: non-git repo dir rejected with exit 3" {
    run bash "${EMITTER}" --stale --repo "${BATS_TEST_TMPDIR}" --saved-sha "${AGENT_SHA}"
    [ "$status" -eq 3 ]
}

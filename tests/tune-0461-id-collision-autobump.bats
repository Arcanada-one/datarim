#!/usr/bin/env bats
# tune-0461-id-collision-autobump.bats
#
# Verifies: V-AC-01, V-AC-03, V-AC-04 (Group A — markdown-contract assertions)
#           V-AC-05 (Group B — empirical: next-free-id.sh fixture-driven auto-bump)
#
# Group A: grep-based assertions that the probe-before-emit invariant, the
#   pinned max()+1 formula, and auto-bump wording are present in the three
#   canonical shipped surfaces.
#
# Group B: fixture-driven harness that seeds a collision and asserts:
#   (a) a warning is emitted to stderr
#   (b) the returned ID is auto-bumped past the claimed candidate
#
# These are CONTRACT tests (markdown-contract asserts) + FUNCTIONAL tests
# (shell helper). /dr-quick and /dr-init are agent-consumed markdown, not
# binaries; Group A validates their prose contract. Group B validates the
# testable shell helper that implements the same semantics.

CMDS_DIR="${BATS_TEST_DIRNAME}/../commands"
SKILLS_DIR="${BATS_TEST_DIRNAME}/../skills"
HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"

# ── Group A — markdown-contract assertions ────────────────────────────────────

# V-AC-01: probe-before-emit invariant present in BOTH command files
@test "A01: dr-quick.md contains probe-before-emit invariant" {
    grep -iE "do not (emit|announce).*id.*until|probe completes" \
        "${CMDS_DIR}/dr-quick.md"
}

@test "A01: dr-init.md contains probe-before-emit invariant" {
    grep -iE "do not (emit|announce).*id.*until|probe completes" \
        "${CMDS_DIR}/dr-init.md"
}

# V-AC-02: dr-quick.md Stage Header no longer forces line-1 ID
@test "A02: dr-quick.md Stage Header does not say 'first line of every response'" {
    # The old wording "Every operator-facing response begins with ... as the first line"
    # must be gone from the Stage Header section.
    run grep -c "Every operator-facing response begins with" "${CMDS_DIR}/dr-quick.md"
    [ "$output" = "0" ]
}

# V-AC-03: pinned formula present in all three files (grep -F exact match)
FORMULA="max(claimed across archive/datarim filenames ∪ line-leading index rows in datarim/tasks.md and datarim/backlog.md) + 1"

@test "A03: dr-quick.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" "${CMDS_DIR}/dr-quick.md"
}

@test "A03: dr-init.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" "${CMDS_DIR}/dr-init.md"
}

@test "A03: task-identity-and-context.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" \
        "${SKILLS_DIR}/datarim-system/task-identity-and-context.md"
}

# V-AC-04: auto-bump behaviour documented in all three files
@test "A04: dr-quick.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" "${CMDS_DIR}/dr-quick.md"
}

@test "A04: dr-init.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" "${CMDS_DIR}/dr-init.md"
}

@test "A04: task-identity-and-context.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" \
        "${SKILLS_DIR}/datarim-system/task-identity-and-context.md"
}

# ── Group B — fixture-driven auto-bump harness (V-AC-05) ─────────────────────

setup() {
    # Create a temporary fixture directory for each test
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    # TUNE-0542: next-free-id.sh now also reads two HOST-GLOBAL claim surfaces
    # (live tmux session names, git worktree/branch names). Neutralise them so
    # this spec stays hermetic on a host running dozens of unrelated agents.
    # Their own coverage lives in tune-0542-next-free-id-claim-surfaces.bats.
    export DATARIM_ID_TMUX_SESSIONS=""
    export DATARIM_ID_GIT_REFS=""
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

@test "B01: next-free-id.sh returns PREFIX-0001 when no IDs exist" {
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
}

@test "B02: next-free-id.sh picks max+1 from tasks.md" {
    printf -- '- TUNE-0005 · some task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0003 · another task\n' >> "${FIXTURE_DIR}/datarim/tasks.md"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0006" ]
}

@test "B03: next-free-id.sh picks max across all three surfaces" {
    # tasks.md: TUNE-0003, backlog.md: TUNE-0005, archive: TUNE-0007
    printf -- '- TUNE-0003 · task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0005 · backlog item\n' > "${FIXTURE_DIR}/datarim/backlog.md"
    printf '# archive-TUNE-0007.md\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0007.md"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0008" ]
}

@test "B04: next-free-id.sh auto-bumps when max+1 is already claimed (collision)" {
    # TUNE-0542: fixture rewritten, assertion intent unchanged.
    #
    # This case has always been about the auto-bump path, but it used to build
    # the collision out of TUNE-9999 + TUNE-10000 — i.e. out of the very
    # 5-digit overflow TUNE-0542 proved is the defect. It only ever "collided"
    # because the unanchored grep read TUNE-10000 as the number 1000, leaving
    # the candidate to land on a literal the ceiling had mis-parsed.
    #
    # A genuine collision needs a claim the CEILING cannot see and the PROBE
    # can — that is what the two-bias split means. Here TUNE-0006 is claimed
    # only in another row's prose: ceiling = 0005, candidate = 0006, probe
    # catches it, bump → 0007.
    printf -- '- TUNE-0005 · high-watermark task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0003 · earlier row [superseded by TUNE-0006, taken by a parallel session]\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    # Use separate stdout/stderr capture so the warning line does not pollute
    # the ID comparison (bats `run` mixes stderr into $output by default)
    STDOUT_FILE="$(mktemp)"
    STDERR_FILE="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
    STATUS=$?
    CHOSEN_ID="$(cat "${STDOUT_FILE}")"
    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"

    [ "$STATUS" -eq 0 ]
    # Should auto-bump past the claimed TUNE-0006 → TUNE-0007
    [ "${CHOSEN_ID}" = "TUNE-0007" ]
}

@test "B05: next-free-id.sh emits a WARNING to stderr on collision" {
    # Same collision setup as B04 (see the TUNE-0542 note there).
    printf -- '- TUNE-0005 · high-watermark task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0003 · earlier row [superseded by TUNE-0006, taken by a parallel session]\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    # Capture stderr separately
    STDOUT_FILE="$(mktemp)"
    STDERR_FILE="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
    STATUS=$?

    [ "$STATUS" -eq 0 ]
    # Stdout: auto-bumped ID
    CHOSEN_ID="$(cat "${STDOUT_FILE}")"
    [ "$CHOSEN_ID" = "TUNE-0007" ]
    # Stderr: warning line present (regex V-AC-05)
    grep -iE "WARNING.*auto.?bump|parallel.session|already claimed" "${STDERR_FILE}"

    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"
}

@test "B06: next-free-id.sh rejects invalid prefix (non-uppercase)" {
    run bash "${HELPER}" "tune" "${FIXTURE_DIR}"
    [ "$status" -ne 0 ]
    echo "$output" | grep -iE "invalid prefix"
}

@test "B07: next-free-id.sh handles TUNE-9999 boundary — absorbs TUNE-0229 DoD" {
    # CONTRACT REVERSED BY TUNE-0542 — deliberate, not a regression.
    #
    # This case previously required TUNE-10000 as the correct answer at the
    # boundary, reading TUNE-0229's DoD ("no 4-digit truncation") as a demand
    # that the allocator overflow into five digits. That reading does not
    # survive contact with the surfaces the allocator has to re-read:
    # `archive-{PREFIX}-[0-9][0-9][0-9][0-9].md`, the dr-init Step-4 probe and
    # the public-surface regexes are all fixed at four digits. An emitted
    # TUNE-10000 is invisible to every one of them, so the NEXT call cannot see
    # it as claimed and hands the same ID out again — the boundary case was
    # specified to produce a permanent self-collision.
    #
    # TUNE-0229's actual requirement is preserved and is stronger here: the
    # helper must never SILENTLY mis-handle the boundary. It now fails loudly.
    # Silence, not the digit count, was the thing worth testing.
    printf -- '- TUNE-9999 · task at boundary\n' > "${FIXTURE_DIR}/datarim/tasks.md"

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -ne 0 ]
    # Never a truncated ID (TUNE-0000 / TUNE-9999 reused) and never a 5-digit one
    echo "$output" | grep -qvE 'TUNE-[0-9]{5}' || { echo "5-digit ID emitted"; false; }
    echo "$output" | grep -iE "exhaust|4-digit"
}

# ── Group C — archived-only ID not reused (AC-3, AC-4) ───────────────────────
#
# Regression for the archived-only-ID reuse class: when an ID exists ONLY in
# documentation/archive/ and is absent from live tasks.md / backlog.md, the
# helper must still treat it as claimed (include it in the max) and return the
# next free ID rather than reusing the archived ID.
#
# C01 + C02 → AC-3. C03 → AC-4 (fixture isolation: helper greps only the
# caller-supplied root; no leakage from the live workspace or cwd).

@test "C01: next-free-id.sh does not reuse an archived-only ID" {
    # Archive has TUNE-0461; tasks.md and backlog.md are absent (empty fixture).
    # Helper must return TUNE-0462, not TUNE-0001 or TUNE-0461.
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    printf '# archive-TUNE-0461.md\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0461.md"
    # tasks.md and backlog.md intentionally absent — helper must tolerate missing files

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0462" ]
}

@test "C02: archive max beats live tasks/backlog when higher; archived ID still not reused" {
    # tasks.md: TUNE-0003, backlog.md: TUNE-0005 (both lower than archive max).
    # Archive: TUNE-0461 — the overall max is 461, so the next free ID is TUNE-0462.
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    printf -- '- TUNE-0003 · task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0005 · backlog item\n' > "${FIXTURE_DIR}/datarim/backlog.md"
    printf '# archive-TUNE-0461.md\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0461.md"

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0462" ]
}

@test "C03: next-free-id.sh greps only the supplied root — no leakage from real workspace" {
    # Supply a completely empty fixture root with an unrelated prefix (ZZ).
    # Even if the real workspace has high TUNE IDs, the helper must return ZZ-0001
    # because the fixture root has no ZZ entries at all.
    # This proves fixture isolation: helper greps only $DATARIM_ROOT.
    run bash "${HELPER}" "ZZ" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "ZZ-0001" ]
}

# ── Group D — real-workspace defects surfaced by dogfooding the wired helper ──
#
# Both regressions are invisible to small synthetic fixtures with clean IDs and
# only appear against a real archive. They are guarded here directly.
#
# D01 → base-10 parse. A zero-padded numeric whose 3rd/4th digit is >= 8 (0058,
# 0079, 0090) is read as OCTAL by a bare `(( 0058 ))`, errors, and is silently
# skipped — corrupting the max. The `10#` pin fixes it. Without the fix this test
# returns the wrong next-free ID (it skips 0058 from the max).
# D02 → filename-based archive surface. Archived docs cite illustrative IDs in
# their PROSE (e.g. a test write-up mentioning a fixture id like PREFIX-9999). A
# content-grep over the archive scoops those up and inflates the max. The claim
# surface is the `archive-{ID}.md` FILENAME, not body text.

@test "D01: zero-padded ID with octal-trap digit (0058) is parsed base-10, not skipped" {
    # tasks.md holds TUNE-0058. A bare octal parse of 0058 errors and skips it,
    # leaving max=0 → wrong result TUNE-0001. With base-10 the answer is TUNE-0059.
    printf -- '- TUNE-0058 · octal-trap watermark\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    STDOUT_FILE="$(mktemp)"
    STDERR_FILE="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
    STATUS=$?
    CHOSEN_ID="$(cat "${STDOUT_FILE}")"
    # No octal arithmetic errors must reach stderr
    run cat "${STDERR_FILE}"
    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"
    [ "$STATUS" -eq 0 ]
    [ "$CHOSEN_ID" = "TUNE-0059" ]
    echo "$output" | grep -vqi "value too great for base" || { echo "octal error leaked to stderr"; false; }
}

@test "D02: archive ID cited only in PROSE does not pollute the max (filename surface)" {
    # A genuinely-archived low task (archive-TUNE-0010.md) whose BODY happens to
    # cite a high fixture ID in prose. The helper must claim 0010 (the filename)
    # and ignore the prose mention → next free is TUNE-0011, never TUNE-10000.
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    printf '# archive-TUNE-0010.md\n\nSee the test fixture TUNE-9999 documented below.\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0010.md"

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0011" ]
}

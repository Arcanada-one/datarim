#!/usr/bin/env bats
#
# TUNE-0422 — Secrecy-aware project-init scaffolding contract.
#
# Origin: reflection-CUBR-0002 primary lesson (scaffold-leak pattern). During
# CUBR-0002, /dr-init project-init populated documentation/reference/architecture.md
# with the verbatim secret algorithm BEFORE the secrecy constraint was codified,
# committing a public-surface leak. Root cause: no secrecy gate at scaffold time.
#
# Scaffolding is LLM-driven markdown, not an executable script, so the contract is
# enforced by grepping the shipped instruction surface (same model as
# scaffolding-no-abolished-files.bats):
#
#   1. project-init/SKILL.md declares a secrecy signal + a [REDACTED] stub rule +
#      a public-surface prohibition.
#   2. templates/project-docs-stubs.md ships a secrecy-aware architecture.md
#      variant whose mechanism sections are [REDACTED — see CLAUDE.md § Secrecy].
#   3. templates/project-claude-md.md carries a conditional ## Secrecy block with a
#      README-tolerant grep gate (find -name 'README*', NOT a bare grep glob that
#      errors on absent README — reflection minor-lesson #1).
#   4. commands/dr-init.md mentions the secrecy signal at the project-init load.
#   5. The new secrecy surface is English-only (shipped-surface rule).
#
# If any of these fail, the secrecy-aware scaffold contract has drifted — restore
# it before merging.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SKILL="${REPO_ROOT}/skills/project-init/SKILL.md"
STUBS="${REPO_ROOT}/templates/project-docs-stubs.md"
CLAUDE_TMPL="${REPO_ROOT}/templates/project-claude-md.md"
DR_INIT="${REPO_ROOT}/commands/dr-init.md"

setup() {
    for f in "${SKILL}" "${STUBS}" "${CLAUDE_TMPL}" "${DR_INIT}"; do
        [ -f "${f}" ] || {
            echo "FIXTURE MISSING: ${f}" >&2
            return 1
        }
    done
}

# ---------- 1. SKILL.md — secrecy signal + REDACTED rule + prohibition ----------

@test "project-init SKILL declares a secrecy-aware scaffolding step" {
    run grep -qiE 'secrecy-aware' "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "project-init SKILL names the secrecy signal (secrecy: annotation or keyword)" {
    run grep -qiE 'secrecy:' "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "project-init SKILL prescribes the REDACTED mechanism-free stub" {
    run grep -qF 'REDACTED' "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "project-init SKILL forbids populating the public surface with mechanism" {
    # The prohibition must reference the public Diataxis surface and 'mechanism'.
    run grep -qiE 'public (Di.taxis )?surface|public docs' "${SKILL}"
    [ "$status" -eq 0 ]
    run grep -qiE 'mechanism' "${SKILL}"
    [ "$status" -eq 0 ]
}

# ---------- 2. project-docs-stubs.md — secrecy-aware architecture variant ----------

@test "project-docs-stubs ships a REDACTED secrecy-aware architecture variant" {
    run grep -qF 'REDACTED — see CLAUDE.md § Secrecy' "${STUBS}"
    [ "$status" -eq 0 ]
}

# ---------- 3. project-claude-md.md — conditional Secrecy block + gate ----------

@test "project CLAUDE template carries a Secrecy section" {
    run grep -qF '## Secrecy' "${CLAUDE_TMPL}"
    [ "$status" -eq 0 ]
}

@test "project CLAUDE template Secrecy block is a conditional include" {
    run grep -qiF 'SECRECY-BLOCK' "${CLAUDE_TMPL}"
    [ "$status" -eq 0 ]
}

@test "secrecy gate is README-tolerant (uses find -name README*, not a bare grep glob)" {
    # Reflection minor-lesson #1: a bare 'grep ... README*' errors (ls: No such
    # file) when no README exists. The shipped gate must resolve README via
    # 'find ... -name README*' so an absent README is graceful.
    run grep -qE "find .* -name ['\"]?README" "${CLAUDE_TMPL}"
    [ "$status" -eq 0 ]
}

@test "secrecy gate does not pass a bare README* glob straight to grep" {
    # Guard against regressing to the errored form 'grep ... README*'.
    run grep -nE 'grep[^|]*README\*' "${CLAUDE_TMPL}"
    [ "$status" -ne 0 ]
}

# ---------- 4. dr-init.md — secrecy signal at project-init load ----------

@test "dr-init command mentions the secrecy signal" {
    run grep -qiE 'secrecy' "${DR_INIT}"
    [ "$status" -eq 0 ]
}

# ---------- 5. English-only shipped surface ----------

@test "new secrecy surface is English-only (no Cyrillic in Secrecy blocks)" {
    # The secrecy block, stub banner, and gate are shipped English-only surface.
    # Grep the Secrecy-related lines for Cyrillic; none is allowed.
    for f in "${SKILL}" "${STUBS}" "${CLAUDE_TMPL}"; do
        run grep -nE 'Secrecy|REDACTED' "${f}"
        # collect matching lines, then assert none contain Cyrillic
        matched="$output"
        printf '%s\n' "${matched}" | grep -qP '[\x{0400}-\x{04FF}]' && {
            echo "Cyrillic found in secrecy surface of ${f}:" >&2
            printf '%s\n' "${matched}" | grep -nP '[\x{0400}-\x{04FF}]' >&2
            return 1
        }
    done
    return 0
}

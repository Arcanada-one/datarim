#!/usr/bin/env bats
# datarim-doctor.bats — TUNE-0071 thin-schema migration tool

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/datarim-doctor"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks" "$TMPROOT/documentation/archive/framework"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Compliance detection (dry-run) -----------------------------------------

@test "T1 dry-run on legacy tasks.md → exit 1 + finding count" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    [[ "$output" == *"finding"* ]] || [[ "$output" == *"non-compliant"* ]]
}

@test "T2 dry-run on compliant tasks.md → exit 0" {
    cp "$FIXTURES/compliant-tasks.md" "$TMPROOT/datarim/tasks.md"
    # Description files must exist for entries referenced
    : > "$TMPROOT/datarim/tasks/TUNE-0071-task-description.md"
    : > "$TMPROOT/datarim/tasks/LEGACY-0001-task-description.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T3 dry-run on empty datarim/ → exit 0" {
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T4 quiet mode produces no stdout" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "T1b (TUNE-0072) --quiet on legacy → exit 1 (parity with verbose)" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --quiet
    [ "$status" -eq 1 ]
}

@test "T17b (TUNE-0072) --quiet on compliant input → exit 0 (parity with verbose)" {
    cp "$FIXTURES/compliant-tasks.md" "$TMPROOT/datarim/tasks.md"
    : > "$TMPROOT/datarim/tasks/TUNE-0071-task-description.md"
    : > "$TMPROOT/datarim/tasks/LEGACY-0001-task-description.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Migration (--fix) -------------------------------------------------------

@test "T5 --fix on legacy tasks.md produces compliant one-liner" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # tasks.md must contain one-liner format
    grep -qE '^- TUNE-0071 · in_progress · P[0-3] · L[1-4] · .+ → tasks/TUNE-0071-task-description\.md$' \
        "$TMPROOT/datarim/tasks.md"
    grep -qE '^- LEGACY-0001 · in_progress · P[0-3] · L[1-4] · .+ → tasks/LEGACY-0001-task-description\.md$' \
        "$TMPROOT/datarim/tasks.md"
}

@test "T6 --fix creates description file for each task" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/tasks/TUNE-0071-task-description.md" ]
    [ -f "$TMPROOT/datarim/tasks/LEGACY-0001-task-description.md" ]
}

@test "T7 description file has YAML frontmatter with required keys" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    desc="$TMPROOT/datarim/tasks/TUNE-0071-task-description.md"
    head -1 "$desc" | grep -q '^---$'
    grep -qE '^id: TUNE-0071$' "$desc"
    grep -qE '^status: in_progress$' "$desc"
    grep -qE '^complexity: L3$' "$desc"
    grep -qE '^priority: P1$' "$desc"
}

@test "T8 --fix idempotent: second run produces no changes" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    cp -r "$TMPROOT/datarim" "$TMPROOT/datarim.first"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    diff -r "$TMPROOT/datarim" "$TMPROOT/datarim.first" >&2
    [ "$(diff -r "$TMPROOT/datarim" "$TMPROOT/datarim.first" 2>&1 | wc -l | tr -d ' ')" = "0" ]
}

@test "T9 --fix on legacy backlog.md produces one-liner pending entries" {
    cp "$FIXTURES/legacy-backlog.md" "$TMPROOT/datarim/backlog.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    grep -qE '^- TUNE-0099 · pending · P[0-3] · L[1-4] · .+ → tasks/TUNE-0099-task-description\.md$' \
        "$TMPROOT/datarim/backlog.md"
    grep -qE '^- INFRA-0099 · pending · P[0-3] · L[1-4] · .+ → tasks/INFRA-0099-task-description\.md$' \
        "$TMPROOT/datarim/backlog.md"
}

@test "T10 --fix deletes legacy progress.md after preserving data" {
    cp "$FIXTURES/legacy-progress.md" "$TMPROOT/datarim/progress.md"
    cp "$FIXTURES/legacy-activeContext.md" "$TMPROOT/datarim/activeContext.md"
    # Pre-create archive files so doctor knows data is preserved
    : > "$TMPROOT/documentation/archive/framework/archive-TUNE-0069.md"
    : > "$TMPROOT/documentation/archive/framework/archive-TUNE-0070.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [ ! -f "$TMPROOT/datarim/progress.md" ]
}

# --- Security ---------------------------------------------------------------

@test "T11 path traversal attempt in tasks.md → exit 4" {
    cp "$FIXTURES/crafted-traversal.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 4 ]
    [[ "$output" == *"traversal"* ]] || [[ "$output" == *"security"* ]] || [[ "$output" == *"reject"* ]]
}

@test "T12 ROOT outside cwd resolves correctly via canonicalise" {
    # absolute path acceptable
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
    # nonexistent root → usage error
    run "$DOCTOR" --root="/tmp/nonexistent-doctor-$$"
    [ "$status" -ne 0 ]
}

# --- Regex compliance --------------------------------------------------------

@test "T13 generated lines match canonical regex" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    # Every non-empty bullet line must match the canonical schema
    while IFS= read -r line; do
        [[ "$line" =~ ^-\ [A-Z]{2,10}-[0-9]{4}\ ·\ (in_progress|blocked|not_started|pending|blocked-pending|cancelled)\ ·\ P[0-3]\ ·\ L[1-4]\ ·\ .{1,80}\ →\ tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$ ]]
    done < <(grep -E '^- [A-Z]+-' "$TMPROOT/datarim/tasks.md")
}

# --- CLI / UX ----------------------------------------------------------------

@test "T14 --help prints usage and exit 0" {
    run "$DOCTOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fix"* ]]
    [[ "$output" == *"--root"* ]]
}

@test "T15 unknown flag → exit 64 (usage error)" {
    run "$DOCTOR" --bogus-flag
    [ "$status" -eq 64 ]
}

# --- TUNE-0077: data-loss safety contract -----------------------------------

@test "T16 (TUNE-0077) --fix creates pre-write tarball backup of datarim/" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # Exactly one tarball expected, named datarim-backup-*.tgz
    n="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz' | wc -l | tr -d ' ')"
    [ "$n" = "1" ]
    # Backup tarball must contain the original tasks.md (pre-fix state)
    tarball="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz')"
    tar tzf "$tarball" | grep -q 'tasks.md'
}

@test "T17 (TUNE-0077) --fix backup file mode is 0600 (umask 077)" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    tarball="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz')"
    mode="$(stat -f '%Lp' "$tarball" 2>/dev/null || stat -c '%a' "$tarball" 2>/dev/null)"
    [ "$mode" = "600" ]
}

@test "T18 (TUNE-0077) post-fix invariant: emitted_count >= parsed_count" {
    # Synthetic 3-task fixture; after --fix all 3 IDs MUST appear as one-liners
    cat > "$TMPROOT/datarim/backlog.md" <<'EOF'
# Backlog

## Pending

### TUNE-9001: Safety check 1

- **Status:** pending
- **Priority:** P2
- **Complexity:** Level 1

### TUNE-9002: Safety check 2

- **Status:** pending
- **Priority:** P3
- **Complexity:** Level 2

### TUNE-9003: Safety check 3

- **Status:** pending
- **Priority:** P2
- **Complexity:** Level 1
EOF
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    n="$(grep -c '^- TUNE-900' "$TMPROOT/datarim/backlog.md")"
    [ "$n" = "3" ]
}

@test "T19 (TUNE-0077) printf hardening: no 'printf \"\$' patterns in script" {
    # Bug C class: printf "$line" misparses '-' prefix as flag
    ! grep -nE 'printf "\$' "$DOCTOR"
}

@test "T20 (TUNE-0077) --fix on body starting with '-' produces clean stderr" {
    # Body line starting with '-' must not trigger 'printf: invalid option' errors
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

### TUNE-9100: Body with leading dash

- **Status:** in_progress
- **Priority:** P2
- **Complexity:** Level 1

#### Overview

- bullet line that starts with a dash and could trigger printf flag parsing
- another such bullet
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # No 'invalid option' or '-:' printf errors in stderr
    [[ "$output" != *"invalid option"* ]]
    [[ "$output" != *"printf:"* ]] || [[ "$output" != *"-:"* ]]
}

@test "T22 (TUNE-0073) dry-run on rich-block activeContext.md → exit 1 + finding count" {
    cp "$FIXTURES/legacy-activeContext-richblock.md" "$TMPROOT/datarim/activeContext.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    [[ "$output" == *"finding"* ]] || [[ "$output" == *"non-compliant"* ]]
}

@test "T23 (TUNE-0073) --fix migrates rich-block activeContext.md to thin one-liners (with cross-lookup)" {
    # tasks.md provides priority/complexity for INFRA-0099 (rich-block has none)
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- INFRA-0099 · in_progress · P1 · L2 · Cross-lookup pathway entry → tasks/INFRA-0099-task-description.md
EOF
    cp "$FIXTURES/legacy-activeContext-richblock.md" "$TMPROOT/datarim/activeContext.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # Inline (Level 2, P2) parsed
    grep -qE '^- TUNE-0099 · in_progress · P2 · L2 · Rich-block migrator pass → tasks/TUNE-0099-task-description\.md$' \
        "$TMPROOT/datarim/activeContext.md"
    # Cross-lookup from tasks.md (P1, L2)
    grep -qE '^- INFRA-0099 · in_progress · P1 · L2 · Cross-lookup pathway entry → tasks/INFRA-0099-task-description\.md$' \
        "$TMPROOT/datarim/activeContext.md"
    # Forbidden section "Последние завершённые" stripped
    ! grep -q 'Последние завершённые' "$TMPROOT/datarim/activeContext.md"
    # Idempotency: 2nd --fix does not change file
    sha1="$(shasum "$TMPROOT/datarim/activeContext.md" | awk '{print $1}')"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    sha2="$(shasum "$TMPROOT/datarim/activeContext.md" | awk '{print $1}')"
    [ "$sha1" = "$sha2" ]
    # Post-fix dry-run is exit 0
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T24 (TUNE-0076) Pass4-cancelled: synthesises documentation/archive/cancelled/archive-{ID}.md with frontmatter" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    [ -f "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md" ]
    grep -q "^id: CONN-9001$" "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md"
    grep -q "^status: cancelled$" "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md"
    grep -q "^cancelled_at: 2026-04-19$" "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md"
    grep -q "^reason:" "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md"
    grep -q "^source: synthesised" "$TMPROOT/documentation/archive/cancelled/archive-CONN-9001.md"
    [ -f "$TMPROOT/documentation/archive/cancelled/archive-TUNE-9001.md" ]
}

@test "T25 (TUNE-0076) Pass4-completed-existing: verified existing archive is not rewritten" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    mkdir -p "$TMPROOT/documentation/archive/framework"
    cat > "$TMPROOT/documentation/archive/framework/archive-TUNE-9101.md" <<'EOF'
# Archive — TUNE-9101 (pre-existing, must be preserved)
EOF
    sha_before="$(shasum "$TMPROOT/documentation/archive/framework/archive-TUNE-9101.md" | awk '{print $1}')"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    sha_after="$(shasum "$TMPROOT/documentation/archive/framework/archive-TUNE-9101.md" | awk '{print $1}')"
    [ "$sha_before" = "$sha_after" ]
}

@test "T26 (TUNE-0076) Pass4-completed-missing: synthesises into general/ with completed_at" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    [ -f "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md" ]
    grep -q "^id: TUNE-9102$" "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md"
    grep -q "^status: completed$" "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md"
    grep -q "^completed_at: 2026-04-26$" "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md"
    grep -q "^source: synthesised" "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md"
}

@test "T27 (TUNE-0076) Pass4-conflict --no-prompt skips existing archive without ID literal" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    mkdir -p "$TMPROOT/documentation/archive/development" "$TMPROOT/documentation/archive/general"
    # Existing archive without TUNE-9102 literal — conflict
    cat > "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md" <<'EOF'
# Unrelated content (no task ID present)
EOF
    sha_before="$(shasum "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md" | awk '{print $1}')"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    sha_after="$(shasum "$TMPROOT/documentation/archive/general/archive-TUNE-9102.md" | awk '{print $1}')"
    # Skipped (--no-prompt) → file unchanged
    [ "$sha_before" = "$sha_after" ]
}

@test "T28 (TUNE-0076) Pass5-zero-findings: post-fix dry-run on migrated tree → exit 0" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    # backlog-archive.md must be removed after successful Pass 4
    [ ! -f "$TMPROOT/datarim/backlog-archive.md" ]
    # Pre-fix backup must exist
    [ -f "$TMPROOT/datarim/backlog-archive.md.pre-v2.bak" ]
    # Post-fix dry-run is exit 0
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T29 (TUNE-0076) Pass5 idempotent: second --fix on migrated tree → exit 0, no-op" {
    cp "$FIXTURES/legacy-backlog-archive.md" "$TMPROOT/datarim/backlog-archive.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    # Snapshot post-fix state
    n1="$(find "$TMPROOT/documentation/archive" -name 'archive-*.md' | wc -l | tr -d ' ')"
    # Re-run --fix (no backlog-archive.md present)
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    n2="$(find "$TMPROOT/documentation/archive" -name 'archive-*.md' | wc -l | tr -d ' ')"
    [ "$n1" = "$n2" ]
}

# --- TUNE-0085: Pass 6 — operational-files archive section migration ---------

@test "T-ARCHIVE-A1 (TUNE-0085) Pass 6 strips ## Archived bullets when canonical archive exists" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0085 · in_progress · P2 · L3 · doctor enforces canonical contract → tasks/TUNE-0085-task-description.md

## Archived

- **DEV-1212** — старая задача (2026-04-01) → documentation/archive/development/archive-DEV-1212.md
- **DEV-1226** — ещё одна архивная (2026-04-15) → documentation/archive/development/archive-DEV-1226.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0085-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/development" "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1212' '' 'id: DEV-1212' > "$TMPROOT/documentation/archive/development/archive-DEV-1212.md"
    printf '%s\n' '# Archive — DEV-1226' '' 'id: DEV-1226' > "$TMPROOT/documentation/archive/development/archive-DEV-1226.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Archive section header is stripped
    ! grep -q '^## Archived$' "$TMPROOT/datarim/tasks.md"
    # Active section preserved
    grep -qF -- '- TUNE-0085 · in_progress · P2 · L3' "$TMPROOT/datarim/tasks.md"
    # Bold-id bullets are gone
    ! grep -q '\*\*DEV-1212\*\*' "$TMPROOT/datarim/tasks.md"
    ! grep -q '\*\*DEV-1226\*\*' "$TMPROOT/datarim/tasks.md"
    # Post-fix dry-run is exit 0
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T-ARCHIVE-A2 (TUNE-0085) Pass 6 synthesises stub when canonical archive missing" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0085 · in_progress · P2 · L3 · doctor enforces canonical contract → tasks/TUNE-0085-task-description.md

## Archived

- **DEV-1300** — задача без архива (2026-04-20) → documentation/archive/development/archive-DEV-1300.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0085-task-description.md"
    # Note: no DEV-1300 archive doc pre-created → must be synthesised

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Stub synthesised
    [ -f "$TMPROOT/documentation/archive/development/archive-DEV-1300.md" ]
    grep -q '^id: DEV-1300$' "$TMPROOT/documentation/archive/development/archive-DEV-1300.md"
    grep -q '^status: completed$' "$TMPROOT/documentation/archive/development/archive-DEV-1300.md"
    grep -q '^source: synthesised' "$TMPROOT/documentation/archive/development/archive-DEV-1300.md"
    # Bullet stripped from operational file
    ! grep -q '\*\*DEV-1300\*\*' "$TMPROOT/datarim/tasks.md"
    ! grep -q '^## Archived$' "$TMPROOT/datarim/tasks.md"
}

@test "T-ARCHIVE-A3 (TUNE-0085) Pass 6 collision (existing archive without ID) → --no-prompt skip + preserve" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0085 · in_progress · P2 · L3 · doctor enforces canonical contract → tasks/TUNE-0085-task-description.md

## Archived

- **DEV-1400** — collision case (2026-04-22) → documentation/archive/development/archive-DEV-1400.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0085-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/development" "$TMPROOT/documentation/archive/general"
    # Existing archive doc WITHOUT DEV-1400 literal → conflict
    printf '%s\n' '# Unrelated archive' 'no task id literal here' > "$TMPROOT/documentation/archive/development/archive-DEV-1400.md"
    sha_before="$(shasum "$TMPROOT/documentation/archive/development/archive-DEV-1400.md" | awk '{print $1}')"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Existing archive untouched
    sha_after="$(shasum "$TMPROOT/documentation/archive/development/archive-DEV-1400.md" | awk '{print $1}')"
    [ "$sha_before" = "$sha_after" ]
    # Bullet preserved in operational file with manual-migration marker
    grep -q 'pending manual migration' "$TMPROOT/datarim/tasks.md"
    grep -qF -- '**DEV-1400**' "$TMPROOT/datarim/tasks.md"
}

@test "T-ARCHIVE-A4 (TUNE-0085) Pass 6 strips ### Recently Archived from activeContext.md (S2 shape)" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- INFRA-0099 · in_progress · P1 · L2 · stub → tasks/INFRA-0099-task-description.md
EOF
    : > "$TMPROOT/datarim/tasks/INFRA-0099-task-description.md"
    cat > "$TMPROOT/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- INFRA-0099 · in_progress · P1 · L2 · stub → tasks/INFRA-0099-task-description.md

### Recently Archived

- **DEV-1500** (completed, 2026-04-25) — TL;DR, must migrate to documentation/archive/.
- **DEV-1501** (cancelled, 2026-04-26) — cancelled task TL;DR.
EOF
    mkdir -p "$TMPROOT/documentation/archive/development" "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1500' '' 'id: DEV-1500' > "$TMPROOT/documentation/archive/development/archive-DEV-1500.md"
    # DEV-1501 missing → must be synthesised

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # ### Recently Archived header stripped
    ! grep -q 'Recently Archived' "$TMPROOT/datarim/activeContext.md"
    ! grep -q '\*\*DEV-1500\*\*' "$TMPROOT/datarim/activeContext.md"
    ! grep -q '\*\*DEV-1501\*\*' "$TMPROOT/datarim/activeContext.md"
    # Active mirror preserved
    grep -qE '^- INFRA-0099 · in_progress · P1 · L2 · ' "$TMPROOT/datarim/activeContext.md"
    # DEV-1501 stub synthesised with cancelled status
    [ -f "$TMPROOT/documentation/archive/development/archive-DEV-1501.md" ]
    grep -q '^status: cancelled$' "$TMPROOT/documentation/archive/development/archive-DEV-1501.md"
}

@test "T-ARCHIVE-A5 (TUNE-0085) Pass 6 idempotent: second --fix on migrated tree → no changes" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0085 · in_progress · P2 · L3 · stub → tasks/TUNE-0085-task-description.md

## Archived

- **DEV-1600** — entry (2026-04-28) → documentation/archive/development/archive-DEV-1600.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0085-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/development" "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1600' '' 'id: DEV-1600' > "$TMPROOT/documentation/archive/development/archive-DEV-1600.md"

    "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt >/dev/null
    sha1="$(shasum "$TMPROOT/datarim/tasks.md" | awk '{print $1}')"
    n1="$(find "$TMPROOT/documentation/archive" -name 'archive-*.md' | wc -l | tr -d ' ')"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    sha2="$(shasum "$TMPROOT/datarim/tasks.md" | awk '{print $1}')"
    n2="$(find "$TMPROOT/documentation/archive" -name 'archive-*.md' | wc -l | tr -d ' ')"
    [ "$sha1" = "$sha2" ]
    [ "$n1" = "$n2" ]
}

@test "T-ARCHIVE-A6 (TUNE-0085) dry-run reports archive sections as findings (rolled-up)" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0085 · in_progress · P2 · L3 · stub → tasks/TUNE-0085-task-description.md

## Archived

- **DEV-1700** — bullet1 (2026-04-29) → documentation/archive/development/archive-DEV-1700.md
- **DEV-1701** — bullet2 (2026-04-30) → documentation/archive/development/archive-DEV-1701.md
- **DEV-1702** — bullet3 (2026-05-01) → documentation/archive/development/archive-DEV-1702.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0085-task-description.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    # One rolled-up finding per archive section, not 3 individual bullets
    n_findings="$(echo "$output" | grep -c 'archive section')"
    [ "$n_findings" = "1" ]
}

@test "T21 (TUNE-0077) --fix prints backup path in stdout summary" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    run env DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup"* ]] || [[ "$output" == *"Backup"* ]]
    [[ "$output" == *"datarim-backup-"* ]]
}

# --- TUNE-0088: Pass 6 hardening (4 bugs from v1.21.5 distributed-user report) ---

@test "T-ARCHIVE-A6-ext (TUNE-0088) parser does NOT match non-task bold spans (false-positive guard)" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **TODO** — should not parse as task
- **FIXME** — neither should this
- **SECTION-1** — no digits → no match
- **DEV-1226** — legitimate task (2026-04-15) → documentation/archive/general/archive-DEV-1226.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1226' '' 'id: DEV-1226' > "$TMPROOT/documentation/archive/general/archive-DEV-1226.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Legitimate bullet stripped (no orphan TODO/FIXME stubs synthesised)
    [ ! -f "$TMPROOT/documentation/archive/development/archive-TODO.md" ]
    [ ! -f "$TMPROOT/documentation/archive/development/archive-FIXME.md" ]
    [ ! -f "$TMPROOT/documentation/archive/general/archive-TODO.md" ]
    # Non-task bullets preserved with manual-migration marker (parser returned 1 for them)
    grep -qF -- '**TODO**' "$TMPROOT/datarim/tasks.md"
    grep -qF -- '**FIXME**' "$TMPROOT/datarim/tasks.md"
}

@test "T-ARCHIVE-A7 (TUNE-0088) Pass 6 prefers explicit pointer over prefix_to_area" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **DEV-1226** — pointer at general (2026-04-15) → documentation/archive/general/archive-DEV-1226.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    # Canonical at GENERAL, NOT at development (prefix_to_area DEV→development)
    mkdir -p "$TMPROOT/documentation/archive/general" "$TMPROOT/documentation/archive/development"
    printf '%s\n' '# Archive — DEV-1226' '' 'id: DEV-1226' > "$TMPROOT/documentation/archive/general/archive-DEV-1226.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Bullet stripped (explicit pointer found canonical at general)
    run grep -qF -- '**DEV-1226**' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    # No stub synthesised at development (the wrong area)
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1226.md" ]
}

@test "T-ARCHIVE-A7b (TUNE-0088) Pass 6 rejects path-traversal in explicit pointer" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **DEV-9999** — evil pointer (2026-04-15) → documentation/archive/../../etc/passwd
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # /etc/passwd or any traversal MUST NOT be touched (we can't write there as user, but check no warn-stub wrote outside docs_root)
    [ ! -f "$TMPROOT/etc/passwd" ]
    # Bullet preserved with marker OR fallback to prefix_to_area path (either is acceptable, not silent overwrite outside docs_root)
    # Either: bullet still in file (preserved) OR a stub at the prefix_to_area location (development/) — never outside docs_root
    if [ -f "$TMPROOT/documentation/archive/development/archive-DEV-9999.md" ]; then
        # Fallback path: stub written under docs_root (acceptable)
        :
    else
        # Preserve path: bullet retained
        grep -qF -- '**DEV-9999**' "$TMPROOT/datarim/tasks.md"
    fi
}

@test "T-ARCHIVE-A8 (TUNE-0088) parser handles compound IDs DEV-1212-S8 and DEV-1196-FOLLOWUP-*" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **DEV-1212-S8** — compound id (2026-04-10) → documentation/archive/general/archive-DEV-1212-S8.md
- **DEV-1196-FOLLOWUP-lock-ownership-doc** — long followup (2026-04-05) → documentation/archive/general/archive-DEV-1196-FOLLOWUP-lock-ownership-doc.md
- **DEV-1182** soft-delete fix — mid-bold context (2026-04-08) → documentation/archive/general/archive-DEV-1182.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1212-S8' '' 'id: DEV-1212-S8' > "$TMPROOT/documentation/archive/general/archive-DEV-1212-S8.md"
    printf '%s\n' '# Archive — DEV-1196-FOLLOWUP-lock-ownership-doc' '' 'id: DEV-1196-FOLLOWUP-lock-ownership-doc' > "$TMPROOT/documentation/archive/general/archive-DEV-1196-FOLLOWUP-lock-ownership-doc.md"
    printf '%s\n' '# Archive — DEV-1182' '' 'id: DEV-1182' > "$TMPROOT/documentation/archive/general/archive-DEV-1182.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # All three bullets stripped (parser handled compound IDs)
    run grep -q 'DEV-1212-S8' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    run grep -q 'DEV-1196-FOLLOWUP' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    run grep -qF -- '**DEV-1182**' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    # No regressions to development/ subdir
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1212-S8.md" ]
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1196-FOLLOWUP-lock-ownership-doc.md" ]
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1182.md" ]
}

@test "T-ARCHIVE-A9 (TUNE-0088) Pass 6 headerless fallback strips legacy bullets in activeContext.md" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    # activeContext.md has legacy bullets without ### Recently Archived header
    cat > "$TMPROOT/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md
- **DEV-1226** — headerless legacy (2026-04-15) → documentation/archive/general/archive-DEV-1226.md
- **DEV-1212-S8** — compound headerless (2026-04-10) → documentation/archive/general/archive-DEV-1212-S8.md
EOF
    mkdir -p "$TMPROOT/documentation/archive/general"
    printf '%s\n' '# Archive — DEV-1226' '' 'id: DEV-1226' > "$TMPROOT/documentation/archive/general/archive-DEV-1226.md"
    printf '%s\n' '# Archive — DEV-1212-S8' '' 'id: DEV-1212-S8' > "$TMPROOT/documentation/archive/general/archive-DEV-1212-S8.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # One-liner active task preserved
    grep -qE '^- TUNE-0088 · in_progress · P1 · L3 ·' "$TMPROOT/datarim/activeContext.md"
    # Legacy bullets stripped
    run grep -qF -- '**DEV-1226**' "$TMPROOT/datarim/activeContext.md"
    [ "$status" -ne 0 ]
    run grep -qF -- '**DEV-1212-S8**' "$TMPROOT/datarim/activeContext.md"
    [ "$status" -ne 0 ]
    # No stubs at development/ (the explicit pointer at general/ is correct)
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1226.md" ]
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1212-S8.md" ]
}

@test "T-ARCHIVE-A9b (TUNE-0088) headerless fallback synthesises stub when canonical missing" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    cat > "$TMPROOT/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md
- **DEV-9876** — headerless missing canonical (2026-04-20)
EOF

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Stub synthesised at prefix_to_area (DEV → development)
    [ -f "$TMPROOT/documentation/archive/development/archive-DEV-9876.md" ]
    grep -q '^id: DEV-9876$' "$TMPROOT/documentation/archive/development/archive-DEV-9876.md"
    # Bullet stripped from activeContext.md
    run grep -qF -- '**DEV-9876**' "$TMPROOT/datarim/activeContext.md"
    [ "$status" -ne 0 ]
}

@test "T-ARCHIVE-A10 (TUNE-0088) defensive find — canonical at unexpected area subdir" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **DEV-1226** — no explicit pointer (2026-04-15)
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    # prefix_to_area maps DEV → development; canonical actually lives at general/
    mkdir -p "$TMPROOT/documentation/archive/general" "$TMPROOT/documentation/archive/development"
    printf '%s\n' '# Archive — DEV-1226' '' 'id: DEV-1226' > "$TMPROOT/documentation/archive/general/archive-DEV-1226.md"

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # Bullet stripped (defensive find located canonical at unexpected subdir)
    run grep -qF -- '**DEV-1226**' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    # No stub created at development/ (defensive find prevented it)
    [ ! -f "$TMPROOT/documentation/archive/development/archive-DEV-1226.md" ]
    # Original canonical at general/ untouched
    [ -f "$TMPROOT/documentation/archive/general/archive-DEV-1226.md" ]
}

@test "T-REPRODUCER (TUNE-0088) distributed-user vault: 14 mixed shapes stripped, no stubs in development/" {
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0088 · in_progress · P1 · L3 · stub → tasks/TUNE-0088-task-description.md

## Archived

- **DEV-1226** — S1 with explicit pointer (2026-04-15) → documentation/archive/general/archive-DEV-1226.md
- **DEV-1227** — S1 (2026-04-14) → documentation/archive/general/archive-DEV-1227.md
- **DEV-1212-S8** — compound (2026-04-10) → documentation/archive/general/archive-DEV-1212-S8.md
- **DEV-1196-FOLLOWUP-lock-ownership-doc** — long followup (2026-04-05) → documentation/archive/general/archive-DEV-1196-FOLLOWUP-lock-ownership-doc.md
- **DEV-1182** soft-delete fix — mid-bold (2026-04-08) → documentation/archive/general/archive-DEV-1182.md
- **DEV-1174** Phase 8 Step 2 — mid-bold (2026-04-07) → documentation/archive/general/archive-DEV-1174.md
- **DEV-1100** — S1 (2026-04-01) → documentation/archive/general/archive-DEV-1100.md
- **DEV-1101** — S1 (2026-04-02) → documentation/archive/general/archive-DEV-1101.md
- **DEV-1102** — S1 (2026-04-03) → documentation/archive/general/archive-DEV-1102.md
- **DEV-1103** — S1 (2026-04-04) → documentation/archive/general/archive-DEV-1103.md
- **DEV-1104** — S1 (2026-04-05) → documentation/archive/general/archive-DEV-1104.md
- **DEV-1105** — S1 (2026-04-06) → documentation/archive/general/archive-DEV-1105.md
- **DEV-1106** — S1 (2026-04-07) → documentation/archive/general/archive-DEV-1106.md
- **DEV-1107** — S1 (2026-04-08) → documentation/archive/general/archive-DEV-1107.md
EOF
    : > "$TMPROOT/datarim/tasks/TUNE-0088-task-description.md"
    mkdir -p "$TMPROOT/documentation/archive/general"
    for id in DEV-1226 DEV-1227 DEV-1212-S8 DEV-1196-FOLLOWUP-lock-ownership-doc DEV-1182 DEV-1174 DEV-1100 DEV-1101 DEV-1102 DEV-1103 DEV-1104 DEV-1105 DEV-1106 DEV-1107; do
        printf '%s\n' "# Archive — $id" '' "id: $id" > "$TMPROOT/documentation/archive/general/archive-$id.md"
    done

    run "$DOCTOR" --root="$TMPROOT/datarim" --fix --no-prompt
    [ "$status" -eq 0 ]
    # All 14 bullets stripped from operational file
    run grep -q '^## Archived$' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    run grep -qF -- '**DEV-' "$TMPROOT/datarim/tasks.md"
    [ "$status" -ne 0 ]
    # NO stubs created in development/ (the regression we are fixing)
    [ ! -d "$TMPROOT/documentation/archive/development" ] || [ -z "$(ls -A "$TMPROOT/documentation/archive/development" 2>/dev/null)" ]
    # General archives untouched (still 14 files)
    n="$(find "$TMPROOT/documentation/archive/general" -name 'archive-DEV-*.md' | wc -l | tr -d ' ')"
    [ "$n" -eq 14 ]
}

#!/usr/bin/env bats
#
# Spec for dev-tools/cross-kb-evolution-digest.sh — the read-only cross-KB
# evolution surfacing digest. Builds mock KB roots under $BATS_TEST_TMPDIR,
# each with a datarim/history/evolution-log.md table, and asserts the digest
# aggregates framework-relevant rows across KBs, classifies evolution vs
# promotion buckets, surfaces per-KB status (no silent omission), stays
# deterministic, escapes JSON, and never executes untrusted row content.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../cross-kb-evolution-digest.sh"
    [ -f "$TOOL" ] || skip "tool not found: $TOOL"
    ROOTS="$BATS_TEST_TMPDIR/roots"
    mkdir -p "$ROOTS"
}

# mk_kb <name> — create a KB root, echo its path.
mk_kb() {
    local d="$ROOTS/$1"
    mkdir -p "$d/datarim/history"
    echo "$d"
}
# write_log <kbdir> — read table body from stdin, prepend header.
write_log() {
    local log="$1/datarim/history/evolution-log.md"
    {
        echo '# Evolution Log'
        echo ''
        echo '| Date | Task ID | Category | Target | Change | Rationale |'
        echo '|------|---------|----------|--------|--------|-----------|'
        cat
    } >"$log"
}

# ── AC-1: multi-KB aggregation + distinct source labels ──────────────────────
@test "AC-1 aggregates framework rows across two KBs with distinct labels" {
    a=$(mk_kb alpha); b=$(mk_kb beta)
    write_log "$a" <<'EOF'
| 2026-05-01 | AAA-0001 | skill-update | `~/.claude/skills/testing.md` | Added property tests | why |
EOF
    write_log "$b" <<'EOF'
| 2026-05-02 | BBB-0002 | agent-update | agents/developer.md | Self-test section | why |
EOF
    run bash "$TOOL" --kb "$a" --kb "$b"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
    [[ "$output" == *"skills/testing.md"* ]]
    [[ "$output" == *"agents/developer.md"* ]]
}

# ── AC-2: two-bucket classification ──────────────────────────────────────────
@test "AC-2 evolution vs promotion vs dropped classification" {
    a=$(mk_kb mixed)
    write_log "$a" <<'EOF'
| 2026-05-03 | CCC-0003 | skill-update | `~/.claude/skills/security.md` | shared runtime edit | why |
| 2026-05-04 | CCC-0004 | feedback-memory | `~/.claude/projects/p/memory/feedback_x.md` | local memory rule | why |
| 2026-05-05 | CCC-0005 | code-fix | src/app/service.ts | unrelated project code | why |
EOF
    run bash "$TOOL" --kb "$a" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/security.md"* ]]          # evolution bucket
    [[ "$output" == *"feedback_x.md"* ]]               # promotion bucket
    [[ "$output" != *"service.ts"* ]]                  # dropped (other)
    # buckets are labelled in json
    [[ "$output" == *'"evolution"'* ]]
    [[ "$output" == *'"promotion"'* ]]
}

# ── AC-3: no silent omission — explicit per-KB status ────────────────────────
@test "AC-3 missing root => MISSING-ROOT, exit 0" {
    run bash "$TOOL" --kb "$ROOTS/does-not-exist"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING-ROOT"* ]]
}
@test "AC-3 root without history log => NO-LOG, exit 0" {
    d="$ROOTS/nolog"; mkdir -p "$d/datarim/history"  # dir but no file
    run bash "$TOOL" --kb "$d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO-LOG"* ]]
}
@test "AC-3 log with zero framework rows => EMPTY, exit 0" {
    a=$(mk_kb onlyproj)
    write_log "$a" <<'EOF'
| 2026-05-06 | DDD-0006 | code-fix | src/x.ts | project only | why |
EOF
    run bash "$TOOL" --kb "$a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"EMPTY"* ]]
}
@test "AC-3 malformed row counted, other rows survive => OK, exit 0" {
    a=$(mk_kb partial)
    write_log "$a" <<'EOF'
| 2026-05-07 | EEE-0007 | skill-update | skills/testing.md | good row | why |
| this is not a table row at all
| 2026-05-08 |
EOF
    run bash "$TOOL" --kb "$a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/testing.md"* ]]
    [[ "$output" == *"OK"* ]]
}

@test "AC-3 only-corrupt pipe-lines, no valid date-rows => PARSE-ERR" {
    a=$(mk_kb corrupt)
    write_log "$a" <<'EOF'
| garbled row without enough columns
| another | broken | one
EOF
    run bash "$TOOL" --kb "$a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSE-ERR"* ]]
}
@test "AC-3 --since filtering all rows => EMPTY, not PARSE-ERR" {
    a=$(mk_kb allfiltered)
    write_log "$a" <<'EOF'
| 2026-01-01 | SSS-0001 | skill-update | skills/testing.md | old | why |
EOF
    run bash "$TOOL" --kb "$a" --since 2026-12-01
    [ "$status" -eq 0 ]
    [[ "$output" == *"EMPTY"* ]]
    [[ "$output" != *"PARSE-ERR"* ]]
}

# ── AC-4: freshness / SYNC-STALE ─────────────────────────────────────────────
@test "AC-4 fresh log => OK; ancient --now => SYNC-STALE" {
    a=$(mk_kb fresh)
    write_log "$a" <<'EOF'
| 2026-05-09 | FFF-0009 | skill-update | skills/testing.md | row | why |
EOF
    run bash "$TOOL" --kb "$a" --sync-stale 86400
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    # push "now" far into the future so the file mtime is older than the window
    run bash "$TOOL" --kb "$a" --sync-stale 86400 --now 99999999999
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNC-STALE"* ]]
}

# ── AC-5: --since / --json / --out ───────────────────────────────────────────
@test "AC-5 --since filters older rows" {
    a=$(mk_kb since)
    write_log "$a" <<'EOF'
| 2026-04-01 | GGG-0001 | skill-update | skills/old.md | old | why |
| 2026-06-01 | GGG-0002 | skill-update | skills/new.md | new | why |
EOF
    run bash "$TOOL" --kb "$a" --since 2026-05-01
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/new.md"* ]]
    [[ "$output" != *"skills/old.md"* ]]
}
@test "AC-5 --json emits valid json (python-parseable)" {
    a=$(mk_kb jsonkb)
    write_log "$a" <<'EOF'
| 2026-05-10 | HHH-0010 | skill-update | skills/testing.md | plain | why |
EOF
    run bash "$TOOL" --kb "$a" --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c 'import sys,json; json.load(sys.stdin)'
}
@test "AC-5 --json stays valid with hostile quote/backslash cell content" {
    a=$(mk_kb jsonhostile)
    write_log "$a" <<'EOF'
| 2026-05-11 | III-0011 | skill-update | skills/testing.md | he said "hi" \ and c:\path | why |
EOF
    run bash "$TOOL" --kb "$a" --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c 'import sys,json; json.load(sys.stdin)'
}
@test "AC-5 --out writes atomically to a file" {
    a=$(mk_kb outkb)
    write_log "$a" <<'EOF'
| 2026-05-12 | JJJ-0012 | skill-update | skills/testing.md | row | why |
EOF
    out="$BATS_TEST_TMPDIR/digest.txt"
    run bash "$TOOL" --kb "$a" --out "$out"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    grep -q "skills/testing.md" "$out"
}
@test "AC-5 --out refuses a symlink target => exit 3" {
    a=$(mk_kb outsym)
    write_log "$a" <<'EOF'
| 2026-05-13 | KKK-0013 | skill-update | skills/testing.md | row | why |
EOF
    victim="$BATS_TEST_TMPDIR/victim.txt"; echo "SECRET" >"$victim"
    link="$BATS_TEST_TMPDIR/link.txt"; ln -s "$victim" "$link"
    run bash "$TOOL" --kb "$a" --out "$link"
    [ "$status" -eq 3 ]
    grep -q "SECRET" "$victim"   # victim untouched
}

# ── AC-6: deterministic global newest-first sort ─────────────────────────────
@test "AC-6 global newest-first across KBs, stable on repeat" {
    a=$(mk_kb ka); b=$(mk_kb kb)
    write_log "$a" <<'EOF'
| 2026-05-20 | LLL-0001 | skill-update | skills/a1.md | r | why |
| 2026-05-10 | LLL-0002 | skill-update | skills/a2.md | r | why |
EOF
    write_log "$b" <<'EOF'
| 2026-05-15 | MMM-0001 | skill-update | skills/b1.md | r | why |
EOF
    run bash "$TOOL" --kb "$a" --kb "$b"
    [ "$status" -eq 0 ]
    # order of first-occurrence of each target, newest first: a1(20) b1(15) a2(10)
    line_a1=$(echo "$output" | grep -n "skills/a1.md" | head -1 | cut -d: -f1)
    line_b1=$(echo "$output" | grep -n "skills/b1.md" | head -1 | cut -d: -f1)
    line_a2=$(echo "$output" | grep -n "skills/a2.md" | head -1 | cut -d: -f1)
    [ "$line_a1" -lt "$line_b1" ]
    [ "$line_b1" -lt "$line_a2" ]
    # Deterministic: identical output on a second run.
    #
    # The comparison MUST pin --now. The per-KB status block reports `mtime age Ns`
    # derived from `date +%s`, so two unpinned runs that straddle a second boundary
    # differ legitimately in that field alone — which made this assertion flake at
    # roughly 1 run in 4 while saying nothing about ordering stability, the property
    # AC-6 exists to pin. --now is the tool's documented freshness test hook.
    run bash "$TOOL" --kb "$a" --kb "$b" --now 1780000000
    out2="$output"
    run bash "$TOOL" --kb "$a" --kb "$b" --now 1780000000
    [ "$output" = "$out2" ]
}

# ── AC-7: untrusted-row safety (no execution, inert passthrough) ─────────────
@test "AC-7 hostile row does not execute and passes through as data" {
    a=$(mk_kb hostile)
    canary="$BATS_TEST_TMPDIR/canary"
    write_log "$a" <<EOF
| 2026-05-25 | NNN-0001 | skill-update | skills/x.md | \$(touch $canary) \`touch $canary\` ;touch $canary | why |
EOF
    run bash "$TOOL" --kb "$a"
    [ "$status" -eq 0 ]
    [ ! -e "$canary" ]                    # nothing executed
    [[ "$output" == *"skills/x.md"* ]]    # row still surfaced
}
@test "AC-7 Target that looks like a path is never opened" {
    a=$(mk_kb pathish)
    write_log "$a" <<'EOF'
| 2026-05-26 | OOO-0001 | skill-update | ../../../../etc/passwd | traversal target | why |
EOF
    run bash "$TOOL" --kb "$a"
    [ "$status" -eq 0 ]
    # classified as a string; not framework-prefixed => dropped (other), not read
    [[ "$output" != *"root:"* ]]
}

# ── AC-8: usage errors => exit 2, no stdout digest ───────────────────────────
@test "AC-8 unknown flag => exit 2" {
    run bash "$TOOL" --bogus
    [ "$status" -eq 2 ]
}
@test "AC-8 malformed --since => exit 2" {
    a=$(mk_kb sincebad)
    write_log "$a" <<'EOF'
| 2026-05-27 | PPP-0001 | skill-update | skills/x.md | r | why |
EOF
    run bash "$TOOL" --kb "$a" --since 05-2026-01
    [ "$status" -eq 2 ]
}
@test "AC-8 --config with missing file => exit 2" {
    run bash "$TOOL" --config "$ROOTS/no-such.conf"
    [ "$status" -eq 2 ]
}

# ── config-file + discover seams ─────────────────────────────────────────────
@test "config file lists roots (comments + blanks skipped)" {
    a=$(mk_kb cfgkb)
    write_log "$a" <<'EOF'
| 2026-05-28 | QQQ-0001 | skill-update | skills/testing.md | row | why |
EOF
    conf="$BATS_TEST_TMPDIR/kbs.conf"
    {
        echo "# managed KBs"
        echo ""
        echo "$a"
    } >"$conf"
    run bash "$TOOL" --config "$conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/testing.md"* ]]
}
@test "config file is read, never sourced (no command execution)" {
    canary="$BATS_TEST_TMPDIR/conf-canary"
    conf="$BATS_TEST_TMPDIR/evil.conf"
    printf '%s\n' "\$(touch $canary)" >"$conf"
    run bash "$TOOL" --config "$conf"
    [ ! -e "$canary" ]                    # not sourced
}
@test "--discover globs KB roots under a parent dir" {
    a=$(mk_kb disc1); b=$(mk_kb disc2)
    write_log "$a" <<'EOF'
| 2026-05-29 | RRR-0001 | skill-update | skills/a.md | row | why |
EOF
    write_log "$b" <<'EOF'
| 2026-05-30 | RRR-0002 | agent-update | agents/b.md | row | why |
EOF
    run bash "$TOOL" --discover "$ROOTS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills/a.md"* ]]
    [[ "$output" == *"agents/b.md"* ]]
}

# ── empty scope ──────────────────────────────────────────────────────────────
@test "no KBs configured => informational message, exit 0" {
    run bash "$TOOL" --config /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"no managed KBs"* ]]
}

@test "wiring: /dr-archive Step 0.5 invokes the digest under a MANDATORY cue" {
    # A tool landed without enforcement wiring is documented-but-unwired. Assert the
    # reflection step keeps an imperative cue adjacent to the invocation, so a later
    # edit demoting it to advisory prose fails here instead of silently dropping the
    # cross-KB read from reflection.
    CMD="$BATS_TEST_DIRNAME/../../commands/dr-archive.md"
    [ -f "$CMD" ]
    run grep -n 'cross-kb-evolution-digest.sh' "$CMD"
    [ "$status" -eq 0 ]
    inv=$(grep -n 'cross-kb-evolution-digest.sh' "$CMD" | head -1 | cut -d: -f1)
    start=$(( inv > 8 ? inv - 8 : 1 ))
    run sed -n "${start},${inv}p" "$CMD"
    [[ "$output" == *MANDATORY* ]]
}

@test "wiring: this suite is enumerated by the dev-tools-lint bats job" {
    # dev-tools/tests/*.bats is NOT swept by `bats tests/` — the CI job lists files
    # explicitly, so an unlisted suite never runs anywhere.
    WF="$BATS_TEST_DIRNAME/../../.github/workflows/dev-tools-lint.yml"
    [ -f "$WF" ]
    run grep -c 'bats dev-tools/tests/cross-kb-evolution-digest.bats' "$WF"
    [ "$status" -eq 0 ]
}

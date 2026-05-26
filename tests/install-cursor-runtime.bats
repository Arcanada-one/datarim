#!/usr/bin/env bats
#
# TUNE-0304 Phase 4: contract tests for --with-cursor install path.
#
# T47-T50 per plan §6.5:
#   T47 — `install.sh --with-cursor --dry-run` reports planned Cursor paths,
#         exits 0, writes nothing.
#   T48 — `install.sh --with-cursor` against an isolated CURSOR_DIR creates
#         ~/.cursor/skills/<name>.md flat files for each migrated skill
#         and exits 0.
#   T49 — idempotency: re-running --with-cursor with no source changes
#         produces no diff on the target.
#   T50 — `--help` advertises the --with-cursor flag and CURSOR_DIR env var.
#
# Cursor's discovery semantics are not officially documented as of
# 2026-Q2; the install creates flat .md mirrors of skills/<name>/SKILL.md
# (one file per skill). This ships behind R7 (accepted-risk: deferred
# Cursor-runtime smoke; operator validates on real Cursor install).

INSTALL_SH="${BATS_TEST_DIRNAME}/../install.sh"

setup() {
    TMPSRC="$(mktemp -d)"
    TMPCURSOR="$(mktemp -d)"
    # Minimal source tree: two migrated skills + one .system skill.
    mkdir -p "$TMPSRC/skills/alpha" "$TMPSRC/skills/beta" "$TMPSRC/skills/.system/bundled"
    cat >"$TMPSRC/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: alpha skill
---
alpha body
EOF
    cat >"$TMPSRC/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: beta skill
---
beta body
EOF
    cat >"$TMPSRC/skills/.system/bundled/SKILL.md" <<'EOF'
---
name: bundled
description: codex bundled
---
EOF
    # install.sh resolves paths via dirname; copy it into a sibling of TMPSRC
    # so it can locate skills/ next to itself.
    cp "$INSTALL_SH" "$TMPSRC/install.sh"
    chmod +x "$TMPSRC/install.sh"
}

teardown() {
    rm -rf "$TMPSRC" "$TMPCURSOR"
}

@test "T47: --with-cursor --dry-run reports planned paths, writes nothing" {
    CURSOR_DIR="$TMPCURSOR" run "$TMPSRC/install.sh" --with-cursor --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"cursor"* ]] || [[ "$output" == *"Cursor"* ]]
    # Target untouched.
    [ ! -e "$TMPCURSOR/skills/alpha.md" ]
}

@test "T48: --with-cursor creates flat .md mirrors of each skill" {
    CURSOR_DIR="$TMPCURSOR" run "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ]
    [ -f "$TMPCURSOR/skills/alpha.md" ]
    [ -f "$TMPCURSOR/skills/beta.md" ]
    run cat "$TMPCURSOR/skills/alpha.md"
    [[ "$output" == *"name: alpha"* ]]
    [[ "$output" == *"alpha body"* ]]
}

@test "T48b: --with-cursor excludes skills/.system/ namespace (C3)" {
    CURSOR_DIR="$TMPCURSOR" run "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ]
    [ ! -f "$TMPCURSOR/skills/bundled.md" ]
    [ ! -d "$TMPCURSOR/skills/.system" ]
}

@test "T49: --with-cursor is idempotent (re-run produces no diff)" {
    CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes >/dev/null
    sha1_first=$(find "$TMPCURSOR/skills" -type f -exec sha1sum {} \; 2>/dev/null | \
                 sort | sha1sum 2>/dev/null || \
                 find "$TMPCURSOR/skills" -type f -exec shasum {} \; | sort | shasum)
    CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes >/dev/null
    sha1_second=$(find "$TMPCURSOR/skills" -type f -exec sha1sum {} \; 2>/dev/null | \
                  sort | sha1sum 2>/dev/null || \
                  find "$TMPCURSOR/skills" -type f -exec shasum {} \; | sort | shasum)
    [ "$sha1_first" = "$sha1_second" ]
}

@test "T50: --help advertises --with-cursor flag" {
    run "$TMPSRC/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--with-cursor"* ]]
}

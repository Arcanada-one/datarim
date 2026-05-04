#!/usr/bin/env bats
# doc-fanout-lint.bats — bats coverage for doc-fanout-lint.sh
#
# Coverage:
#   T1  parses bundled-style config (block YAML, AWK path)
#   T2  parses minimal config and emits no violations on green tree
#   T3  malformed config (missing version) → fatal exit 2
#   T4  unknown version → fatal exit 2
#   T5  grep_in_file green
#   T6  grep_in_file missing → ERR + grep-missing rule code
#   T7  file_must_exist green
#   T8  file_must_exist missing → WARN + file-missing
#   T9  count_match mismatch → ERR + count-mismatch
#   T10 cross_root without --allow-cross-root → fatal exit 2
#   T11 cross_root with --allow-cross-root resolves OK
#   T12 default (compact-ish) format
#   T13 --verbose multiline output
#   T14 SUMMARY line content
#   T15 --strict promotes warning to exit 1

LINT="$BATS_TEST_DIRNAME/../doc-fanout-lint.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    export TMPROOT
}

teardown() {
    [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

mk_artefact() {
    # mk_artefact <relpath>
    local p="$TMPROOT/$1"
    mkdir -p "$(dirname "$p")"
    echo "# $(basename "$p" .md)" > "$p"
}

mk_consumer() {
    # mk_consumer <relpath> <content>
    local p="$TMPROOT/$1"
    mkdir -p "$(dirname "$p")"
    printf '%s\n' "$2" > "$p"
}

write_cfg() {
    # write_cfg <content>
    cat > "$TMPROOT/.doc-fanout.yml" <<EOF
$1
EOF
}

# -------------------------------------------------------------------- T1, T2
@test "T1: linter accepts bundled-shape config and runs to completion" {
    mk_artefact "skills/foo.md"
    mk_consumer "CLAUDE.md" "mentions foo here"
    mk_consumer "docs/skills.md" "1 reusable skill: foo"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: framework_claude
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error
counts:
  - id: skill_count
    source_glob: skills/*.md
    consumer_file: docs/skills.md
    pattern: ([0-9]+) reusable skill
    severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]
}

@test "T2: empty consumer list with green count → exit 0" {
    mk_artefact "skills/a.md"
    mk_artefact "skills/b.md"
    mk_consumer "docs/skills.md" "intro: 2 reusable skill modules"
    write_cfg 'version: 1
counts:
  - id: c
    source_glob: skills/*.md
    consumer_file: docs/skills.md
    pattern: ([0-9]+) reusable skill
    severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]
}

# -------------------------------------------------------------------- T3, T4
@test "T3: missing version → fatal exit 2" {
    mk_consumer "docs/x.md" "stuff"
    cat > "$TMPROOT/.doc-fanout.yml" <<'EOF'
artifacts: []
EOF
    run "$LINT" --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "T4: unknown version → fatal exit 2" {
    write_cfg 'version: 99
counts: []'
    run "$LINT" --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

# -------------------------------------------------------------------- T5, T6
@test "T5: grep_in_file pattern present → exit 0" {
    mk_artefact "skills/foo.md"
    mk_consumer "CLAUDE.md" "see foo for details"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: cl
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]
}

@test "T6: grep_in_file pattern missing → ERR + grep-missing" {
    mk_artefact "skills/foo.md"
    mk_consumer "CLAUDE.md" "no mention here"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: cl
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"grep-missing"* ]]
    [[ "$output" == *"foo"* ]]
}

# -------------------------------------------------------------------- T7, T8
@test "T7: file_must_exist green → exit 0" {
    mk_artefact "agents/x.md"
    mk_consumer "data/x.php" "<?php"
    write_cfg 'version: 1
artifacts:
  - glob: agents/*.md
    name_transform: basename_no_ext
    consumers:
      - id: php
        kind: file_must_exist
        path: data/{name}.php
        severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]
}

@test "T8: file_must_exist missing → WARN with file-missing" {
    mk_artefact "agents/x.md"
    write_cfg 'version: 1
artifacts:
  - glob: agents/*.md
    name_transform: basename_no_ext
    consumers:
      - id: php
        kind: file_must_exist
        path: data/{name}.php
        severity: warning'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]    # warnings alone → exit 0
    [[ "$output" == *"file-missing"* ]]
    [[ "$output" == *"WARN"* ]]
}

# -------------------------------------------------------------------- T9
@test "T9: count_match mismatch → ERR + count-mismatch" {
    mk_artefact "skills/a.md"
    mk_artefact "skills/b.md"
    mk_artefact "skills/c.md"
    mk_consumer "docs/skills.md" "claim: 2 reusable skills total"
    write_cfg 'version: 1
counts:
  - id: skill_count
    source_glob: skills/*.md
    consumer_file: docs/skills.md
    pattern: ([0-9]+) reusable skill
    severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" == *"count-mismatch"* ]]
    [[ "$output" == *"3"* ]]
    [[ "$output" == *"2"* ]]
}

# -------------------------------------------------------------------- T10, T11
@test "T10: cross_root: true without --allow-cross-root → fatal exit 2" {
    mk_artefact "skills/x.md"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: ext
        kind: file_must_exist
        path: ../external/{name}.php
        severity: warning
        cross_root: true'
    run "$LINT" --root "$TMPROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cross-root"* ]] || [[ "$stderr" == *"cross-root"* ]]
}

@test "T11: cross_root with --allow-cross-root resolves" {
    mk_artefact "skills/x.md"
    mkdir -p "$TMPROOT/external"
    : > "$TMPROOT/external/x.php"
    # The artefact is under skills/, but path is `../external/`
    # so we use a sub-root for the linter and keep external above
    SUBROOT="$TMPROOT/sub"
    mkdir -p "$SUBROOT/skills"
    : > "$SUBROOT/skills/x.md"
    mkdir -p "$TMPROOT/external"
    : > "$TMPROOT/external/x.php"
    cat > "$SUBROOT/.doc-fanout.yml" <<'EOF'
version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: ext
        kind: file_must_exist
        path: ../external/{name}.php
        severity: warning
        cross_root: true
EOF
    run "$LINT" --root "$SUBROOT" --allow-cross-root --quiet
    [ "$status" -eq 0 ]
}

# -------------------------------------------------------------------- T12
@test "T12: default format emits one line per violation" {
    mk_artefact "skills/foo.md"
    mk_consumer "CLAUDE.md" "empty"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: cl
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error'
    run "$LINT" --root "$TMPROOT" --quiet
    # Expect ERR <art> -> <surface>: <msg> [<rc>]
    [[ "$output" == *"ERR skills/foo.md -> CLAUDE.md"* ]]
    [[ "$output" == *"[grep-missing]"* ]]
}

# -------------------------------------------------------------------- T13
@test "T13: --verbose emits multi-line output" {
    mk_artefact "skills/foo.md"
    mk_consumer "CLAUDE.md" "empty"
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: cl
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error'
    run "$LINT" --root "$TMPROOT" --verbose --quiet
    [[ "$output" == *"surface:"* ]]
    [[ "$output" == *"note:"* ]]
}

# -------------------------------------------------------------------- T14
@test "T14: SUMMARY line lists errors, warnings, violations, artefacts" {
    mk_artefact "skills/a.md"
    mk_artefact "skills/b.md"
    mk_consumer "CLAUDE.md" ""
    write_cfg 'version: 1
artifacts:
  - glob: skills/*.md
    name_transform: basename_no_ext
    consumers:
      - id: cl
        kind: grep_in_file
        file: CLAUDE.md
        pattern: "{name}"
        severity: error'
    run "$LINT" --root "$TMPROOT"
    [[ "$output" == *"SUMMARY:"* ]]
    [[ "$output" == *"errors"* ]]
    [[ "$output" == *"warnings"* ]]
    [[ "$output" == *"violations"* ]]
    [[ "$output" == *"artefacts"* ]]
}

# -------------------------------------------------------------------- T15
@test "T15: --strict promotes warning to exit 1" {
    mk_artefact "agents/y.md"
    write_cfg 'version: 1
artifacts:
  - glob: agents/*.md
    name_transform: basename_no_ext
    consumers:
      - id: php
        kind: file_must_exist
        path: data/{name}.php
        severity: warning'
    run "$LINT" --root "$TMPROOT" --quiet
    [ "$status" -eq 0 ]   # warning only without --strict
    run "$LINT" --root "$TMPROOT" --strict --quiet
    [ "$status" -eq 1 ]   # warning becomes failure with --strict
}

# -------------------------------------------------------------------- T16, T17
@test "T16: install-hook.sh idempotent (run twice → same content)" {
    HK="$BATS_TEST_DIRNAME/../install-hook.sh"
    REPO="$TMPROOT/repo"
    mkdir -p "$REPO/.git/hooks"
    run "$HK" "$REPO"
    [ "$status" -eq 0 ]
    SUM1="$(shasum "$REPO/.git/hooks/pre-commit" | awk '{print $1}')"
    run "$HK" "$REPO"
    [ "$status" -eq 0 ]
    SUM2="$(shasum "$REPO/.git/hooks/pre-commit" | awk '{print $1}')"
    [ "$SUM1" = "$SUM2" ]
}

@test "T17: install-hook.sh preserves existing hook contents" {
    HK="$BATS_TEST_DIRNAME/../install-hook.sh"
    REPO="$TMPROOT/repo"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'PRE'
#!/usr/bin/env bash
echo "existing hook line"
PRE
    chmod +x "$REPO/.git/hooks/pre-commit"
    run "$HK" "$REPO"
    [ "$status" -eq 0 ]
    grep -q "existing hook line" "$REPO/.git/hooks/pre-commit"
    grep -q "datarim-doc-fanout-lint" "$REPO/.git/hooks/pre-commit"
}

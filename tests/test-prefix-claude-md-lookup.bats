#!/usr/bin/env bats
# test-prefix-claude-md-lookup.bats — TUNE-0030
#
# Verifies that datarim-doctor.sh resolves project prefixes by walking up the
# directory tree and parsing `## Task Prefix Registry` sections in CLAUDE.md.
# Universal area prefixes resolve from the runtime case-statement; project
# prefixes resolve from the consumer's CLAUDE.md; unknown prefixes fall back
# to `general`. Path-traversal and unsafe characters in Archive Subdir are
# rejected.

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMPROOT"
}

@test "T-PFX-1 area prefix resolves without CLAUDE.md (runtime-owned)" {
    cd "$TMPROOT"
    run "$DOCTOR" --probe-prefix=INFRA
    [ "$status" -eq 0 ]
    [ "$output" = "infrastructure" ]
}

@test "T-PFX-2 unknown prefix in empty tree → general" {
    cd "$TMPROOT"
    run "$DOCTOR" --probe-prefix=VERD
    [ "$status" -eq 0 ]
    [ "$output" = "general" ]
}

@test "T-PFX-3 project prefix resolves from CLAUDE.md in cwd" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| ACME | Acme service | acme |
EOF
    cd "$TMPROOT"
    run "$DOCTOR" --probe-prefix=ACME
    [ "$status" -eq 0 ]
    [ "$output" = "acme" ]
}

@test "T-PFX-4 walks up to ancestor CLAUDE.md when local has no registry" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Workspace

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| ACME | Acme service | acme |
EOF
    mkdir -p "$TMPROOT/sub/deeper"
    cd "$TMPROOT/sub/deeper"
    run "$DOCTOR" --probe-prefix=ACME
    [ "$status" -eq 0 ]
    [ "$output" = "acme" ]
}

@test "T-PFX-5 nearer CLAUDE.md without prefix → falls through to outer registry" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Workspace

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| OUTER | Outer project | outer |
EOF
    mkdir -p "$TMPROOT/sub"
    cat > "$TMPROOT/sub/CLAUDE.md" <<'EOF'
# Inner

No registry here.
EOF
    cd "$TMPROOT/sub"
    run "$DOCTOR" --probe-prefix=OUTER
    [ "$status" -eq 0 ]
    [ "$output" = "outer" ]
}

@test "T-PFX-6 path-traversal in Archive Subdir → rejected, falls back to general" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| EVIL | Bad | ../../etc |
EOF
    cd "$TMPROOT"
    out="$("$DOCTOR" --probe-prefix=EVIL 2>/dev/null)"
    [ "$out" = "general" ]
}

@test "T-PFX-7 spaces / uppercase in Archive Subdir → rejected" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| BADCASE | Bad casing | With Spaces |
EOF
    cd "$TMPROOT"
    out="$("$DOCTOR" --probe-prefix=BADCASE 2>/dev/null)"
    [ "$out" = "general" ]
}

@test "T-PFX-8 ### heading-level registry also parsed (Project-Specific zone)" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Project

## Project-Specific Configuration

### Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| NESTED | Nested-zone project | nested |
EOF
    cd "$TMPROOT"
    run "$DOCTOR" --probe-prefix=NESTED
    [ "$status" -eq 0 ]
    [ "$output" = "nested" ]
}

@test "T-PFX-9 invalid probe prefix → exit 64" {
    run "$DOCTOR" --probe-prefix=lowercase
    [ "$status" -eq 64 ]
}

@test "T-PFX-10 area prefix wins over CLAUDE.md row of the same name" {
    cat > "$TMPROOT/CLAUDE.md" <<'EOF'
# Project

## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| INFRA | Trying to override | overridden |
EOF
    cd "$TMPROOT"
    run "$DOCTOR" --probe-prefix=INFRA
    [ "$status" -eq 0 ]
    [ "$output" = "infrastructure" ]
}

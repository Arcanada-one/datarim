#!/usr/bin/env bats
# resolve-datarim-root.bats — canonical KB-root resolver + nesting guard.
#
# Contract: resolve_datarim_root [start] echoes the REPO-ROOT (parent of the
# KB-marked datarim/). assert_not_nested_datarim <root> rejects a root that is
# itself inside a datarim/. Algorithm mirrors the Quick Shell Check documented
# in skills/datarim-system/path-and-storage.md (git-toplevel anchor + walk-up
# fallback + multi-KB advisory).

RESOLVER="$BATS_TEST_DIRNAME/../scripts/lib/resolve-datarim-root.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    TMPROOT="$(cd "$TMPROOT" && pwd -P)"
    mkdir -p "$TMPROOT/.datarim-runtime"
    python3 -c 'import json,sys; from pathlib import Path; p=Path(sys.argv[1]); (p/".datarim-runtime/installation.json").write_text(json.dumps({"schema":1,"project":str(p)}))' "$TMPROOT"
    # A KB carries at least one canonical operational file.
    mkdir -p "$TMPROOT/datarim"
    printf '# Tasks\n' > "$TMPROOT/datarim/tasks.md"
    printf '# Backlog\n' > "$TMPROOT/datarim/backlog.md"
    # deeply nested cwd inside the project (a "space"-style layout)
    mkdir -p "$TMPROOT/spaces/client/code/src"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- resolve_datarim_root: returns repo-root, not the datarim/ dir ----------

@test "R1 resolve from repo-root echoes repo-root" {
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root' _ "$RESOLVER" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

@test "R2 resolve from deeply nested cwd echoes repo-root (not nested dir)" {
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root' _ "$RESOLVER" "$TMPROOT/spaces/client/code/src"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

@test "R3 explicit start_dir arg overrides cwd" {
    run bash -c '. "$1"; cd /; resolve_datarim_root "$2"' _ "$RESOLVER" "$TMPROOT/spaces/client"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

@test "R4 echoes repo-root, never the datarim/ dir itself" {
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root' _ "$RESOLVER" "$TMPROOT/spaces"
    [ "$status" -eq 0 ]
    # must NOT end in /datarim
    [[ "$output" != */datarim ]]
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

@test "R5 a plain datarim/ without KB markers is not a KB" {
    # framework source-tree style: datarim/ exists but has no tasks.md/backlog.md
    local fake="$TMPROOT/code/datarim/skills"
    mkdir -p "$fake"
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root' _ "$RESOLVER" "$fake"
    # should resolve to the real KB at $TMPROOT, walking past the marker-less one
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

@test "R6 no KB anywhere → exit 1 with stderr error" {
    local bare="$(mktemp -d)"
    mkdir -p "$bare/x/y"
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root' _ "$RESOLVER" "$bare/x/y"
    [ "$status" -eq 1 ]
    [[ "$output" == *ERROR* ]] || [[ "$output" == *"not found"* ]]
    rm -rf "$bare"
}

@test "R7 explicit project anchor wins over a closer sibling datarim/" {
    command -v git >/dev/null || skip "git not available"
    # KB at the git toplevel; a closer sibling datarim/ deeper in the tree
    git -C "$TMPROOT" init -q
    mkdir -p "$TMPROOT/spaces/client/datarim"
    printf '# Tasks\n' > "$TMPROOT/spaces/client/datarim/tasks.md"
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root 2>/dev/null' _ "$RESOLVER" "$TMPROOT/spaces/client/code/src"
    [ "$status" -eq 0 ]
    # git anchor returns the toplevel KB, not the nested sibling
    [ "$output" = "$(cd "$TMPROOT" && pwd)" ]
}

# --- assert_not_nested_datarim: refuses an already-nested root --------------

@test "R8 historical KB alone cannot activate a project" {
    rm "$TMPROOT/.datarim-runtime/installation.json"
    run bash -c '. "$1"; resolve_datarim_root "$2"' _ "$RESOLVER" "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No project-local Datarim installation"* ]]
}

@test "R9 nested repository cannot inherit parent KB without opt-in" {
    mkdir -p "$TMPROOT/spaces/client/.git"
    run bash -c '. "$1"; resolve_datarim_root "$2"' _ "$RESOLVER" "$TMPROOT/spaces/client/code/src"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not an approved project context"* ]]
}

@test "N1 a normal repo-root passes the nesting guard" {
    run bash -c '. "$1"; assert_not_nested_datarim "$2"' _ "$RESOLVER" "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "N2 a root that is itself inside a datarim/ is rejected" {
    # the datarim/datarim/ vector: someone passes <repo>/datarim as the root
    run bash -c '. "$1"; assert_not_nested_datarim "$2"' _ "$RESOLVER" "$TMPROOT/datarim"
    [ "$status" -ne 0 ]
    [[ "$output" == *nested* ]] || [[ "$output" == *datarim/datarim* ]]
}

@test "N3 a deeply-nested-inside-datarim root is rejected" {
    mkdir -p "$TMPROOT/datarim/snapshots"
    run bash -c '. "$1"; assert_not_nested_datarim "$2"' _ "$RESOLVER" "$TMPROOT/datarim/snapshots"
    [ "$status" -ne 0 ]
}

# --- multi-KB advisory ------------------------------------------------------

@test "A1 multiple KB-marked datarim/ below the anchor → WARN on stderr" {
    # a misplaced second KB under the resolved root
    mkdir -p "$TMPROOT/spaces/rogue/datarim"
    printf '# Tasks\n' > "$TMPROOT/spaces/rogue/datarim/tasks.md"
    run bash -c '. "$1"; cd "$2"; resolve_datarim_root 2>&1 1>/dev/null' _ "$RESOLVER" "$TMPROOT"
    [[ "$output" == *WARN* ]]
}

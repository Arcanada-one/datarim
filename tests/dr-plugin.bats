#!/usr/bin/env bats
# dr-plugin.bats — TUNE-0101 Plugin System Core (Phase A scaffold).
#
# Coverage in this slice:
#   - validate_plugin_id helper (regex + boundary)
#   - parse_plugin_yaml helper (field extraction, list parsing)
#   - validate_source helper (path traversal, abs path, git URL)
#   - dr-plugin list (first-run bootstrap, active entries rendering)
#
# Out of scope (later phases):
#   - enable / disable / sync / doctor — Phase A3-D (next /dr-do)
#
# Source: plans/TUNE-0101-plan.md § Phase A.

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
LIB_SH="$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh"
TEMPLATE_DIR="$BATS_TEST_DIRNAME/../templates"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
    mkdir -p "$TMPROOT/code/datarim"

    # Mirror the layout `dr-plugin.sh` expects to find via DR_PLUGIN_ROOT.
    cp -r "$BATS_TEST_DIRNAME/../templates" "$TMPROOT/code/datarim/templates"
    cp "$BATS_TEST_DIRNAME/../VERSION" "$TMPROOT/code/datarim/VERSION"

    export DR_PLUGIN_WORKSPACE="$TMPROOT"
    export DR_PLUGIN_RUNTIME_ROOT="$TMPROOT/local-claude"
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT"/{skills,agents,commands,templates}

    # shellcheck source=../scripts/lib/plugin-system.sh
    . "$LIB_SH"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- validate_plugin_id ------------------------------------------------------

@test "T1 validate_plugin_id accepts kebab-case id" {
    run validate_plugin_id "my-plugin"
    [ "$status" -eq 0 ]
}

@test "T2 validate_plugin_id accepts single-letter id" {
    run validate_plugin_id "a"
    [ "$status" -eq 0 ]
}

@test "T3 validate_plugin_id rejects uppercase" {
    run validate_plugin_id "MyPlugin"
    [ "$status" -ne 0 ]
}

@test "T4 validate_plugin_id rejects leading digit" {
    run validate_plugin_id "1plugin"
    [ "$status" -ne 0 ]
}

@test "T5 validate_plugin_id rejects empty id" {
    run validate_plugin_id ""
    [ "$status" -ne 0 ]
}

@test "T6 validate_plugin_id rejects path traversal" {
    run validate_plugin_id "../evil"
    [ "$status" -ne 0 ]
}

@test "T7 validate_plugin_id rejects id over 32 chars" {
    run validate_plugin_id "$(printf 'a%.0s' {1..33})"
    [ "$status" -ne 0 ]
}

@test "T8 validate_plugin_id accepts id at 32-char boundary" {
    run validate_plugin_id "$(printf 'a%.0s' {1..32})"
    [ "$status" -eq 0 ]
}

# --- parse_plugin_yaml -------------------------------------------------------

@test "T10 parse_plugin_yaml extracts id" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" id
    [ "$status" -eq 0 ]
    [ "$output" = "my-plugin" ]
}

@test "T11 parse_plugin_yaml extracts schema_version" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" schema_version
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "T12 parse_plugin_yaml extracts title with spaces" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" title
    [ "$status" -eq 0 ]
    [ "$output" = "My Plugin Title" ]
}

@test "T13 parse_plugin_yaml returns empty for missing field" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" nonexistent
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T14 parse_plugin_yaml rejects CRLF input (security)" {
    printf 'schema_version: 1\r\nid: bad\r\n' > "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" id
    [ "$status" -ne 0 ]
    [[ "$output" == *"CRLF"* ]] || [[ "$output" == *"line ending"* ]]
}

@test "T15 parse_plugin_yaml rejects missing file" {
    run parse_plugin_yaml "$TMPROOT/no-such.yaml" id
    [ "$status" -ne 0 ]
}

# --- parse_yaml_list ---------------------------------------------------------

@test "T20 parse_yaml_list extracts categories" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_yaml_list "$TMPROOT/plugin.yaml" categories
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills"* ]]
    [[ "$output" == *"commands"* ]]
}

@test "T21 parse_yaml_list returns empty for absent key" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_yaml_list "$TMPROOT/plugin.yaml" overrides
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- validate_source ---------------------------------------------------------

@test "T30 validate_source accepts builtin keyword" {
    run validate_source "builtin"
    [ "$status" -eq 0 ]
}

@test "T31 validate_source accepts absolute path under HOME" {
    run validate_source "$HOME/some/path"
    [ "$status" -eq 0 ]
}

@test "T32 validate_source accepts https git URL" {
    run validate_source "https://github.com/Arcanada-one/example-plugin.git"
    [ "$status" -eq 0 ]
}

@test "T33 validate_source rejects path traversal" {
    run validate_source "../evil"
    [ "$status" -ne 0 ]
}

@test "T34 validate_source rejects relative path" {
    run validate_source "some/rel/path"
    [ "$status" -ne 0 ]
}

@test "T35 validate_source rejects URL with embedded credentials" {
    run validate_source "https://user:token@github.com/foo/bar.git"
    [ "$status" -ne 0 ]
    [[ "$output" == *"credential"* ]] || [[ "$output" == *"token"* ]]
}

# --- dr-plugin list (first-run + render) ------------------------------------

@test "T40 dr-plugin list bootstraps datarim-core on first run" {
    [ ! -f "$TMPROOT/datarim/enabled-plugins.md" ]
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/enabled-plugins.md" ]
    grep -q "id: datarim-core" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "protected: true" "$TMPROOT/datarim/enabled-plugins.md"
}

@test "T41 dr-plugin list renders datarim-core entry" {
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"datarim-core"* ]]
    [[ "$output" == *"protected"* ]] || [[ "$output" == *"builtin"* ]]
}

@test "T42 dr-plugin list is idempotent — second run does not duplicate core" {
    run "$PLUGIN_SH" list
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    local count
    count="$(grep -c "id: datarim-core" "$TMPROOT/datarim/enabled-plugins.md")"
    [ "$count" = "1" ]
}

@test "T43 dr-plugin --help exits 0 with usage" {
    run "$PLUGIN_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"dr-plugin"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"enable"* ]]
}

@test "T44 dr-plugin with no args prints usage and exits 64" {
    run "$PLUGIN_SH"
    [ "$status" -eq 64 ]
}

@test "T45 dr-plugin unknown subcommand exits 64" {
    run "$PLUGIN_SH" unknown-cmd
    [ "$status" -eq 64 ]
}

# --- Phase A3 helpers --------------------------------------------------------

# Create a synthetic plugin source dir with given id and category files.
# Usage: make_plugin_source <id> <skill-file>...
make_plugin_source() {
    local id="$1"; shift
    local dir="$TMPROOT/sources/$id"
    mkdir -p "$dir/skills" "$dir/commands"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: $id
title: Test Plugin $id
version: 0.0.1
author: Test
license: MIT
description: Synthetic test plugin.
categories:
  - skills
  - commands
EOF
    local f
    for f in "$@"; do
        echo "# $f content" > "$dir/skills/$f"
    done
    echo "# default command" > "$dir/commands/${id}-cmd.md"
    echo "$dir"
}

# --- enable: happy paths -----------------------------------------------------

@test "T50 enable from local path creates symlinks in runtime root" {
    local src
    src="$(make_plugin_source "demo" "alpha.md" "beta.md")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/demo/alpha.md" ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/demo/beta.md" ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/commands/demo/demo-cmd.md" ]
}

@test "T51 enable updates manifest with file_inventory" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    grep -q "id: demo" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "alpha.md" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "demo-cmd.md" "$TMPROOT/datarim/enabled-plugins.md"
}

@test "T52 enable rejects missing plugin.yaml" {
    mkdir -p "$TMPROOT/sources/broken"
    run "$PLUGIN_SH" enable "$TMPROOT/sources/broken"
    [ "$status" -ne 0 ]
    [[ "$output" == *"plugin.yaml"* ]]
}

@test "T53 enable rejects mismatched id (yaml id != dir name allowed; uses yaml id)" {
    # Plugin id from yaml, not dir name — should succeed and use 'demo' as id.
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    mv "$src" "$TMPROOT/sources/different-name"
    run "$PLUGIN_SH" enable "$TMPROOT/sources/different-name"
    [ "$status" -eq 0 ]
    grep -q "id: demo" "$TMPROOT/datarim/enabled-plugins.md"
}

@test "T54 enable second time is idempotent — no duplicate manifest entry" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    local count
    count="$(grep -c "^- id: demo$" "$TMPROOT/datarim/enabled-plugins.md")"
    [ "$count" = "1" ]
}

@test "T55 enable conflict (target file already exists outside plugin) → fail" {
    # First plugin places foo.md in skills/.
    local s1 s2
    s1="$(make_plugin_source "first" "shared.md")"
    s2="$(make_plugin_source "second" "shared.md")"
    "$PLUGIN_SH" enable "$s1"
    # Manually drop a stray file in the same target path the second plugin would
    # try to create (collision in skills/ root, not under plugin namespace).
    echo "stray" > "$DR_PLUGIN_RUNTIME_ROOT/skills/second"
    run "$PLUGIN_SH" enable "$s2"
    [ "$status" -ne 0 ]
}

@test "T56 enable rejects invalid yaml id" {
    local dir="$TMPROOT/sources/badid"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: ../evil
title: Bad
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    run "$PLUGIN_SH" enable "$dir"
    [ "$status" -ne 0 ]
}

@test "T57 enable rejects schema_version != 1" {
    local dir="$TMPROOT/sources/v2"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 2
id: future
title: Future
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    run "$PLUGIN_SH" enable "$dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"schema_version"* ]]
}

# --- disable: happy paths ----------------------------------------------------

@test "T60 disable removes symlinks" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    "$PLUGIN_SH" enable "$src"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/demo/alpha.md" ]
    run "$PLUGIN_SH" disable demo
    [ "$status" -eq 0 ]
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/demo/alpha.md" ]
    [ ! -d "$DR_PLUGIN_RUNTIME_ROOT/skills/demo" ]
}

@test "T61 disable removes manifest entry" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    "$PLUGIN_SH" enable "$src"
    grep -q "^- id: demo$" "$TMPROOT/datarim/enabled-plugins.md"
    "$PLUGIN_SH" disable demo
    ! grep -q "^- id: demo$" "$TMPROOT/datarim/enabled-plugins.md"
}

@test "T62 disable datarim-core → exit 1 (protected)" {
    "$PLUGIN_SH" list >/dev/null  # bootstrap
    run "$PLUGIN_SH" disable datarim-core
    [ "$status" -eq 1 ]
    [[ "$output" == *"protected"* ]] || [[ "$output" == *"datarim-core"* ]]
}

@test "T63 disable nonexistent plugin → exit 1" {
    "$PLUGIN_SH" list >/dev/null
    run "$PLUGIN_SH" disable no-such-plugin
    [ "$status" -eq 1 ]
}

@test "T64 disable plugin with active dependent → fail with named dependent" {
    local s1
    s1="$(make_plugin_source "base" "core.md")"
    "$PLUGIN_SH" enable "$s1"
    # Build a dependent that depends_on base.
    local d="$TMPROOT/sources/dep"
    mkdir -p "$d/skills"
    cat > "$d/plugin.yaml" <<EOF
schema_version: 1
id: dep
title: Dependent
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
depends_on:
  - base
EOF
    echo "# dep" > "$d/skills/dep.md"
    "$PLUGIN_SH" enable "$d"
    run "$PLUGIN_SH" disable base
    [ "$status" -ne 0 ]
    [[ "$output" == *"dep"* ]]
}

# --- locking ----------------------------------------------------------------

@test "T70 concurrent enable returns lock-busy exit 3" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    # Manually create the lock dir to simulate a held lock.
    mkdir -p "$TMPROOT/datarim/.locks/plugin.lock"
    DR_PLUGIN_LOCK_TIMEOUT=1 run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 3 ]
    rmdir "$TMPROOT/datarim/.locks/plugin.lock"
}

# --- validation surface for cmd_enable ---------------------------------------

@test "T71 enable rejects path with traversal" {
    run "$PLUGIN_SH" enable "../../etc"
    [ "$status" -ne 0 ]
}

@test "T72 enable list shows newly enabled plugin" {
    local src
    src="$(make_plugin_source "demo" "alpha.md")"
    "$PLUGIN_SH" enable "$src"
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo"* ]]
    [[ "$output" == *"datarim-core"* ]]
}

# --- Phase B: overrides mechanism --------------------------------------------

# Build a plugin whose plugin.yaml declares overrides on selected skill names.
# Usage: make_plugin_with_overrides <id> <override-name>... -- <regular-name>...
make_plugin_with_overrides() {
    local id="$1"; shift
    local dir="$TMPROOT/sources/$id"
    mkdir -p "$dir/skills"
    local overrides=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        overrides+=("$1"); shift
    done
    [ "${1:-}" = "--" ] && shift
    local regular=("$@")
    {
        echo "schema_version: 1"
        echo "id: $id"
        echo "title: $id"
        echo "version: 0.0.1"
        echo "author: x"
        echo "license: MIT"
        echo "description: x"
        echo "categories:"
        echo "  - skills"
        if [ ${#overrides[@]} -gt 0 ]; then
            echo "overrides:"
            local n
            for n in "${overrides[@]}"; do echo "  - $n"; done
        fi
    } > "$dir/plugin.yaml"
    local n
    for n in "${overrides[@]}"; do echo "# override $n" > "$dir/skills/${n}.md"; done
    for n in "${regular[@]}"; do echo "# regular $n" > "$dir/skills/${n}.md"; done
    echo "$dir"
}

@test "T80 enable with override installs file at root position (not namespaced)" {
    local src
    src="$(make_plugin_with_overrides "myplug" "foo" -- "bar")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    # Override target: root position wins via local overlay precedence.
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/foo.md" ]
    # Non-override: namespaced subdir.
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/myplug/bar.md" ]
    # Override basename should NOT exist under namespaced subdir.
    [ ! -e "$DR_PLUGIN_RUNTIME_ROOT/skills/myplug/foo.md" ]
}

@test "T81 enable with critical-core override emits warning to stderr" {
    local src
    src="$(make_plugin_with_overrides "evilplug" "evolution" -- "harmless")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]]
    [[ "$output" == *"evolution"* ]]
}

@test "T82 enable with non-critical override is silent (no warning)" {
    local src
    src="$(make_plugin_with_overrides "innocent" "harmless" -- "another")"
    run "$PLUGIN_SH" enable "$src"
    [ "$status" -eq 0 ]
    ! [[ "$output" == *"WARNING"* ]]
    ! [[ "$output" == *"warning"* ]]
}

@test "T83 disable removes override symlink from root position" {
    local src
    src="$(make_plugin_with_overrides "myplug" "foo" -- "bar")"
    "$PLUGIN_SH" enable "$src"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/foo.md" ]
    run "$PLUGIN_SH" disable myplug
    [ "$status" -eq 0 ]
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/foo.md" ]
    [ ! -d "$DR_PLUGIN_RUNTIME_ROOT/skills/myplug" ]
}

@test "T84 multi-override conflict: second plugin overriding same target → fail" {
    local s1 s2
    s1="$(make_plugin_with_overrides "first" "shared" --)"
    s2="$(make_plugin_with_overrides "second" "shared" --)"
    "$PLUGIN_SH" enable "$s1"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/shared.md" ]
    run "$PLUGIN_SH" enable "$s2"
    [ "$status" -ne 0 ]
    [[ "$output" == *"shared"* ]] || [[ "$output" == *"override"* ]] || [[ "$output" == *"conflict"* ]]
}

@test "T85 enable rejects override that is not shipped by the plugin" {
    local dir="$TMPROOT/sources/badoverride"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: badoverride
title: Bad Override
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
overrides:
  - missing
EOF
    echo "# something else" > "$dir/skills/something.md"
    run "$PLUGIN_SH" enable "$dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing"* ]] || [[ "$output" == *"override"* ]]
}

@test "T86 manifest records overrides field for re-disable correctness" {
    local src
    src="$(make_plugin_with_overrides "myplug" "foo" "qux" -- "bar")"
    "$PLUGIN_SH" enable "$src"
    grep -q "overrides:" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "    - foo" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "    - qux" "$TMPROOT/datarim/enabled-plugins.md"
}

# --- TUNE-0101 Phase C: snapshot/rollback + sync ----------------------------

@test "T100 snapshot_create writes tarball and rotates within cap" {
    export DR_PLUGIN_SNAPSHOT_MAX=3
    local manifest="$TMPROOT/datarim/enabled-plugins.md"
    mkdir -p "$TMPROOT/datarim"
    echo "# manifest" > "$manifest"
    local snap1 snap2 snap3 snap4
    snap1="$(snapshot_create "$TMPROOT" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest")"
    [ -f "$snap1" ]
    sleep 1
    snap2="$(snapshot_create "$TMPROOT" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest")"
    sleep 1
    snap3="$(snapshot_create "$TMPROOT" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest")"
    sleep 1
    snap4="$(snapshot_create "$TMPROOT" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest")"
    [ -f "$snap4" ]
    [ ! -f "$snap1" ]   # FIFO rotated oldest
    local count
    count="$(find "$(snapshot_dir "$TMPROOT")" -name '*.tar.gz' -type f | wc -l | tr -d ' ')"
    [ "$count" = "3" ]
}

@test "T101 restore_from_snapshot reverts manifest + runtime to captured state" {
    local manifest="$TMPROOT/datarim/enabled-plugins.md"
    mkdir -p "$TMPROOT/datarim"
    echo "# pre-state" > "$manifest"
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT/skills"
    ln -sfn "$TMPROOT/imaginary" "$DR_PLUGIN_RUNTIME_ROOT/skills/pre.md"
    local snap
    snap="$(snapshot_create "$TMPROOT" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest")"

    # Mutate state.
    echo "# post-state mess" > "$manifest"
    rm -f "$DR_PLUGIN_RUNTIME_ROOT/skills/pre.md"
    ln -sfn "$TMPROOT/other" "$DR_PLUGIN_RUNTIME_ROOT/skills/post.md"

    restore_from_snapshot "$snap" "$DR_PLUGIN_RUNTIME_ROOT" "$manifest"

    grep -q "pre-state" "$manifest"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/pre.md" ]
    [ ! -e "$DR_PLUGIN_RUNTIME_ROOT/skills/post.md" ]
}

@test "T102 enable rolls back when fault injected after symlinks" {
    local src
    src="$(make_plugin_source "rbplug" "foo.md")"
    DR_PLUGIN_FAULT_INJECT=after_symlinks run "$PLUGIN_SH" enable "$src"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fault injected"* ]] || [[ "$output" == *"restored"* ]]
    # Symlinks must be gone after restore.
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/rbplug/foo.md" ]
    [ ! -d "$DR_PLUGIN_RUNTIME_ROOT/skills/rbplug" ]
    # Manifest must not contain the rbplug entry.
    if [ -f "$TMPROOT/datarim/enabled-plugins.md" ]; then
        ! grep -q "^- id: rbplug$" "$TMPROOT/datarim/enabled-plugins.md"
    fi
}

@test "T103 enable rolls back when fault injected after manifest" {
    local src
    src="$(make_plugin_source "rbplug2" "foo.md")"
    DR_PLUGIN_FAULT_INJECT=after_manifest run "$PLUGIN_SH" enable "$src"
    [ "$status" -ne 0 ]
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/rbplug2/foo.md" ]
    if [ -f "$TMPROOT/datarim/enabled-plugins.md" ]; then
        ! grep -q "^- id: rbplug2$" "$TMPROOT/datarim/enabled-plugins.md"
    fi
}

@test "T104 sync removes orphan root-position symlink" {
    local src
    src="$(make_plugin_source "syncplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    # Inject orphan: dangling symlink not in any plugin's inventory.
    ln -sfn "$TMPROOT/nowhere" "$DR_PLUGIN_RUNTIME_ROOT/skills/orphan.md"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/orphan.md" ]
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/orphan.md" ]
    # Legitimate plugin symlink must remain.
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/syncplug/foo.md" ]
}

@test "T105 sync removes orphan namespaced subdir for unknown plugin" {
    local src
    src="$(make_plugin_source "knownplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT/skills/ghost-id"
    ln -sfn "$TMPROOT/nope" "$DR_PLUGIN_RUNTIME_ROOT/skills/ghost-id/leftover.md"
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [ ! -d "$DR_PLUGIN_RUNTIME_ROOT/skills/ghost-id" ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/knownplug/foo.md" ]
}

@test "T106 sync recreates broken symlink (target deleted)" {
    local src
    src="$(make_plugin_source "brokplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/brokplug/foo.md" ]
    rm -f "$DR_PLUGIN_RUNTIME_ROOT/skills/brokplug/foo.md"
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/brokplug/foo.md" ]
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/brokplug/foo.md" ]
    # Target must point at the source file.
    local lk
    lk="$(readlink "$DR_PLUGIN_RUNTIME_ROOT/skills/brokplug/foo.md")"
    [[ "$lk" == "$src/skills/foo.md" ]]
}

@test "T107 sync output reports counts" {
    local src
    src="$(make_plugin_source "countplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    ln -sfn "$TMPROOT/nowhere" "$DR_PLUGIN_RUNTIME_ROOT/skills/junk.md"
    rm -f "$DR_PLUGIN_RUNTIME_ROOT/skills/countplug/foo.md"
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed=1"* ]]
    [[ "$output" == *"recreated=1"* ]]
}

@test "T108 sync is idempotent on a clean tree" {
    local src
    src="$(make_plugin_source "cleanplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    "$PLUGIN_SH" sync >/dev/null
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed=0"* ]]
    [[ "$output" == *"recreated=0"* ]]
}

@test "T109 sync restores disabled-orphan backup file" {
    local src
    src="$(make_plugin_source "anchorplug" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    # Synthesise a `*.<id>.disabled` backup left behind by a vanished plugin.
    echo "stale content" > "$DR_PLUGIN_RUNTIME_ROOT/skills/zoo.md.gone-id.disabled"
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    [ -f "$DR_PLUGIN_RUNTIME_ROOT/skills/zoo.md" ]
    [ ! -e "$DR_PLUGIN_RUNTIME_ROOT/skills/zoo.md.gone-id.disabled" ]
}

# --- T120-T139: Phase D — dr-plugin doctor (8 checks + skill-registry) ------

@test "T120 doctor on bootstrapped clean tree exits 0" {
    "$PLUGIN_SH" list >/dev/null
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]] || [[ "$output" == *"9/9"* ]]
}

@test "T121 doctor detects missing required field (manifest-syntax)" {
    "$PLUGIN_SH" list >/dev/null
    # Append a malformed entry: no version/enabled_at.
    cat >> "$TMPROOT/datarim/enabled-plugins.md" <<EOF

- id: broken
  source: /tmp/nowhere
EOF
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing field"* ]] || [[ "$output" == *"version"* ]]
}

@test "T122 doctor detects invalid id in manifest" {
    "$PLUGIN_SH" list >/dev/null
    cat >> "$TMPROOT/datarim/enabled-plugins.md" <<EOF

- id: BadID
  source: /tmp/x
  version: 0.0.1
  enabled_at: 2026-05-06T00:00:00Z
EOF
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid id"* ]]
}

@test "T123 doctor detects inventory-consistency (missing symlink)" {
    local src
    src="$(make_plugin_source "incon" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    rm -rf "$DR_PLUGIN_RUNTIME_ROOT/skills/incon"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing symlink"* ]]
}

@test "T124 doctor detects broken-symlinks" {
    local src
    src="$(make_plugin_source "brok" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    # Replace target with broken symlink (ln to nonexistent).
    rm -f "$DR_PLUGIN_RUNTIME_ROOT/skills/brok/foo.md"
    ln -sfn "$TMPROOT/nope" "$DR_PLUGIN_RUNTIME_ROOT/skills/brok/foo.md"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"broken symlink"* ]]
}

@test "T125 doctor detects orphan-files (warning only, exit 1)" {
    local src
    src="$(make_plugin_source "clean" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    ln -sfn "$TMPROOT/nowhere" "$DR_PLUGIN_RUNTIME_ROOT/skills/orphan.md"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"orphan"* ]]
}

@test "T126 doctor --fix runs sync to repair orphan + broken" {
    local src
    src="$(make_plugin_source "fixme" "foo.md")"
    "$PLUGIN_SH" enable "$src"
    ln -sfn "$TMPROOT/nowhere" "$DR_PLUGIN_RUNTIME_ROOT/skills/junk.md"
    rm -f "$DR_PLUGIN_RUNTIME_ROOT/skills/fixme/foo.md"
    run "$PLUGIN_SH" doctor --fix
    # After fix, re-run doctor → orphan/broken errors gone (exit ≠ 2).
    # skill-registry may still warn for stub skills without frontmatter
    # (intentional: proves Check 9 is wired and exit=1 is "warnings only").
    run "$PLUGIN_SH" doctor
    [ "$status" -ne 2 ]
    [ ! -L "$DR_PLUGIN_RUNTIME_ROOT/skills/junk.md" ]
    [ -L "$DR_PLUGIN_RUNTIME_ROOT/skills/fixme/foo.md" ]
}

@test "T127 doctor detects override declared but not in inventory" {
    local dir="$TMPROOT/sources/badovr"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: badovr
title: x
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    echo "x" > "$dir/skills/real.md"
    "$PLUGIN_SH" enable "$dir"
    # Manually inject overrides field into manifest entry referring to
    # a basename that's not in file_inventory.
    python3 - <<'PY'
import pathlib
m = pathlib.Path("$TMPROOT/datarim/enabled-plugins.md".replace("$TMPROOT", "${TMPROOT}"))
PY
    # Simpler: append override line via awk-rewrite.
    awk '
        /^- id: badovr$/ { in_b=1; print; next }
        in_b && /^[[:space:]]+file_inventory:/ {
            print "  overrides:"
            print "    - phantom.md"
            print
            in_b=0
            next
        }
        { print }
    ' "$TMPROOT/datarim/enabled-plugins.md" > "$TMPROOT/m.tmp"
    mv "$TMPROOT/m.tmp" "$TMPROOT/datarim/enabled-plugins.md"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"override"* ]]
    [[ "$output" == *"phantom.md"* ]]
}

@test "T128 doctor detects dangling dependency" {
    local src
    src="$(make_plugin_source "depok" "a.md")"
    "$PLUGIN_SH" enable "$src"
    # Inject a depends_on referencing a non-active plugin.
    awk '
        /^- id: depok$/ { in_b=1; print; next }
        in_b && /^[[:space:]]+enabled_at:/ {
            print
            print "  depends_on:"
            print "    - ghost-dep"
            in_b=0
            next
        }
        { print }
    ' "$TMPROOT/datarim/enabled-plugins.md" > "$TMPROOT/m.tmp"
    mv "$TMPROOT/m.tmp" "$TMPROOT/datarim/enabled-plugins.md"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"dangling"* ]]
    [[ "$output" == *"ghost-dep"* ]]
}

@test "T129 doctor detects dependency cycle" {
    local s1 s2
    s1="$(make_plugin_source "cyca" "a.md")"
    s2="$(make_plugin_source "cycb" "b.md")"
    "$PLUGIN_SH" enable "$s1"
    "$PLUGIN_SH" enable "$s2"
    # Inject a→b and b→a cycle.
    awk '
        /^- id: cyca$/ { print; getline; print; getline; print; getline; print; print "  depends_on:"; print "    - cycb"; next }
        /^- id: cycb$/ { print; getline; print; getline; print; getline; print; print "  depends_on:"; print "    - cyca"; next }
        { print }
    ' "$TMPROOT/datarim/enabled-plugins.md" > "$TMPROOT/m.tmp"
    mv "$TMPROOT/m.tmp" "$TMPROOT/datarim/enabled-plugins.md"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 2 ]
    [[ "$output" == *"cycle"* ]]
}

@test "T130 doctor snapshot-cleanup warns on >30d-old snapshots" {
    "$PLUGIN_SH" list >/dev/null
    local snap_d="$TMPROOT/datarim/plugin-storage/.snapshots"
    mkdir -p "$snap_d"
    : > "$snap_d/old.tar.gz"
    # Backdate 40 days via touch -t (date 40 days ago).
    local old_date
    if date -v -40d +"%Y%m%d%H%M" >/dev/null 2>&1; then
        old_date="$(date -v -40d +"%Y%m%d%H%M")"
    else
        old_date="$(date -d '40 days ago' +"%Y%m%d%H%M")"
    fi
    touch -t "$old_date" "$snap_d/old.tar.gz"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"snapshots older than"* ]]
}

@test "T131 doctor --fix purges old snapshots" {
    "$PLUGIN_SH" list >/dev/null
    local snap_d="$TMPROOT/datarim/plugin-storage/.snapshots"
    mkdir -p "$snap_d"
    : > "$snap_d/old.tar.gz"
    local old_date
    if date -v -40d +"%Y%m%d%H%M" >/dev/null 2>&1; then
        old_date="$(date -v -40d +"%Y%m%d%H%M")"
    else
        old_date="$(date -d '40 days ago' +"%Y%m%d%H%M")"
    fi
    touch -t "$old_date" "$snap_d/old.tar.gz"
    run "$PLUGIN_SH" doctor --fix
    [ ! -f "$snap_d/old.tar.gz" ]
}

@test "T132 doctor skill-registry detects missing frontmatter name" {
    local dir="$TMPROOT/sources/regplug"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: regplug
title: x
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    # Ship a skill file WITHOUT YAML frontmatter — Skill tool can't resolve.
    echo "# just a markdown body, no frontmatter" > "$dir/skills/no-frontmatter.md"
    "$PLUGIN_SH" enable "$dir"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter"* ]]
}

@test "T133 doctor skill-registry detects name/basename mismatch" {
    local dir="$TMPROOT/sources/regplug2"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: regplug2
title: x
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    cat > "$dir/skills/wrongname.md" <<EOF
---
name: rightname
description: test skill
---

# Body
EOF
    "$PLUGIN_SH" enable "$dir"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"mismatch"* ]] || [[ "$output" == *"frontmatter"* ]]
}

@test "T134 doctor skill-registry passes for properly-formed skill" {
    local dir="$TMPROOT/sources/regplug3"
    mkdir -p "$dir/skills"
    cat > "$dir/plugin.yaml" <<EOF
schema_version: 1
id: regplug3
title: x
version: 0.0.1
author: x
license: MIT
description: x
categories:
  - skills
EOF
    cat > "$dir/skills/goodskill.md" <<EOF
---
name: goodskill
description: a well-formed skill
---

# Body
EOF
    "$PLUGIN_SH" enable "$dir"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 0 ]
}

@test "T135 doctor unknown flag returns exit 64" {
    "$PLUGIN_SH" list >/dev/null
    run "$PLUGIN_SH" doctor --bogus
    [ "$status" -eq 64 ]
}

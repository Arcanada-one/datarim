#!/usr/bin/env bats
PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
LIB_SH="$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh"

setup() {
  TMPROOT="$(mktemp -d)"
  TMPROOT="$(cd "$TMPROOT" && pwd -P)"
  mkdir -p "$TMPROOT/datarim" "$TMPROOT/.datarim-runtime/local" "$TMPROOT/plugin/skills/demo-skill"
  printf '# Plugin state\n\n## Active\n' > "$TMPROOT/datarim/enabled-plugins.md"
  printf '{"schema":1,"project":"%s"}\n' "$TMPROOT" > "$TMPROOT/.datarim-runtime/installation.json"
  mkdir -p "$TMPROOT/.datarim-runtime/local/"{skills,agents,commands,templates}
  cat > "$TMPROOT/plugin/plugin.yaml" <<'YAML'
schema_version: 1
id: nested-fixture
title: Nested fixture
version: 0.1.0
author: test
license: MIT
description: Synthetic nested bundle test.
categories:
  - skills
YAML
  printf '%s\n' '---' 'name: demo-skill' '---' '# Synthetic skill' > "$TMPROOT/plugin/skills/demo-skill/SKILL.md"
  printf '%s\n' '# Synthetic fragment' > "$TMPROOT/plugin/skills/demo-skill/research.md"
  printf '%s\n' 'preserve me' > "$TMPROOT/datarim/insights.md"
  export DR_PLUGIN_WORKSPACE="$TMPROOT"
  . "$LIB_SH"
}

teardown() { rm -rf "$TMPROOT"; }

make_ct2_legacy_fixture() {
  local shape="$1" root="$2"
  mkdir -p "$root/skills"
  cat > "$root/plugin.yaml" <<'YAML'
schema_version: 1
id: ct2-legacy
title: CT2 legacy identity
version: 0.1.0
author: test
license: MIT
description: Synthetic CT2 compatibility fixture.
categories:
  - skills
YAML
  case "$shape" in
    dotfile)
      printf '%s\n' '# Skipped dotfile' > "$root/skills/.ignored.md"
      ;;
    flat-symlink)
      printf '%s\n' '---' 'name: regular-target' '---' '# Regular target' > "$root/skills/target.md"
      ln -s target.md "$root/skills/legacy-link.md"
      ;;
    undeclared-category)
      mkdir -p "$root/templates"
      printf '%s\n' '---' 'name: active' '---' '# Declared skill' > "$root/skills/active.md"
      printf '%s\n' '# Undeclared template' > "$root/templates/ignored.md"
      ;;
    *) echo "unknown CT2 fixture shape: $shape" >&2; return 2 ;;
  esac
}

setup_ct2_sandbox() {
  local ws="$1" plugin_source="$2"
  mkdir -p "$ws/datarim" "$ws/.datarim-runtime/local/skills" "$ws/.datarim-runtime/local/agents" "$ws/.datarim-runtime/local/commands" "$ws/.datarim-runtime/local/templates"
  printf '# Plugin state\n\n## Active\n' > "$ws/datarim/enabled-plugins.md"
  printf '{"schema":1,"project":"%s"}\n' "$ws" > "$ws/.datarim-runtime/installation.json"
  cp -a "$plugin_source" "$ws/plugin"
}

ct2_installed_identity() {
  python3 - "$1" <<'PY'
from pathlib import Path
import hashlib, sys
root=Path(sys.argv[1])/'.datarim-runtime/local'
rows=[]
for category in ('skills','templates','agents','commands'):
    target=root/category/'ct2-legacy'
    if not target.exists():
        continue
    rows.append((f'D {target.relative_to(root)}',''))
    for path in sorted(target.rglob('*')):
        rel=str(path.relative_to(root))
        if path.is_symlink():
            rows.append((f'L {rel}',hashlib.sha256(path.read_bytes()).hexdigest()))
        elif path.is_dir():
            rows.append((f'D {rel}',''))
        elif path.is_file():
            rows.append((f'F {rel}',hashlib.sha256(path.read_bytes()).hexdigest()))
for path,digest in sorted(rows):
    print(f'{path} {digest}'.rstrip())
PY
}

@test "CT2 base-vs-head identity preserves dotfiles, flat links and undeclared categories" {
  local repo_root baseline baseline_root shape fixture base_ws head_ws base_identity head_identity source
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  baseline="fa5c9c2bfdfe267d9848ffb0ed0efed9f77bbe87"
  baseline_root="$TMPROOT/base-installer"
  mkdir -p "$baseline_root/scripts/lib"
  for source in scripts/dr-plugin.sh scripts/lib/plugin-system.sh scripts/project_scope.py; do
    git -C "$repo_root" show "$baseline:$source" > "$baseline_root/$source"
  done
  chmod +x "$baseline_root/scripts/dr-plugin.sh"

  for shape in dotfile flat-symlink undeclared-category; do
    fixture="$TMPROOT/$shape-plugin"
    base_ws="$TMPROOT/$shape-base"
    head_ws="$TMPROOT/$shape-head"
    make_ct2_legacy_fixture "$shape" "$fixture"
    setup_ct2_sandbox "$base_ws" "$fixture"
    setup_ct2_sandbox "$head_ws" "$fixture"

    run env DR_PLUGIN_WORKSPACE="$base_ws" "$baseline_root/scripts/dr-plugin.sh" enable "$base_ws/plugin"
    [ "$status" -eq 0 ] || { echo "base installer refused CT2 shape '$shape': $output"; return 1; }
    run env DR_PLUGIN_WORKSPACE="$head_ws" "$PLUGIN_SH" enable "$head_ws/plugin"
    [ "$status" -eq 0 ] || { echo "head installer refused CT2 shape '$shape': $output"; return 1; }

    [ "$(manifest_inventory_of "$base_ws/datarim/enabled-plugins.md" ct2-legacy skills)" = "$(manifest_inventory_of "$head_ws/datarim/enabled-plugins.md" ct2-legacy skills)" ] || { echo "skills inventory differs for CT2 shape '$shape'"; return 1; }
    [ "$(manifest_inventory_of "$base_ws/datarim/enabled-plugins.md" ct2-legacy templates)" = "$(manifest_inventory_of "$head_ws/datarim/enabled-plugins.md" ct2-legacy templates)" ] || { echo "templates inventory differs for CT2 shape '$shape'"; return 1; }
    base_identity="$(ct2_installed_identity "$base_ws")"
    head_identity="$(ct2_installed_identity "$head_ws")"
    [ "$base_identity" = "$head_identity" ] || { echo "installed paths or bytes differ for CT2 shape '$shape'"; return 1; }
  done
}

@test "nested bundle inventory installs by bytes and survives disable re-enable" {
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 0 ]
  [ "$(manifest_inventory_of "$TMPROOT/datarim/enabled-plugins.md" nested-fixture skills | LC_ALL=C sort)" = "demo-skill/SKILL.md
demo-skill/research.md" ]
  for rel in demo-skill/SKILL.md demo-skill/research.md; do
    [ "$(sha256sum "$TMPROOT/.datarim-runtime/local/skills/nested-fixture/$rel" | cut -d' ' -f1)" = "$(sha256sum "$TMPROOT/plugin/skills/$rel" | cut -d' ' -f1)" ]
  done
  run "$PLUGIN_SH" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed=0"* ]]
  run "$PLUGIN_SH" doctor
  [ "$status" -eq 0 ]
  run "$PLUGIN_SH" disable nested-fixture
  [ "$status" -eq 0 ]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
  [ "$(cat "$TMPROOT/datarim/insights.md")" = "preserve me" ]
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 0 ]
  for rel in demo-skill/SKILL.md demo-skill/research.md; do
    [ "$(sha256sum "$TMPROOT/.datarim-runtime/local/skills/nested-fixture/$rel" | cut -d' ' -f1)" = "$(sha256sum "$TMPROOT/plugin/skills/$rel" | cut -d' ' -f1)" ]
  done
}

@test "uncollected nested template directory is refused before installation" {
  printf '%s\n' '  - templates' >> "$TMPROOT/plugin/plugin.yaml"
  mkdir -p "$TMPROOT/plugin/templates/sub"
  printf '%s\n' '# Unsupported nested template' > "$TMPROOT/plugin/templates/sub/a.md"
  before_manifest="$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_PLUGIN_BUNDLE_INVALID"* ]]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
}

@test "assets in an undeclared category are ignored like the legacy installer" {
  mkdir -p "$TMPROOT/plugin/templates"
  printf '%s\n' '# Unlisted template' > "$TMPROOT/plugin/templates/rogue.md"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 0 ]
  [ -L "$TMPROOT/.datarim-runtime/local/skills/nested-fixture/demo-skill/SKILL.md" ]
  [ ! -e "$TMPROOT/.datarim-runtime/local/templates/nested-fixture/rogue.md" ]
}

@test "dotfiles in declared categories are skipped like the legacy installer" {
  printf '%s\n' '  - templates' >> "$TMPROOT/plugin/plugin.yaml"
  mkdir -p "$TMPROOT/plugin/templates"
  printf '%s\n' '# Hidden template' > "$TMPROOT/plugin/templates/.hidden.md"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 0 ]
  [ -L "$TMPROOT/.datarim-runtime/local/skills/nested-fixture/demo-skill/SKILL.md" ]
  [ -z "$(manifest_inventory_of "$TMPROOT/datarim/enabled-plugins.md" nested-fixture templates)" ]
  [ ! -e "$TMPROOT/.datarim-runtime/local/templates/nested-fixture/.hidden.md" ]
}

@test "dangling root skill symlink is refused instead of omitted from inventory" {
  ln -s "$TMPROOT/missing.md" "$TMPROOT/plugin/skills/orphan.md"
  before_manifest="$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_PLUGIN_BUNDLE_INVALID"* ]]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
}

@test "nested bundle install rolls back after manifest fault injection" {
  before_runtime="$(find "$TMPROOT/.datarim-runtime/local" -type f -o -type l | sort | sha256sum | cut -d' ' -f1)"
  before_manifest="$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)"
  DR_PLUGIN_FAULT_INJECT=after_symlinks run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 2 ]
  [ "$(find "$TMPROOT/.datarim-runtime/local" -type f -o -type l | sort | sha256sum | cut -d' ' -f1)" = "$before_runtime" ]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
  run env DR_PLUGIN_FAULT_INJECT=after_manifest "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 2 ]
  [ "$(find "$TMPROOT/.datarim-runtime/local" -type f -o -type l | sort | sha256sum | cut -d' ' -f1)" = "$before_runtime" ]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
}

@test "legacy flat skill installs at the established path with matching installed bytes" {
  flat_src="$TMPROOT/flat-plugin"
  mkdir -p "$flat_src/skills" "$flat_src/templates"
  printf '%s\n' '---' 'name: legacy-flat' '---' '# Legacy flat skill' > "$flat_src/skills/legacy-flat.md"
  printf '%s\n' '# Legacy template' > "$flat_src/templates/legacy-template.md"
  cat > "$flat_src/plugin.yaml" <<'YAML'
schema_version: 1
id: legacy-flat
title: Legacy flat
version: 0.1.0
author: test
license: MIT
description: Synthetic legacy flat plugin.
categories:
  - skills
  - templates
YAML
  run "$PLUGIN_SH" enable "$flat_src"
  [ "$status" -eq 0 ]
  [ "$(manifest_inventory_of "$TMPROOT/datarim/enabled-plugins.md" legacy-flat skills)" = "legacy-flat.md" ]
  [ -L "$TMPROOT/.datarim-runtime/local/skills/legacy-flat/legacy-flat.md" ]
  [ -L "$TMPROOT/.datarim-runtime/local/templates/legacy-flat/legacy-template.md" ]
  [ "$(sha256sum "$TMPROOT/.datarim-runtime/local/skills/legacy-flat/legacy-flat.md" | cut -d' ' -f1)" = "$(sha256sum "$flat_src/skills/legacy-flat.md" | cut -d' ' -f1)" ]
  [ "$(sha256sum "$TMPROOT/.datarim-runtime/local/templates/legacy-flat/legacy-template.md" | cut -d' ' -f1)" = "$(sha256sum "$flat_src/templates/legacy-template.md" | cut -d' ' -f1)" ]
}

@test "bundle without SKILL.md refuses enable with a typed error" {
  before_manifest="$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)"
  before_runtime="$(find "$TMPROOT/.datarim-runtime" -maxdepth 2 -type f | sort | sha256sum | cut -d' ' -f1)"
  rm "$TMPROOT/plugin/skills/demo-skill/SKILL.md"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_PLUGIN_BUNDLE_INVALID"* ]]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
  [ "$(find "$TMPROOT/.datarim-runtime" -maxdepth 2 -type f | sort | sha256sum | cut -d' ' -f1)" = "$before_runtime" ]
}

@test "bundle subdirectories are refused as unsafe" {
  mkdir "$TMPROOT/plugin/skills/demo-skill/parts"
  printf '%s\n' '# nested' > "$TMPROOT/plugin/skills/demo-skill/parts/extra.md"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_PLUGIN_BUNDLE_INVALID"* ]]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
}

@test "symlinked bundle assets are refused" {
  printf '%s\n' '# external' > "$TMPROOT/external.md"
  ln -s "$TMPROOT/external.md" "$TMPROOT/plugin/skills/demo-skill/extra.md"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_PLUGIN_BUNDLE_INVALID"* ]]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
}

@test "bundle cannot be declared as an override" {
  printf '%s\n' 'overrides:' '  - demo-skill' >> "$TMPROOT/plugin/plugin.yaml"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bundles cannot be overrides"* ]]
  [ ! -e "$TMPROOT/.datarim-runtime/local/skills/nested-fixture" ]
}

@test "foreign namespace entry blocks enable" {
  mkdir -p "$TMPROOT/.datarim-runtime/local/skills/nested-fixture"
  printf '%s\n' 'foreign' > "$TMPROOT/.datarim-runtime/local/skills/nested-fixture/foreign.md"
  before_manifest="$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)"
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"foreign entry in plugin namespace"* ]]
  [ "$(sha256sum "$TMPROOT/datarim/enabled-plugins.md" | cut -d' ' -f1)" = "$before_manifest" ]
}

@test "manifest inventory rejects traversal in nested entries" {
  run "$PLUGIN_SH" enable "$TMPROOT/plugin"
  [ "$status" -eq 0 ]
  sed -i 's/demo-skill\/SKILL.md/..\/SKILL.md/' "$TMPROOT/datarim/enabled-plugins.md"
  run manifest_validate_entry "$TMPROOT/datarim/enabled-plugins.md" nested-fixture
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe skills inventory path"* ]]
}

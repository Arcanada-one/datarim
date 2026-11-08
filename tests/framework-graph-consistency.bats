#!/usr/bin/env bats
setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
}

make_fixture() {
  FIXTURE="$BATS_TEST_TMPDIR/graph-fixture"
  rm -rf "$FIXTURE"
  cp -a "$ROOT/tests/fixtures/framework-graph-consistency/seed" "$FIXTURE"
  # Git does not track empty directories; CI checkouts omit seed/skills/visual-maps
  # unless a tracked placeholder exists. Create the write target before --write.
  mkdir -p "$FIXTURE/skills/visual-maps"
  cp "$ROOT/dev-tools/framework-graph.py" "$FIXTURE/dev-tools/framework-graph.py"
}

@test "canonical framework graph is current" {
  run python3 "$ROOT/dev-tools/framework-graph.py" --check
  [ "$status" -eq 0 ]
}

@test "command graph exactly matches command files" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_01.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "plugin assets are discovered with unique ownership and conditional reachability" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_02.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "plugin condition fields independently gate profile reachability" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_03.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "profile CLI refuses a projection that violates its requested state" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_04.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "profile off and on checks report their reachable graph states" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_05.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "profile-off preserves all legacy-to-legacy graph edges" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_06.py" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "missing referenced plugin skill fails check" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  sed -i 's#skills/topic/SKILL.md#skills/missing/SKILL.md#' "$FIXTURE/commands/demo.md"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken reference"* ]]
}

@test "hand-copied plugin inventory fails check" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_07.py" "$FIXTURE/dev-tools/framework-graph.yaml"
  [ "$status" -eq 0 ]
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugin inventory is stale or hand-maintained"* ]]
}

@test "new plugin files enter the graph from the manifest category" {
  make_fixture
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  printf '# Added after graph generation\n' >"$FIXTURE/plugins/optional/templates/added.md"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -ne 0 ]
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_08.py" "$FIXTURE/dev-tools/framework-graph.yaml"
  [ "$status" -eq 0 ]
}

@test "Python runtime caches in plugin script directories do not stale the generated graph" {
  make_fixture
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_12.py" "$FIXTURE/plugins/optional/plugin.yaml"
  [ "$status" -eq 0 ]
  mkdir -p "$FIXTURE/plugins/optional/scripts"
  printf '# shipped script\n' >"$FIXTURE/plugins/optional/scripts/entry.py"
  # The real repository already tracks these generated maps before --write.
  : >"$FIXTURE/skills/visual-maps/framework-architecture.md"
  : >"$FIXTURE/skills/visual-maps/command-dependencies.md"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]

  mkdir -p "$FIXTURE/plugins/optional/scripts/__pycache__"
  printf 'synthetic bytecode\n' >"$FIXTURE/plugins/optional/scripts/__pycache__/entry.cpython-312.pyc"
  run python3 "$FIXTURE/dev-tools/framework-graph.py" --check
  [ "$status" -eq 0 ]
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_09.py" "$FIXTURE/dev-tools/framework-graph.yaml"
  [ "$status" -eq 0 ]
}

@test "plugin reference extraction and manifest guards reject invalid inputs" {
  make_fixture
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_10.py" "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "independent write runs produce identical graph and map bytes" {
  run python3 "$ROOT/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  first="$(sha256sum "$ROOT/dev-tools/framework-graph.yaml" "$ROOT/skills/visual-maps/framework-architecture.md" "$ROOT/skills/visual-maps/command-dependencies.md")"
  run python3 "$ROOT/dev-tools/framework-graph.py" --write
  [ "$status" -eq 0 ]
  second="$(sha256sum "$ROOT/dev-tools/framework-graph.yaml" "$ROOT/skills/visual-maps/framework-architecture.md" "$ROOT/skills/visual-maps/command-dependencies.md")"
  [ "$first" = "$second" ]
}

@test "every skill frontmatter block is strict YAML" {
  run python3 "$ROOT/tests/fixtures/framework-graph-consistency/helpers/case_11.py" "$ROOT"
  [ "$status" -eq 0 ]
}

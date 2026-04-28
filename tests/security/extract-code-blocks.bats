#!/usr/bin/env bats
# Self-tests for tests/security/extract-code-blocks.sh
# Origin: TUNE-0045 P2.1 — markdown code-block extractor.
# Contract:
#   - Extract bash/sh/python/python3 fenced blocks.
#   - Skip blocks inside <!-- security:counter-example --> ... <!-- /security:counter-example -->
#   - Skip blocks whose first content line is `# nosec-extract` or `# noshellcheck-extract`
#   - Output: _extracted/<basename>.<n>.<ext> and _extracted/manifest.txt

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  EXTRACTOR="$REPO_ROOT/tests/security/extract-code-blocks.sh"
  FIXTURES="$REPO_ROOT/tests/security/fixtures"
  WORK="$(mktemp -d)"
  cd "$WORK"
}

teardown() {
  rm -rf "$WORK"
}

@test "extractor: good-shell.md produces 1 .sh file" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/good-shell.md"
  [ "$status" -eq 0 ]
  count=$(find "$WORK/_extracted" -name '*.sh' | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "extractor: good-python.md produces 1 .py file" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/good-python.md"
  [ "$status" -eq 0 ]
  count=$(find "$WORK/_extracted" -name '*.py' | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "extractor: counter-example.md skips block inside fence, extracts the safe one" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/counter-example.md"
  [ "$status" -eq 0 ]
  count=$(find "$WORK/_extracted" -name '*.sh' | wc -l | tr -d ' ')
  [ "$count" = "1" ]
  # Verify the extracted content is the safe one, NOT the SSH disable line
  ! grep -rq 'StrictHostKeyChecking=no' "$WORK/_extracted/"
  grep -rq 'echo "ok"' "$WORK/_extracted/"
}

@test "extractor: marker-skip.md skips nosec-extract and noshellcheck-extract markers" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/marker-skip.md"
  [ "$status" -eq 0 ]
  # Only the third block ("extracted normally") should be present
  total=$(find "$WORK/_extracted" -name '*.sh' -o -name '*.py' | wc -l | tr -d ' ')
  [ "$total" = "1" ]
  grep -rq 'extracted normally' "$WORK/_extracted/"
  ! grep -rq 'author requests skip' "$WORK/_extracted/"
  ! grep -rq 'skipped python block' "$WORK/_extracted/"
}

@test "extractor: mixed.md extracts only block-1 and block-4" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/mixed.md"
  [ "$status" -eq 0 ]
  total=$(find "$WORK/_extracted" -name '*.sh' -o -name '*.py' | wc -l | tr -d ' ')
  [ "$total" = "2" ]
  grep -rq 'block-1 extracted' "$WORK/_extracted/"
  grep -rq 'block-4 extracted' "$WORK/_extracted/"
  ! grep -rq 'rm -rf /' "$WORK/_extracted/"
  ! grep -rq 'block-3 has skip marker' "$WORK/_extracted/"
}

@test "extractor: produces manifest.txt listing extracted files" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$FIXTURES/mixed.md"
  [ "$status" -eq 0 ]
  [ -f "$WORK/_extracted/manifest.txt" ]
  lines=$(wc -l < "$WORK/_extracted/manifest.txt" | tr -d ' ')
  [ "$lines" = "2" ]
}

@test "extractor: handles multiple input files" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" \
    "$FIXTURES/good-shell.md" "$FIXTURES/good-python.md"
  [ "$status" -eq 0 ]
  total=$(find "$WORK/_extracted" -type f \( -name '*.sh' -o -name '*.py' \) | wc -l | tr -d ' ')
  [ "$total" = "2" ]
}

@test "extractor: ignores unsupported language blocks (e.g. yaml, json)" {
  cat > "$WORK/yaml-only.md" <<'EOF'
# Yaml fixture

```yaml
key: value
```

```json
{"a":1}
```
EOF
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$WORK/yaml-only.md"
  [ "$status" -eq 0 ]
  # No .sh or .py expected
  total=$(find "$WORK/_extracted" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null | wc -l | tr -d ' ')
  [ "$total" = "0" ]
}

@test "extractor: --help prints usage" {
  run bash "$EXTRACTOR" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'usage'
}

@test "extractor: aborts on missing input file" {
  run bash "$EXTRACTOR" -o "$WORK/_extracted" "$WORK/does-not-exist.md"
  [ "$status" -ne 0 ]
}

#!/usr/bin/env bats

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
}

@test "every dr-* command file appears in docs/commands.md" {
  for cmd in "$REPO"/commands/dr-*.md; do
    name="$(basename "$cmd" .md)"
    run grep -qF "/$name" "$REPO/docs/commands.md"
    [ "$status" -eq 0 ] || { echo "missing in docs/commands.md: /$name"; false; }
  done
}

@test "every dr-* command file is mentioned in CLAUDE.md" {
  for cmd in "$REPO"/commands/dr-*.md; do
    name="$(basename "$cmd" .md)"
    run grep -qF "/$name" "$REPO/CLAUDE.md"
    [ "$status" -eq 0 ] || { echo "missing in CLAUDE.md: /$name"; false; }
  done
}

@test "no obsolete /dr-reflect or /dr-security references in CLAUDE.md" {
  ! grep -qE '/dr-reflect|/dr-security' "$REPO/CLAUDE.md"
}

@test "code/datarim/documentation/ does not exist in framework repo" {
  [ ! -d "$REPO/documentation" ]
}

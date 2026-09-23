#!/usr/bin/env bats
setup() { CHECK="${BATS_TEST_DIRNAME}/../check-code-contracts.sh"; WORK="$BATS_TEST_TMPDIR/cc"; mkdir -p "$WORK/dev-tools"; }
@test "valid directory contracts pass" {
  cat >"$WORK/CONTRACTS" <<'EOT'
@cc [label:test] stable-rule
The invariant remains stable across tasks.
EOT
  run "$CHECK" --root "$WORK" --format json
  [ "$status" -eq 0 ] && [[ "$output" == *'"status": "clean"'* ]]
}
@test "malformed contracts fail closed" {
  cat >"$WORK/CONTRACTS" <<'EOT'
@cc [broken] malformed
This must fail.
EOT
  run "$CHECK" --root "$WORK" --format json
  [ "$status" -eq 1 ] && [[ "$output" == *'"status": "invalid"'* ]]
}
@test "duplicate ids in one scope fail" {
  cat >"$WORK/CONTRACTS" <<'EOT'
@cc duplicate
First.

@cc duplicate
Second.
EOT
  run "$CHECK" --root "$WORK" --format json
  [ "$status" -eq 1 ] && [[ "$output" == *'duplicate contract id'* ]]
}

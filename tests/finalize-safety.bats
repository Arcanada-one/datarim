#!/usr/bin/env bats
TOOL="${BATS_TEST_DIRNAME}/../dev-tools/finalize-safety.py"
setup() {
    ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$ROOT"
    git -C "$ROOT" init -q -b main
    git -C "$ROOT" config user.name Test
    git -C "$ROOT" config user.email test@example.invalid
    printf 'base\n' > "$ROOT/file"
    git -C "$ROOT" add file
    git -C "$ROOT" commit -qm base
    git -C "$ROOT" update-ref refs/remotes/origin/main HEAD
    git -C "$ROOT" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    git -C "$ROOT" switch -qc task
    printf '{"schema":1,"owned":{"paths":[],"branches":["task"]}}\n' > "$BATS_TEST_TMPDIR/ledger.json"
}

@test "unmerged task branch is refused" {
    printf 'change\n' >> "$ROOT/file"
    git -C "$ROOT" add file
    git -C "$ROOT" commit -qm change
    run python3 "$TOOL" branch --ledger "$BATS_TEST_TMPDIR/ledger.json" --repo "$ROOT" --target task
    [ "$status" -eq 2 ]
    [[ "$output" == *'not proven merged'* ]]
    git -C "$ROOT" show-ref --verify refs/heads/task
}

@test "unledgered temporary path is refused" {
    printf 'scratch\n' > "$ROOT/scratch"
    run python3 "$TOOL" path --ledger "$BATS_TEST_TMPDIR/ledger.json" --workspace "$ROOT" --target "$ROOT/scratch"
    [ "$status" -eq 2 ]
    [[ "$output" == *'absent from task-owned ledger'* ]]
    [ -f "$ROOT/scratch" ]
}

@test "unconfigured tracker reports not applied" {
    run python3 "$TOOL" tracker --config "$ROOT/datarim/config/tracker.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "not applied"'* ]]
}

@test "diverged remote task branch is refused even if local branch was merged" {
    printf 'remote change\n' >> "$ROOT/file"
    git -C "$ROOT" add file
    git -C "$ROOT" commit -qm remote
    git -C "$ROOT" update-ref refs/remotes/origin/task HEAD
    git -C "$ROOT" switch -q main
    git -C "$ROOT" branch -f task main
    run python3 "$TOOL" branch --ledger "$BATS_TEST_TMPDIR/ledger.json" --repo "$ROOT" --target task
    [ "$status" -eq 2 ]
    [[ "$output" == *'refs/remotes/origin/task'* ]]
}

@test "ledgered tracked file is still refused for temporary cleanup" {
    python3 - "$BATS_TEST_TMPDIR/ledger.json" "$ROOT/file" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text()); d['owned']['paths']=[sys.argv[2]]; p.write_text(json.dumps(d))
PY
    run python3 "$TOOL" path --ledger "$BATS_TEST_TMPDIR/ledger.json" --workspace "$ROOT" --target "$ROOT/file"
    [ "$status" -eq 2 ]
    [[ "$output" == *'tracked file cleanup refused'* ]]
    [ -f "$ROOT/file" ]
}

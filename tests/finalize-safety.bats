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

@test "add creates a ledger atomically, deduplicates exact values, and keeps mode 0600" {
    ledger="$BATS_TEST_TMPDIR/new/finalize/task.json"
    run python3 "$TOOL" add --ledger "$ledger" --kind branch --value task
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "recorded"'* ]]
    run python3 "$TOOL" add --ledger "$ledger" --kind branch --value task
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "already recorded"'* ]]
    python3 - "$ledger" <<'PY'
import json,os,stat,sys
from pathlib import Path
p=Path(sys.argv[1]); data=json.loads(p.read_text())
assert data['owned']['branches']==['task']
assert set(data['owned'])=={'paths','worktrees','branches','processes','containers'}
assert stat.S_IMODE(os.stat(p).st_mode)==0o600
assert not list(p.parent.glob('.finalize-*'))
PY
}

@test "concurrent add calls retain every entry without partial JSON" {
    ledger="$BATS_TEST_TMPDIR/concurrent/task.json"
    for n in 1 2 3 4 5 6 7 8; do
        python3 "$TOOL" add --ledger "$ledger" --kind container --value "fixture-$n" > /dev/null &
    done
    wait
    python3 - "$ledger" <<'PY'
import json,sys
from pathlib import Path
owned=json.loads(Path(sys.argv[1]).read_text())['owned']
assert set(owned['containers'])=={f'fixture-{n}' for n in range(1,9)}
PY
}

@test "add refuses a symlink ledger and an unsafe owned path" {
    ledger="$BATS_TEST_TMPDIR/unsafe.json"
    printf 'keep\n' > "$BATS_TEST_TMPDIR/foreign"
    ln -s "$BATS_TEST_TMPDIR/foreign" "$ledger"
    run python3 "$TOOL" add --ledger "$ledger" --kind branch --value task
    [ "$status" -eq 2 ]
    [ "$(cat "$BATS_TEST_TMPDIR/foreign")" = keep ]
    ln -s "$ROOT/file" "$ROOT/link"
    run python3 "$TOOL" add --ledger "$BATS_TEST_TMPDIR/safe.json" --kind path --value "$ROOT/link" --workspace "$ROOT"
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/safe.json" ]
    run python3 "$TOOL" add --ledger "$BATS_TEST_TMPDIR/safe.json" --kind path --value / --workspace "$ROOT"
    [ "$status" -eq 2 ]
}

@test "add preserves malformed ledger bytes and refuses an outside workspace path" {
    ledger="$BATS_TEST_TMPDIR/malformed.json"
    printf 'original malformed bytes\n' > "$ledger"
    run python3 "$TOOL" add --ledger "$ledger" --kind branch --value task
    [ "$status" -eq 2 ]
    [ "$(cat "$ledger")" = 'original malformed bytes' ]
    printf 'outside\n' > "$BATS_TEST_TMPDIR/outside"
    run python3 "$TOOL" add --ledger "$BATS_TEST_TMPDIR/other.json" --kind path --value "$BATS_TEST_TMPDIR/outside" --workspace "$ROOT"
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/other.json" ]
}

@test "recorded worktree branch and temp path pass cleanup checks while sibling survives" {
    workspace="$BATS_TEST_TMPDIR/task-space"
    mkdir -p "$workspace/repo"
    git -C "$workspace/repo" init -q -b main
    git -C "$workspace/repo" config user.name Test
    git -C "$workspace/repo" config user.email test@example.invalid
    printf 'base\n' > "$workspace/repo/base"
    git -C "$workspace/repo" add base
    git -C "$workspace/repo" commit -qm base
    git -C "$workspace/repo" update-ref refs/remotes/origin/main HEAD
    git -C "$workspace/repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    git -C "$workspace/repo" worktree add -qb task-owned "$workspace/owned-worktree"
    printf 'scratch\n' > "$workspace/owned-temp"
    printf 'foreign\n' > "$workspace/foreign-sibling"
    ledger="$workspace/ledger.json"
    python3 "$TOOL" add --ledger "$ledger" --kind worktree --value "$workspace/owned-worktree"
    python3 "$TOOL" add --ledger "$ledger" --kind branch --value task-owned
    python3 "$TOOL" add --ledger "$ledger" --kind path --value "$workspace/owned-temp" --workspace "$workspace"
    run python3 "$TOOL" path --ledger "$ledger" --workspace "$workspace" --target "$workspace/foreign-sibling"
    [ "$status" -eq 2 ]
    python3 "$TOOL" worktree --ledger "$ledger" --repo "$workspace/repo" --target "$workspace/owned-worktree"
    git -C "$workspace/repo" worktree remove "$workspace/owned-worktree"
    python3 "$TOOL" branch --ledger "$ledger" --repo "$workspace/repo" --target task-owned
    git -C "$workspace/repo" branch -d task-owned
    python3 "$TOOL" path --ledger "$ledger" --workspace "$workspace" --target "$workspace/owned-temp"
    rm "$workspace/owned-temp"
    [ ! -e "$workspace/owned-worktree" ]
    [ ! -e "$workspace/owned-temp" ]
    [ -f "$workspace/foreign-sibling" ]
}

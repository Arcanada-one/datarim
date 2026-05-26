#!/usr/bin/env bats
# check-dev-tools-path-convention.bats — TUNE-0313 regression for runtime
# markdown dev-tools path convention.
#
# Detector contract: every `dev-tools/<script>.sh|py` reference inside
# commands/*.md, skills/**/*.md, agents/*.md, templates/*.{md,yml,yaml}
# that is an INVOCATION (inside a runnable code fence OR following an
# invocation verb like `invoke`/`run`/`bash`/`Run`) MUST be prefixed with
# `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/...` (or one of the other
# accepted runtime-prefixed forms). Bare-relative invocations resolve
# against the agent's cwd, which is frequently the consumer workspace
# root — invocation then fails closed with a misleading "not found"
# warning (TUNE-0313 root case).
#
# Prose mentions WITHOUT an invocation verb / args remain acceptable:
# "see `dev-tools/foo.sh`" names the script for the reader, not for
# the agent to execute via cwd.
#
# Fenced code blocks with language tag other than bash/sh/shell/console
# are not invocation contexts (e.g. ```yaml, ```diff).

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-dev-tools-path-convention.sh"

setup() {
    TMPROOT="$(mktemp -d -t dr-tune-0313-XXXX)"
    mkdir -p "$TMPROOT/commands" "$TMPROOT/skills" "$TMPROOT/agents" "$TMPROOT/templates"
}

teardown() {
    if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
        rm -rf "$TMPROOT"
    fi
    return 0
}

@test "clean tree returns exit 0 with no output" {
    cat >"$TMPROOT/commands/dr-foo.md" <<'EOF'
# /dr-foo

Run `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-foo.sh" --task ID`.

```bash
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-bar.sh"
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "FAIL on bare-relative invocation inside bash fence" {
    cat >"$TMPROOT/commands/dr-bad.md" <<'EOF'
# /dr-bad

```bash
dev-tools/check-expectations-checklist.sh --verify ID
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dr-bad.md"* ]]
    [[ "$output" == *"dev-tools/check-expectations-checklist.sh"* ]]
}

@test "FAIL on bare-relative invocation following invoke verb" {
    cat >"$TMPROOT/commands/dr-verb.md" <<'EOF'
# /dr-verb

The agent MUST invoke `dev-tools/append-init-task-qa.sh --decided-by operator`.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dev-tools/append-init-task-qa.sh"* ]]
}

@test "PASS on prose mention without invocation verb" {
    cat >"$TMPROOT/commands/dr-prose.md" <<'EOF'
# /dr-prose

See `dev-tools/measure-prospective-rate.sh` for the aggregator contract.
The detector at `dev-tools/check-template-path-convention.sh` runs in CI.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "PASS on runtime-prefixed forms" {
    cat >"$TMPROOT/commands/dr-ok.md" <<'EOF'
# /dr-ok

```bash
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/foo.sh" arg
bash $HOME/.claude/dev-tools/bar.sh arg
python3 "$DATARIM_RUNTIME/dev-tools/baz.py" arg
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "PASS on markdown intra-repo link" {
    cat >"$TMPROOT/commands/dr-link.md" <<'EOF'
# /dr-link

Source: [`dev-tools/check-foo.sh`](../dev-tools/check-foo.sh).
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "PASS inside non-shell fenced block (yaml/diff)" {
    cat >"$TMPROOT/commands/dr-yaml.md" <<'EOF'
# /dr-yaml

```yaml
example_field: dev-tools/some-script.sh
```

```diff
- dev-tools/old.sh
+ dev-tools/new.sh
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "FAIL across multiple files, all reported" {
    cat >"$TMPROOT/commands/dr-a.md" <<'EOF'
```bash
dev-tools/a.sh
```
EOF
    mkdir -p "$TMPROOT/skills/example"
    cat >"$TMPROOT/skills/example/SKILL.md" <<'EOF'
```sh
dev-tools/b.sh
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dr-a.md"* ]]
    [[ "$output" == *"SKILL.md"* ]]
}

@test "templates/*.yml and *.yaml are scanned" {
    cat >"$TMPROOT/templates/example.yml" <<'EOF'
# Validator: dev-tools/check-foo.sh arg1
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"example.yml"* ]]
}

@test "--quiet suppresses output but keeps exit code" {
    cat >"$TMPROOT/commands/dr-bad.md" <<'EOF'
```bash
dev-tools/x.sh arg
```
EOF
    run bash "$SCRIPT" --root "$TMPROOT" --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "--root requires a valid directory" {
    run bash "$SCRIPT" --root /nonexistent/path/should-not-exist
    [ "$status" -eq 2 ]
}

@test "unknown flag exits 2" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "live framework repo passes" {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run bash "$SCRIPT" --root "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

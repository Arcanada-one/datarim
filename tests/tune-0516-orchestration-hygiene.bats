#!/usr/bin/env bats
# Presence contracts for advisory orchestration-hygiene rules.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ROUTING="$REPO_ROOT/skills/datarim-system/backlog-and-routing.md"
    ARCHIVE_RULES="$REPO_ROOT/skills/datarim-system/command-and-archive-rules.md"
    ORCHESTRATE="$REPO_ROOT/commands/dr-orchestrate.md"
    AUTO="$REPO_ROOT/commands/dr-auto.md"
    CLAUDE="$REPO_ROOT/CLAUDE.md"
}

@test "parallel orchestration is the canonical default" {
    grep -q 'Parallel orchestration is the default' "$ROUTING"
    grep -q 'own worktree' "$ROUTING"
    grep -q 'own branch' "$ROUTING"
    grep -q 'same branch' "$ROUTING"
    grep -q 'same target files' "$ROUTING"
}

@test "parallel example is explicitly non-normative and placeholder-only" {
    grep -q 'Example - adapt to your infrastructure (non-normative)' "$ROUTING"
    grep -q 'my-dev-host' "$ROUTING"
    grep -q 'task-id' "$ROUTING"
}

@test "orchestration commands link to the canonical parallel rule" {
    grep -q 'Parallel orchestration is the default' "$ORCHESTRATE"
    grep -q 'Parallel orchestration is the default' "$AUTO"
}

@test "tracked status flips are committed and pushed promptly" {
    grep -q 'Persist status changes immediately' "$ARCHIVE_RULES"
    grep -Eqi 'status flip|flips? a task.*status' "$ARCHIVE_RULES"
    grep -Eqi 'commit.*push|push.*commit' "$ARCHIVE_RULES"
    grep -qi 'tracked operational file' "$ARCHIVE_RULES"
}

@test "status persistence rule does not force WIP code commits" {
    grep -qi 'does not require.*WIP code' "$ARCHIVE_RULES"
}

@test "dr-auto command table documents the per-task marker" {
    run grep -F 'datarim/.auto-mode-active' "$CLAUDE"
    [ "$status" -ne 0 ]
    grep -Fq 'datarim/.auto/<TASK-ID>.mode' "$CLAUDE"
}

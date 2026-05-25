#!/usr/bin/env bats
# check-template-path-convention.bats — TUNE-0267 regression for runtime
# markdown template-path convention (CLAUDE.md § Critical Rules #4).
#
# Detector contract: every template asset reference inside
# commands/*.md, skills/**/*.md, agents/*.md MUST be absolute
# (`$HOME/.claude/templates/...` or `${DATARIM_RUNTIME:-...}/templates/...`).
# Bare `templates/<name>.<ext>` resolves relative to agent cwd and breaks
# LLM-copied invocations in foreign projects.
#
# Markdown intra-repo links of the form `[text](../templates/X)` are excluded —
# renderer-side relative links, not LLM-actionable paths.
# Fenced code blocks (``` ... ```) are excluded — illustrative content.

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-template-path-convention.sh"

setup() {
    TMPROOT="$(mktemp -d -t dr-tune-0267-XXXX)"
    mkdir -p "$TMPROOT/commands" "$TMPROOT/skills" "$TMPROOT/agents"
}

teardown() {
    if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
        rm -rf "$TMPROOT"
    fi
    return 0
}

@test "clean tree returns exit 0 with no output" {
    cat >"$TMPROOT/commands/dr-foo.md" <<'EOF'
# foo
- `$HOME/.claude/templates/task-template.md` — canonical reference.
- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` — env-var form.
- See [`templates/security-deps-upgrade-plan.md`](../templates/security-deps-upgrade-plan.md) for details.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "bare relative ref in prose triggers exit 1 + offence line" {
    cat >"$TMPROOT/commands/dr-bar.md" <<'EOF'
# bar
- `templates/task-template.md` — minimal skeleton.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dr-bar.md:2"* ]]
    [[ "$output" == *"templates/task-template.md"* ]]
}

@test "bare ref inside fenced code block does NOT trigger" {
    cat >"$TMPROOT/skills/example.md" <<'EOF'
# example

```
Target: templates/migration-checklist.md
```

Plain prose after fence.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "markdown link form [\`templates/X\`](../templates/X) does NOT trigger" {
    cat >"$TMPROOT/skills/links.md" <<'EOF'
# links
- [`templates/security-deps-upgrade-plan.md`](../templates/security-deps-upgrade-plan.md) — drop-in.
- [`templates/security-workflow.yml`](../templates/security-workflow.yml) — CI gate.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "non-.md extensions (.yml .sh .template) trigger when bare" {
    cat >"$TMPROOT/skills/exts.md" <<'EOF'
# exts
- `templates/security-workflow.yml` — CI gate.
- `templates/cloudflare-nginx-setup.sh` — install script.
- `templates/plugin.yaml.template` — bootstrap.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"templates/security-workflow.yml"* ]]
    [[ "$output" == *"templates/cloudflare-nginx-setup.sh"* ]]
    [[ "$output" == *"templates/plugin.yaml.template"* ]]
}

@test "subdir form templates/docs-diataxis/... triggers when bare" {
    cat >"$TMPROOT/skills/subdir.md" <<'EOF'
# subdir
- Scaffold at `templates/docs-diataxis/tutorials/README.md`.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"templates/docs-diataxis/tutorials/README.md"* ]]
}

@test "explicit datarim/templates/X (project-local override) does NOT trigger" {
    cat >"$TMPROOT/skills/override.md" <<'EOF'
- Create reflection document using `$HOME/.claude/templates/reflection-template.md` (fallback to `datarim/templates/reflection-template.md` only if project provides a custom template).
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "agents/ subtree is also scanned" {
    cat >"$TMPROOT/agents/foo.md" <<'EOF'
Reference: `templates/foo.md`.
EOF
    run bash "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"agents/foo.md"* ]]
}

@test "--quiet suppresses per-line output but preserves exit code" {
    cat >"$TMPROOT/commands/dr-baz.md" <<'EOF'
- `templates/cta-template.md`
EOF
    run bash "$SCRIPT" --root "$TMPROOT" --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "missing --root falls back to script-dir/.. (smoke only — must not crash)" {
    run bash "$SCRIPT" --quiet
    # Exit 0 or 1 acceptable; exit 2 (usage) is the failure mode under test.
    [ "$status" -ne 2 ]
}

@test "usage error returns exit 2" {
    run bash "$SCRIPT" --bogus-flag
    [ "$status" -eq 2 ]
}

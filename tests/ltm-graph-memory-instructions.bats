#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

memory_consumers() {
    cat <<'EOF'
commands/dr-prd.md
agents/researcher.md
skills/research-workflow/SKILL.md
EOF
}

@test "every canonical graph-memory consumer references the workspace resolver" {
    local file
    while IFS= read -r file; do
        grep -qF 'ltm-graph-memory-state.sh' "$REPO/$file" || {
            echo "missing graph-memory resolver contract: $file" >&2
            return 1
        }
    done < <(memory_consumers)
}

@test "every canonical graph-memory consumer distinguishes enabled and disabled" {
    local file
    while IFS= read -r file; do
        grep -qiF 'enabled' "$REPO/$file" && grep -qiF 'disabled' "$REPO/$file" || {
            echo "missing graph-memory state semantics: $file" >&2
            return 1
        }
    done < <(memory_consumers)
}

@test "research workflow defines the vendor-neutral retrieve and store boundary" {
    grep -qF 'retrieve(query, namespace, limit, context?)' "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'store(content, namespace, source, metadata?)' "$REPO/skills/research-workflow/SKILL.md"
}

@test "disabled contract forbids every memory I/O path" {
    grep -qF 'no discovery, adapter invocation, network call, queue, or retry is authorized' \
        "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'must not attempt graph-memory I/O' "$REPO/commands/dr-prd.md" \
        && grep -qF 'must not perform graph-memory I/O' "$REPO/agents/researcher.md"
}

@test "enabled state is permission rather than adapter availability" {
    grep -qF 'permission, not proof that an adapter is configured' \
        "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'separately configured adapter' "$REPO/commands/dr-prd.md"
}

@test "memory failures and recalled content keep safe semantics" {
    grep -qF 'Retrieval failure is visible and non-fatal' "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'failed store must never be reported as successful' "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'untrusted context' "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'source attribution' "$REPO/skills/research-workflow/SKILL.md"
}

@test "Datarim owns policy while the LTM project owns live integration" {
    grep -qF 'The LTM project owns the engine, transport, authentication, deployment, retries, and vendor schemas.' \
        "$REPO/skills/research-workflow/SKILL.md" \
        && grep -qF 'contains no engine, client, credential, endpoint, or runtime overlay' \
        "$REPO/plugins/ltm-graph-memory/README.md"
}

@test "bundled plugin is metadata-only and default-off" {
    grep -q '^id: ltm-graph-memory$' "$REPO/plugins/ltm-graph-memory/plugin.yaml" \
        && grep -q '^categories:$' "$REPO/plugins/ltm-graph-memory/plugin.yaml" \
        && ! grep -q '^default_enabled:' "$REPO/plugins/ltm-graph-memory/plugin.yaml" \
        && [ ! -d "$REPO/plugins/ltm-graph-memory/skills" ] \
        && [ ! -d "$REPO/plugins/ltm-graph-memory/agents" ] \
        && [ ! -d "$REPO/plugins/ltm-graph-memory/commands" ] \
        && [ ! -d "$REPO/plugins/ltm-graph-memory/templates" ]
}

@test "installer fans out the LTM resolver with the shared plugin library" {
    grep -qF 'scripts/ltm-graph-memory-state.sh' "$REPO/install.sh" \
        && grep -qF 'scripts/lib/plugin-system.sh' "$REPO/install.sh"
}

@test "installer advertises the reserved graph-memory toggle by CLI identity" {
    local target="$BATS_TEST_TMPDIR/claude"

    run env HOME="$BATS_TEST_TMPDIR/home" CLAUDE_DIR="$target" \
        bash "$REPO/install.sh" --with-claude --copy --yes

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"/dr-plugin enable ltm-graph-memory"* ]] || return 1
    [[ "$output" != *"/dr-plugin enable $REPO/plugins/ltm-graph-memory"* ]]
}

@test "plugin command and public framework docs link the LTM how-to" {
    [ -f "$REPO/documentation/how-to/ltm-graph-memory-adapter.md" ] \
        && grep -qF 'ltm-graph-memory-adapter.md' "$REPO/commands/dr-plugin.md" \
        && grep -qF 'ltm-graph-memory-adapter.md' "$REPO/README.md" \
        && grep -qF 'ltm-graph-memory' "$REPO/CLAUDE.md"
}

@test "plugin docs preserve batch and no-live-service boundaries" {
    grep -qF 'does not configure or call an LTM service' \
        "$REPO/documentation/how-to/ltm-graph-memory-adapter.md" \
        && grep -qF 'does not change `VERSION`' \
        "$REPO/documentation/how-to/ltm-graph-memory-adapter.md"
}

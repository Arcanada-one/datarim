#!/usr/bin/env bash
# install-hook.sh — Idempotent pre-commit hook installer (TUNE-0091)
#
# Wires doc-fanout-lint.sh into the developer's local pre-commit hook of
# the workspace repo (~/arcanada or wherever the linter is invoked from).
#
# Idempotent: running twice is a no-op (detects marker line).

set -u

MARKER="# datarim-doc-fanout-lint"
WORKSPACE_REPO="${1:-${ARCANADA_WORKSPACE:-$HOME/arcanada}}"

if [ ! -d "$WORKSPACE_REPO/.git" ]; then
    echo "Error: workspace repo '$WORKSPACE_REPO' has no .git" >&2
    exit 2
fi

HOOK="$WORKSPACE_REPO/.git/hooks/pre-commit"

# Detect existing marker
if [ -f "$HOOK" ] && grep -qF "$MARKER" "$HOOK"; then
    echo "OK: hook already installed at $HOOK"
    exit 0
fi

# Append (preserve existing hook contents if any)
if [ ! -f "$HOOK" ]; then
    printf '#!/usr/bin/env bash\n' > "$HOOK"
    chmod +x "$HOOK"
fi

cat >> "$HOOK" <<'EOF'

# datarim-doc-fanout-lint
if git diff --cached --name-only | grep -qE '^Projects/Datarim/code/datarim/(commands|skills|agents|docs|CLAUDE\.md|README\.md)|^Projects/Websites/datarim\.club/data/'; then
    bash Projects/Datarim/code/datarim/dev-tools/doc-fanout-lint.sh \
         --root "$PWD/Projects/Datarim/code/datarim" \
         --config Projects/Datarim/code/datarim/dev-tools/.doc-fanout.yml \
         --allow-cross-root --strict --compact || {
        echo "doc-fanout-lint failed; bypass with: git commit --no-verify" >&2
        exit 1
    }
fi
EOF

echo "OK: hook installed at $HOOK"
exit 0

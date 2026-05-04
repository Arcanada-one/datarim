---
name: file-relocation-checklist
description: Pre-flight grep checklist for any file relocation (git mv, cross-repo move, rename). Catch dangling references before committing the relocation, not after.
---

# File Relocation Checklist

When a file is moved/renamed/relocated within the framework repo (or cross-repo from framework to workspace), references from unexpected callers — skills, agents, templates, CLAUDE.md, docs, scripts — are easy to miss. The post-hoc safety net (`scripts/check-doc-refs.sh`) catches them after the fact, but the cleanest pattern is to make the relocation atomic with its reference-fixup commit.

## Pre-Flight Recipe

Before staging the `git mv` (or `cp + git rm` cross-repo), grep ALL framework markdown and shell for the old path string:

```bash
OLD=path/to/old/location
grep -rln "$OLD" code/datarim/ | grep -v '.git/'
```

Each hit is a touch-point that MUST be updated in the **same commit** as the relocation itself. Splitting them creates a window where `check-doc-refs.sh` is broken on HEAD.

## Cross-Repo Variant

For framework → workspace (or any cross-repo) relocation:

```bash
OLD=code/datarim/documentation/archive/security/findings-2026-04-28.md
NEW="$HOME/arcanada/documentation/archive/security/findings-2026-04-28.md"

# 1. Inventory references in BOTH source and destination repos
grep -rln "$OLD" code/datarim/ "$HOME/arcanada/" | grep -v '.git/'

# 2. Move the file (preserve git history if same repo; cp + git rm + git add otherwise)
git -C code/datarim rm "$OLD"
cp "$NEW" "$HOME/arcanada/$NEW"  # if not already there
git -C "$HOME/arcanada" add "$NEW"

# 3. Update each reference found in step 1 — same commit per repo
# 4. Embed forensic line in relocated file frontmatter:
#    > Source: code/datarim@<sha> (relocated <date>)
```

## Verification

After relocation + reference updates, before commit:

```bash
bash code/datarim/scripts/check-doc-refs.sh --root code/datarim/
# expect: OK
```

A non-zero exit means a reference was missed. Re-run the grep with the new path to spot what was over-corrected, or with the old path to spot what was under-corrected.

## Why This Matters

Splitting relocation from reference-fixup creates a transient broken-HEAD state. Any CI run, any clone, any agent that reads the docs in that window sees dangling links. Atomicity costs nothing (one extra grep) and removes the failure mode entirely.

## Scope

This checklist applies to:

- `git mv` within a repo (most common — agents/skills/commands/templates moves).
- Cross-repo moves from framework to consumer or workspace.
- Rename operations (treat as relocation: old name → new name).

It does NOT apply to in-place edits, code refactors that don't move files, or content-only changes.

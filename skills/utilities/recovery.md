# Recovering Runtime Files from Compacted Session Context

**When to use:** A runtime file in `$HOME/.claude/` (skill, agent, command, template) has been overwritten or deleted in the current session, and:
- No git history exists for the runtime tree (typical case).
- External backups (Time Machine, APFS snapshots, cloud sync) are unavailable or not configured.
- The lost file was previously **invoked via the Skill tool** or **read via the Read tool** earlier in the same session.

**Why this works:** when the harness loads a skill via the Skill tool, the full skill body is injected into the conversation as a `<system-reminder>` block. When the session is compacted with `/compact`, those blocks survive in the compacted summary as verbatim text. The pre-incident file content is therefore recoverable from the session's system-reminder history even after the filesystem copy is destroyed.

**Recipe:**

1. Search the current conversation's system-reminder blocks for either:
   - `### Skill: <lost-name>` followed by the full body (when skill was invoked), or
   - `Called the Read tool with the following input: {"file_path":"<path-to-lost-file>"}` followed by its Result block (when file was read).
2. Extract the body text verbatim. Strip the surrounding `<system-reminder>...</system-reminder>` wrapping; keep the inner markdown.
3. Validate the extracted content: check frontmatter opens with `---` / closes with `---`, sections are intact, no truncation markers (`... (truncated`).
4. Write back with the Write tool to `$HOME/.claude/{agents,skills,commands,templates}/<name>.md`.
5. Curate runtime → repo via selective `cp`, then `scripts/check-drift.sh` to verify in-sync state.

**Limits:**

- Only recovers files that were loaded **earlier in the same session before the incident**. Files never invoked in the session are not in the context.
- If compaction was itself more aggressive than default, some skill bodies may be summarized rather than verbatim. Check for ellipses or `[summary]` markers before trusting.
- Not a substitute for real backups — this is an emergent, opportunistic recovery path. Set up proper backup for the runtime tree (e.g. APFS snapshots or a git-tracked `~/.claude/`) for durability.

**Source:** TUNE-0011 — `install.sh --force` during TUNE-0003 /dr-archive overwrote 4 runtime files. 2 of them (`commands/dr-do.md`, `commands/dr-qa.md`) were recovered verbatim from system-reminder blocks preserved through /compact. Channel 2 of the Disaster Recovery checklist in `skills/evolution.md`.

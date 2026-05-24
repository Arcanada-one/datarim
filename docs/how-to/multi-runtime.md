# How to use Datarim with both Claude Code and Codex CLI

This guide configures one workstation so that **Claude Code** (`~/.claude/`) and **Codex CLI** (`~/.codex/`) both read the same Datarim source repository. After the steps below, slash commands (`/dr-status`, `/dr-do`, …), agents, skills, templates, dev-tools and the `AGENTS.md` ecosystem-router are visible from either runtime without duplication.

> **Status:** stable on macOS + Linux symlink filesystems. The flow that adds `~/.codex/AGENTS.md → source/AGENTS.md` is the multi-runtime extension introduced in Datarim 2.20.0+. Earlier versions can still install `~/.codex/{agents,skills,...}` but require manual `AGENTS.md` linking.

## Prerequisites

- A working Claude Code install (or skip the Claude line below).
- Codex CLI installed (`codex --version`).
- The Datarim source repo cloned at `~/arcanada/Projects/Datarim/code/datarim` (or any local checkout).
- Coworker binary on `PATH` if you want the cross-runtime delegation profile (see «Optional: Coworker `codex` profile» below).

## Install both runtimes in one command

From the Datarim source repo:

```bash
cd ~/arcanada/Projects/Datarim/code/datarim
./install.sh --with-claude --with-codex
```

This creates two symlink fanouts:

```
~/.claude/{agents,skills,commands,templates,scripts,tests,dev-tools}   → repo
~/.codex/{agents,skills,commands,templates,scripts,tests,dev-tools}    → repo
~/.codex/AGENTS.md                                                     → repo/AGENTS.md
```

`AGENTS.md` is installed **only under `--with-codex`** — Codex CLI reads `~/.codex/AGENTS.md` as its ecosystem-router entry point, while Claude Code reads `~/.claude/CLAUDE.md` (each runtime sees the canonical Datarim CLAUDE.md through its own entry-file convention). The Datarim source ships `AGENTS.md` as a symlink to `CLAUDE.md`, so both runtimes resolve to one canonical file.

If your install topology must avoid symlinks (Windows, FAT, restrictive sandboxes), use `--copy` and the same `--with-codex` flag — the copy path mirrors the AGENTS.md installation step.

## Verify the topology

After install, the directory entries under `~/.codex/` should match `~/.claude/`:

```bash
for d in agents skills commands templates scripts tests dev-tools; do
    diff <(readlink -f "$HOME/.claude/$d") <(readlink -f "$HOME/.codex/$d") \
        && echo "OK  $d" || echo "DIFF $d"
done

readlink -f ~/.codex/AGENTS.md     # → <repo>/CLAUDE.md (through AGENTS.md → CLAUDE.md chain)
head -1 ~/.codex/AGENTS.md         # → "# Datarim — Universal Iterative Workflow Framework"
```

When you launch Codex CLI inside an Arcanada-managed workspace, the slash-command catalogue (`~/.codex/commands/dr-*.md`) is now visible to the runtime exactly like under Claude Code.

```bash
cd ~/arcanada
codex exec --skip-git-repo-check "запусти /dr-status и верни TASK-ID + статус 3 активных задач"
```

The output should cite at least one task from `datarim/tasks.md`. If you see «file not found» on `commands/dr-status.md`, the `~/.codex/commands/` symlink was not created — re-run `./install.sh --with-codex` from the canonical source path.

## Optional: Coworker `codex` profile

If you use `coworker` to delegate bulk I/O to an external LLM, register a `codex` profile so the system prompt is aware of Codex CLI conventions (slash-commands are pipeline commands, not shell input; YAML frontmatter is byte-exact).

Append to `~/.config/coworker/profiles.yaml`:

```yaml
codex:
  description: Codex CLI runtime (Datarim multi-runtime parity with `code` profile)
  system_prompt: |
    You assist a Codex CLI session running over a Datarim-managed workspace.
    [...verbatim from examples/profiles.yaml.example...]
  default_max_tokens_ask: 16384
  default_max_tokens_write: 24000
  recommended_provider: deepseek
```

The canonical block is shipped in `Projects/Coworker/code/coworker/examples/profiles.yaml.example`. After editing, smoke:

```bash
coworker ask --profile codex --provider deepseek \
    --paths /Users/$USER/arcanada/CLAUDE.md \
    --question "Назови 3 prefix-а из Arcanada Task Prefix Registry через запятую."
```

Non-empty answer = profile recognised. The default provider is `deepseek` (≈14× cheaper than Moonshot for bulk delegation); override per call with `--provider`.

## Parallel-session safety

`~/.claude/` and `~/.codex/` resolve to the same Datarim source files. Running Claude Code and Codex CLI side-by-side in `~/arcanada/` is supported with the existing workspace-discipline rules (`git add -p` per task ID, foreign hunks left alone, single `.doctor.lock` per workspace).

Two practical checks before a parallel session:

1. **Stale lockfile** — `ls -la ~/arcanada/datarim/.doctor.lock`. A 0-byte file older than the current session is residue from a crashed pipeline; remove it before starting either runtime.
2. **No mutations from read-only Codex calls** — `git status --porcelain datarim/` should stay empty after `codex exec "ls datarim/"` or similar look-ups; mutations indicate a slash-command was triggered, not a lookup.

The two runtimes do not interlock at the OS level — concurrency safety is enforced by the same `flock` + git-add-p discipline Claude Code already uses.

## Troubleshooting

### `link_scope_tree: refuses to overwrite real directory`

`~/.codex/skills/` (or another scope) already contains a regular directory — typically Codex CLI's bundled `.system/` skills (`imagegen`, `plugin-creator`, `skill-creator`, `openai-docs`, `skill-installer`). Move it aside before re-running install:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
mv ~/.codex/skills "$HOME/.codex/skills.bundled-backup-$ts"
./install.sh --with-codex
```

Restoring the bundled skills under the Datarim symlink topology is tracked as a future Datarim backlog item; the move-aside recipe preserves them losslessly.

### `~/.codex/AGENTS.md` is a regular empty file

Codex CLI pre-creates `~/.codex/AGENTS.md` as a 0-byte placeholder on first launch. Re-run `./install.sh --with-codex` — the patched installer replaces the placeholder with a symlink via `ln -sfn`.

### Coworker `which coworker` returns nothing from a Codex shell sandbox

Codex CLI's sandbox may not inherit `~/.local/bin` from the user's interactive shell rc files. Prepend the path before delegation:

```bash
PATH="$HOME/.local/bin:$PATH" coworker ask --profile codex …
```

For permanent fixes, add the export to a shell init file Codex actually reads (verify with `codex exec "echo $PATH"`).

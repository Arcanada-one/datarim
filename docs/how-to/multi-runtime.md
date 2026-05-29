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

```text
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

When you launch Codex CLI inside an Arcanada-managed workspace, the slash-command catalogue (`~/.codex/commands/dr-*.md`) is reachable on disk through the symlink, **but Codex CLI does not auto-discover slash commands the way Claude Code does** — there is no `/`-prefix popup menu in the REPL.

To invoke a Datarim command under Codex, reference its markdown file by name in your prompt:

```text
cd ~/arcanada
codex exec --skip-git-repo-check \
    "Выполни workflow /dr-status — прочитай commands/dr-status.md и следуй инструкциям, верни TASK-ID + статус 3 активных задач"
```

The output should cite at least one task from `datarim/tasks.md`. If you see «file not found» on `commands/dr-status.md`, the `~/.codex/commands/` symlink was not created — re-run `./install.sh --with-codex` from the canonical source path.

### Why no `/`-popup menu in Codex?

Slash-command auto-complete is a feature of the **host runtime** (Claude Code), not of the Datarim symlinks. Claude Code scans `~/.claude/commands/*.md` and registers each file as a UI command; Codex CLI has no equivalent indexing layer in 0.133.0. The markdown files are still reachable — Codex reads them on demand when you reference them by path or name — but they will not surface in a `/`-typed menu. UI parity for Codex is an upstream concern (Codex CLI feature request), not a Datarim runtime gap. Recommended pattern under Codex: name the command explicitly in the prompt (e.g. «follow `commands/dr-do.md` for TUNE-0123») so the LLM loads the instructions on first turn.

### Why no Datarim skills in the Codex skill-list?

Codex CLI ships its own native skill-discovery mechanism for the bundled `.system/` skills it places under `~/.codex/skills/.system/` (`imagegen`, `plugin-creator`, `skill-creator`, `openai-docs`, `skill-installer`). The same indexing layer that registers those bundled skills does **not** crawl flat `*.md` files at the top of `~/.codex/skills/` — Codex expects each skill to live as `<name>/SKILL.md` with valid YAML frontmatter.

This discovery gap is resolved by `./install.sh --with-codex` (default behaviour as of v2.21.0). See § Codex UX integration below for the topology and verification recipes. Opt-out via `--no-codex-ux` if you need the TUNE-0114 baseline (uniform symlink topology) — useful for CI or debugging.

## Codex UX integration

Default behaviour of `./install.sh --with-codex` is to make Datarim commands, skills, and agents discoverable through Codex CLI's native UI conventions. This is layered on top of the TUNE-0114 multi-runtime baseline and the TUNE-0296 `AGENTS.md` symlink.

### What gets installed

| Artefact | Path | Purpose |
|----------|------|---------|
| SKILL.md wrappers | `~/.codex/skills/<name>/SKILL.md` (one per top-level source skill) | Codex CLI's `<name>/SKILL.md` shape; YAML frontmatter carries `name:` + `description:` extracted from the source file; body links back to `code/datarim/skills/<name>.md`. |
| Restored bundled skills | `~/.codex/skills/.system/{imagegen,plugin-creator,skill-creator,openai-docs,skill-installer}/` | Codex CLI's own pre-shipped skills, restored from the TUNE-0296 backup directory so `~/.codex/rules/default.rules` keeps resolving. |
| AGENTS override | `~/.codex/AGENTS.override.md` | Codex-only manifest with three H2 sections — Available Datarim Commands / Skills / Agents — auto-generated from `code/datarim/{commands,skills,agents}/*.md`. |

The canonical AGENTS.md symlink chain (`~/.codex/AGENTS.md` → source `AGENTS.md` → source `CLAUDE.md`) is untouched by design — the override file is the only place where Codex-specific catalogue text lives, so the shared router stays byte-stable for Claude.

### Topology note: `~/.codex/skills/` becomes a real directory

Under TUNE-0114 baseline `~/.codex/skills/` was a symlink to `code/datarim/skills/`. Under the new UX default it is a **real directory** containing the wrapper subdirs and the restored `.system/`. Other scopes (`agents`, `commands`, `templates`, `scripts`, `tests`, `dev-tools`) remain symlinks to source. The mixed-topology guard in `detect_existing_topology` is aware of this divergence and does not error on re-runs.

To go back to the baseline uniform-symlink topology temporarily:

```bash
rm -rf ~/.codex/skills ~/.codex/AGENTS.override.md
./install.sh --with-codex --no-codex-ux
```

The bundled `.system/` backup at `~/.codex/skills.bundled-backup-TUNE-0296-*/` is preserved across runs — restore is sourced from there each time, so wiping `~/.codex/skills/` and re-running `--with-codex` is safe.

### Verification

```bash
# count wrappers — should match source skill count
find ~/.codex/skills -maxdepth 2 -name SKILL.md -not -path '*.system*' | wc -l

# manifest is Codex-only — AGENTS.md remains byte-stable
shasum -a 256 ~/.codex/AGENTS.md ~/.codex/AGENTS.override.md

# .system/ restored and default.rules path resolves
test -r "$(grep -oE '/[^"]*list-skills\.py' ~/.codex/rules/default.rules | head -1)" && echo OK
```

### When to opt out

Pass `--no-codex-ux` when:

- you are running install.sh under CI and only want the symlink baseline,
- you need to bisect a Codex discovery issue (compare with-UX vs without-UX behaviour),
- you are intentionally testing the TUNE-0114 baseline topology.

The flag composes with all other flags (`--with-codex --no-codex-ux`, `--with-claude --with-codex --no-codex-ux`, `--with-codex --no-codex-ux --dry-run`).

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

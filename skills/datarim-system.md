---
name: datarim-system
description: Core Datarim rules. Load this entry first, then only the fragment needed for paths, storage, numbering, backlog, routing, or archive behavior.
---

# Datarim System Rules

> **Core system rules for Datarim (датарим). Always load this entry first.**
> "Datarim" and "датарим" are the same framework. Recognize both forms in any language context.

## Always-Apply Rules

- All Datarim workflow state lives in `datarim/` at the project root.
- Resolve the correct `datarim/` path before any read/write operation.
- Never create `datarim/` outside `/dr-init`.
- Use task IDs in `{PREFIX}-{NNNN}` format across the whole lifecycle.
- Keep `datarim/` for local workflow state and `documentation/archive/` for committed long-term archives.
- Never create `documentation/tasks/`.
- Use `$HOME/.claude/` or project-relative paths, not absolute machine-specific paths.

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/datarim-system/path-and-storage.md`
  Use for path resolution, core file locations, report storage, and archive/documentation boundaries.
- `skills/datarim-system/task-identity-and-context.md`
  Use for task numbering, active task tracking, prefix rules, and rename policy.
- `skills/datarim-system/model-assignment.md`
  Use for `model` / `effort` frontmatter rules and agent-skill assignment policy.
- `skills/datarim-system/backlog-and-routing.md`
  Use for backlog architecture, complexity levels, date handling, and mode transitions.
- `skills/datarim-system/command-and-archive-rules.md`
  Use for `/dr-` namespace rules, archive area mapping, project setup, and critical invariants.

## Quick Path Resolution Rule

Before writing any file to `datarim/`:

1. Check whether `datarim/` exists in the current working directory.
2. If not, walk up the directory tree until a parent containing `datarim/` is found.
3. If no such directory exists, stop and instruct the user to run `/dr-init`.

## Loading Order (v1.17.0+)

Skills, agents, commands, and templates load from two layers:

1. **Framework layer:** `$HOME/.claude/{skills,agents,commands,templates}/{name}.md`.
   In symlink-mode (default since v1.17.0, TUNE-0033) this resolves to the
   cloned datarim repo. In copy-mode it resolves to local copies.
2. **Local overlay:** `$HOME/.claude/local/{skills,agents,commands,templates}/{name}.md`.
   User-private. Gitignored. Created empty by `install.sh`.

**Conflict resolution:** if a name collides between layer 1 and layer 2, the
local overlay wins. `validate.sh` emits a WARN line per detected override.

**Convention:** prefix local files with a personal namespace
(`local/skills/my-org-style.md`) to avoid accidental overrides of framework
skills you actually wanted to keep tracking upstream.

## Quick Routing Heuristic

- Need file placement or archive destination? Load `path-and-storage.md` or `command-and-archive-rules.md`.
- Need task ID, active task, or backlog lifecycle logic? Load `task-identity-and-context.md` and `backlog-and-routing.md`.
- Need complexity-driven stage routing? Load `backlog-and-routing.md`.
- Need `model` or `effort` guidance for agents/skills? Load `model-assignment.md`.

## Why This Skill Is Split

This skill is always in the hot path, so the entry file stays short and routing-focused. Detailed rules now live in focused supporting fragments to reduce context waste while preserving the full system contract.

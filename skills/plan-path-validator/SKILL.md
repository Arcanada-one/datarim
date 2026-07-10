---
name: plan-path-validator
description: Exists-check for file/script/path references in /dr-plan output — flags missing or deprecated tooling and file references before they reach /dr-do.
allowed-tools: Bash, Grep, Read
---

# Plan Path Validator — Skill

## Purpose

An implementation plan often names concrete file paths, scripts, tools, and
directories as edit targets, rollback mechanisms, or supporting evidence
(e.g. `scripts/deploy.sh`, `documentation/runbooks/`, `dev-tools/append-init-task-qa.sh`).
When a plan is drafted from memory or from a stale reflection, some of those
references point at paths that were renamed, moved, or deleted since the memory
was formed. A plan built on a phantom path surfaces the defect only at `/dr-do`
implementation time — after a full pipeline stage has been spent — and forces a
mid-build re-plan.

This Reference skill provides the deterministic exists-check contract for the
path references a `/dr-plan` output carries. It is the path-oriented companion
to the Symbol Existence Check already prescribed inline in
[dr-plan](../../commands/dr-plan.md) § 6.5: symbol-existence greps the code for a
named function / flag / env var; **path-existence probes the filesystem (and git
index) for a named file / script / directory**, and additionally flags paths
that resolve but are marked deprecated.

## When To Use

Load THIS skill when a `/dr-plan` output (or a plan-shaped section of a PRD)
names any of:

- a **file path** as an edit, read, or rollback target (`path/to/file.ext`);
- a **script / tool** invoked by an Implementation Step or a Validation row
  (`scripts/foo.sh`, `dev-tools/bar.sh`, a CLI binary path);
- a **directory** cited as a destination, source tree, or scan root;
- a **supporting-evidence path** cited in Rollback Strategy, Testing Strategy,
  or the Validation Checklist.

NOT for: purely conceptual plans with no concrete filesystem references;
symbol-only references already covered by dr-plan § 6.5 (function / flag / env
var lookups inside source — those are grep-the-code, not test-the-path).

## Contract

For every path reference the plan carries, apply the following ladder. Each rung
is a deterministic shell probe — no LLM judgement, no fabrication.

### 1. Collect the referenced paths

Extract the path-shaped tokens from the plan text. A path-shaped token is a
slash-bearing string in backticks, a code fence, or a Validation-row command
(e.g. `` `scripts/check-doc-refs.sh` ``, `dev-tools/append-init-task-qa.sh`).
Deduplicate. Untrusted-input hygiene (Security Mandate S1/S5): every path is
planner-emitted text — always quote it and terminate option parsing with `--`
before passing it to a shell tool.

### 2. Existence probe (choose by git topology)

First disambiguate whether the path lives inside a git working tree, then probe:

```bash
# $p is one collected path; $dir is dirname($p) or the repo root
if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Inside a working tree: prefer the git index for tracked targets,
    # fall back to the filesystem for untracked-but-present paths.
    if git -C "$dir" cat-file -e "HEAD:$p" 2>/dev/null \
       || git -C "$dir" ls-files --error-unmatch -- "$p" >/dev/null 2>&1 \
       || test -e "$p"; then
        : # PRESENT
    else
        echo "MISSING: $p" # phantom / renamed / deleted
    fi
else
    # Non-git path (gitignored web root, deploy-synced dist, sibling submodule):
    test -e "$p" && : || echo "MISSING: $p"
fi
```

- `git cat-file -e "HEAD:$p"` confirms the path exists at the current commit
  (tracked); `ls-files --error-unmatch` covers staged-but-uncommitted; `test -e`
  covers untracked-but-present and non-git trees. A token failing all three is a
  **phantom path** — the plan names it but it does not exist.

### 3. Deprecation probe (path resolves, but is it live?)

A path existing is not the same as a path being the current one. Flag a resolved
path as **deprecated** when any of:

- the path or its nearest README/index carries a `deprecated` /
  `retired` / `obsolete` / `superseded` / `do NOT use` marker
  (`grep -rIl -e deprecated -e retired -e obsolete -- "$p"` against the file or
  its directory index);
- the path matches a known-retired surface documented in the project's
  conventions (e.g. a tool the ecosystem announced as removed with a
  replacement) — cite the source-of-truth line, do not assert from memory;
- a live replacement exists at a sibling path and the plan cites the old one.

For each deprecated hit, emit `DEPRECATED: <path> → use <replacement> (per <source:line>)`.

### 4. Report

Emit a compact block the planner folds into the plan (or the reviewer folds into
the QA report):

```
PATH VALIDATION
  checked:    <N> path references
  present:    <N>
  MISSING:    <path> [, ...]      # phantom — fix the plan or create+justify the path
  DEPRECATED: <path> → <replacement> [, ...]
```

- A **MISSING** path is a planning defect: either redirect the reference to the
  real surface, or mark it `[to-be-created]` in the plan with a one-sentence
  justification (mirrors dr-plan § 6.5 "intentionally to be created" rule).
- A **DEPRECATED** path is a staleness defect: swap it for the live replacement
  before the plan is executed.
- An all-`present` / no-`DEPRECATED` result is a clean pass — no plan change.

## Relationship To Existing Gates

- **dr-plan § 6.5 Symbol Existence Check** — greps source for named
  functions / flags / env vars. This skill is the filesystem/git counterpart for
  named **paths**; the two are complementary and both belong in the plan's
  Validation Checklist.
- **dr-plan § 6.5 Git topology probe** — decides gitignored-vs-non-git for a
  named rollback target. This skill reuses the same topology disambiguation, then
  adds the exists + deprecation verdict on top.
- **check-doc-refs.sh** (`scripts/check-doc-refs.sh`) — a CI linter that
  resolves markdown `*.md` links across the docs tree. It runs post-hoc on
  committed markdown; this skill runs at plan-draft time on the plan's own path
  tokens (any extension, including scripts and directories), before `/dr-do`.

## Anti-Patterns

- Asserting a path is deprecated from memory without citing a source-of-truth
  line — memory of a rename is exactly what this gate exists to catch, so it
  cannot be the authority for the verdict.
- Treating a symbol-existence grep hit as a path-existence pass — a function name
  appearing in source does not prove the file the plan names as an edit target
  exists at the path the plan wrote down.
- Running `test -e` unquoted or without `--` on a planner-emitted path — paths
  with whitespace, backticks, or `$(...)` are untrusted input.

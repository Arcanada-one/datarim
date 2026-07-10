---
name: utilities
description: Native shell recipes for common operations. Load this entry first, then only the fragment needed for the specific utility category.
model: inherit
current_aal: 1
target_aal: 2
---

# Native Shell Utilities

> **Usage rule:** Agent picks the appropriate one-liner from this skill instead of depending on external MCP servers. All recipes use tools available on macOS and Linux by default (bash, python3, openssl, jq).

## Fragment Routing

Load only the fragment relevant to the task:

- `datetime.md`
  Use for date/time formatting, epoch conversion, timezone conversion, date arithmetic.
- `system-info.md`
  Use for OS detection, architecture, hostname, and math operations (bc, python3).
- `crypto.md`
  Use for hashing (SHA-256/512, MD5), UUID generation, random strings, password generation.
- `encoding.md`
  Use for Base64 encode/decode and URL encoding/decoding.
- `text-transform.md`
  Use for case conversion (camelCase, snake_case, kebab-case, PascalCase) and slug generation.
- `validation.md`
  Use for validating email, URL, IPv4, UUID formats.
- `json.md`
  Use for JSON pretty-print, minify, validate, and field extraction via jq.
- `yaml.md`
  Use for reading YAML and extracting YAML frontmatter from markdown (frontmatter-only parse).
- `formatting.md`
  Use for byte humanization, number formatting (thousands, currency, percentage), and color conversion (hex/RGB/HSL).
- `datarim-sync.md`
  Use for synchronizing framework files between `$HOME/.claude/` and the Datarim repo.
- `ga4-admin.md`
  Use for Google Analytics 4 Admin API operations (list/create data streams, OAuth setup).
- `ssh-deploy.md`
  Use for running scripts on remote servers via SSH without heredoc corruption (base64 pattern).
- `recovery.md`
  Use for recovering lost runtime files from compacted session context (disaster recovery).
- `keyword-linter.md`
  Use when building a keyword-denylist linter — bash recipe with whole-word grep, escape-hatch markers, whitelist mechanic, bats fixture pattern. Pattern source: stack-agnostic gate.
- `git-diff-parsing.md`
  Use when a shell recipe extracts data from `git diff` / `git diff --cached`. Canonical filter chain (`^[+-]` excluding `+++/---`) for separating real additions/removals from hunk-context noise; covers the markdown-bullet edge case and untracked-file fallback.
- `shell-conventions.md`
  Use when writing or reviewing a shell helper that returns lists, iterates over them, splits on a delimiter, or runs a regex. Canonical IFS / word-splitting / locale rules (newline-separated `printf '%s\n'` returns, `while IFS= read -r` loops, narrow `IFS` scoping, `LC_ALL=C` for regex/sort) for cross-platform (macOS bash 3.2 / Linux) behaviour. Runnable skeleton: `templates/shell-helper-template.sh`.

## Quick Selection Guide

- Need date/time operations? Load `datetime.md`.
- Need hashing, passwords, or random values? Load `crypto.md`.
- Need to encode/decode data? Load `encoding.md`.
- Need text case or slug conversion? Load `text-transform.md`.
- Need input validation? Load `validation.md`.
- Need JSON manipulation? Load `json.md`.
- Need number/color formatting? Load `formatting.md`.
- Need to sync Datarim files? Load `datarim-sync.md`.
- Need GA4 API operations? Load `ga4-admin.md`.
- Need SSH remote execution? Load `ssh-deploy.md`.
- Need to recover a lost runtime file? Load `recovery.md`.
- Writing or reviewing a shell helper (list returns, read loops, regex)? Load `shell-conventions.md`.

## Why This Skill Is Split

This skill contains diverse utility recipes spanning 12 domains. Loading all 500+ lines when an agent needs one date command wastes context tokens. The index entry stays short and routing-focused while preserving the full recipe library in directly addressable fragments.

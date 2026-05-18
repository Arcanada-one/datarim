---
name: utilities
description: Native shell recipes for common operations. Load this entry first, then only the fragment needed for the specific utility category.
model: haiku
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Native Shell Utilities

> **Usage rule:** Agent picks the appropriate one-liner from this skill instead of depending on external MCP servers. All recipes use tools available on macOS and Linux by default (bash, python3, openssl, jq).

## Fragment Routing

Load only the fragment relevant to the task:

- `skills/utilities/datetime.md`
  Use for date/time formatting, epoch conversion, timezone conversion, date arithmetic.
- `skills/utilities/system-info.md`
  Use for OS detection, architecture, hostname, and math operations (bc, python3).
- `skills/utilities/crypto.md`
  Use for hashing (SHA-256/512, MD5), UUID generation, random strings, password generation.
- `skills/utilities/encoding.md`
  Use for Base64 encode/decode and URL encoding/decoding.
- `skills/utilities/text-transform.md`
  Use for case conversion (camelCase, snake_case, kebab-case, PascalCase) and slug generation.
- `skills/utilities/validation.md`
  Use for validating email, URL, IPv4, UUID formats.
- `skills/utilities/json.md`
  Use for JSON pretty-print, minify, validate, and field extraction via jq.
- `skills/utilities/formatting.md`
  Use for byte humanization, number formatting (thousands, currency, percentage), and color conversion (hex/RGB/HSL).
- `skills/utilities/datarim-sync.md`
  Use for synchronizing framework files between `$HOME/.claude/` and the Datarim repo.
- `skills/utilities/ga4-admin.md`
  Use for Google Analytics 4 Admin API operations (list/create data streams, OAuth setup).
- `skills/utilities/ssh-deploy.md`
  Use for running scripts on remote servers via SSH without heredoc corruption (base64 pattern).
- `skills/utilities/recovery.md`
  Use for recovering lost runtime files from compacted session context (disaster recovery).
- `skills/utilities/keyword-linter.md`
  Use when building a keyword-denylist linter — bash recipe with whole-word grep, escape-hatch markers, whitelist mechanic, bats fixture pattern. Pattern source: stack-agnostic gate.
- `skills/utilities/git-diff-parsing.md`
  Use when a shell recipe extracts data from `git diff` / `git diff --cached`. Canonical filter chain (`^[+-]` excluding `+++/---`) for separating real additions/removals from hunk-context noise; covers the markdown-bullet edge case and untracked-file fallback.

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

## Why This Skill Is Split

This skill contains diverse utility recipes spanning 12 domains. Loading all 500+ lines when an agent needs one date command wastes context tokens. The index entry stays short and routing-focused while preserving the full recipe library in directly addressable fragments.

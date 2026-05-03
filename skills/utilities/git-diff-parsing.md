# Parsing `git diff` Output in Shell Scripts

> **Usage:** Load when a shell recipe extracts data from `git diff` / `git diff --cached`. Raw diff output mixes file headers, hunk headers, and context lines with the actual additions/removals — applying a regex over the raw output catches all three.

## The Pitfall

`git diff -- <file>` emits four kinds of lines:

```
diff --git a/foo b/foo        ← repo header (single per file)
--- a/foo                     ← old-file header
+++ b/foo                     ← new-file header
@@ -3,5 +3,6 @@               ← hunk header
 unchanged line               ← context (leading SPACE)
-removed line                 ← removal (leading -)
+added line                   ← addition (leading +)
```

A naive `grep -oE 'PATTERN' <(git diff)` matches inside file headers (`---`/`+++`), inside hunk headers (`@@ ... @@`), and inside surrounding **context lines** (which carry every body token of the file near a hunk). For an index file that lists 20 task IDs in committed body and got one new line appended, the context shows ~3 surrounding body lines on either side of the hunk — your regex sees those 6 body IDs as if they were the change.

## Canonical Filter — Real Additions/Removals Only

```bash
git diff -- "$file" \
  | grep -E '^[+-]' \
  | grep -vE '^(\+\+\+|---)' \
  | grep -oE 'YOUR_REGEX'
```

Two filters in order:

1. `^[+-]` — keep only lines whose first character is `+` or `-` (drops repo/hunk headers, drops context lines).
2. `^(\+\+\+|---)` (negated) — drop the `+++ b/path` and `--- a/path` file headers, which would otherwise pollute matches with parts of file paths.

Apply this **before** any extraction regex. After the two filters, every surviving line is a real addition (`+content`) or removal (`-content`); the leading `+`/`-` does not interfere with field-extraction regexes (e.g., `grep -oE '[A-Z]+-[0-9]{4}'`).

## Caveats

- **Staged + working-tree:** combine both via `printf '%s\n%s\n' "$(git diff)" "$(git diff --cached)"` then pipe through the filter once.
- **Markdown bullets:** an added markdown bullet looks like `+- TASK-ID …`. The earlier filter shape `^[+-][^+-]` (one diff-marker + one non-marker char) rejected this because the second char (`-`) collided with the diff-marker filter, leaving the addition invisible. Use `^[+-]` (single-char anchor) — it accepts `+-` (added bullet) and `--` (removed bullet) correctly.
- **Untracked files:** have no HEAD blob — `git diff -- <file>` emits nothing. Fall back to scanning the file body directly when both `git diff` and `git diff --cached` are empty. Document the fallback path explicitly so callers don't silently skip untracked content.
- **Whitespace-only changes:** `git diff -w` strips them; consider whether your gate cares about whitespace edits.
- **Binary files:** `git diff` emits `Binary files differ`, not a textual diff. Either pre-filter binary paths (`git ls-files --eol -- <file>`) or accept the `Binary files differ` line in your downstream filter (it starts with `B`, so the `^[+-]` filter drops it harmlessly).

## Reference

This recipe is the canonical filter for any consumer that classifies hunks by content (e.g., `pre-archive-check.sh` in this framework). The pattern surfaced three times in framework history before being formalised here.

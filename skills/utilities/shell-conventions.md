# Shell Helper Conventions — IFS, Word-Splitting, Locale

> **Usage:** Load when writing or reviewing a Datarim shell helper that returns lists, iterates over them, splits on a delimiter, or runs a regex. These four conventions keep behaviour identical across macOS (bash 3.2, non-POSIX collation) and Linux (bash 5.x). Runnable skeleton: `templates/shell-helper-template.sh`.

## Why This Exists

Word-splitting bugs from inconsistent `IFS` handling and space-separated return values surfaced as repeat fixes during framework work. The rules below are the canonical fix; the template is the same rules as an executable, shellcheck-clean starting point.

## C1 — Return one value per line with `printf '%s\n'`

A list-returning function MUST emit one element per line; never join with spaces.

```bash
# GOOD — newline-separated, whitespace-in-element safe
list_ids() { printf '%s\n' "item-42" "a b c"; }

# BAD — single space-joined line; the caller's word-splitting mangles "a b c"
list_ids() { echo "item-42 a b c"; }
```

`echo "$a $b $c"` collapses the values into one line; any consumer using `for x in $(list_ids)` re-splits on `IFS` and breaks every element that contains a space. `printf '%s\n'` newline-terminates each argument, so the value round-trips losslessly.

## C2 — Consume with `while IFS= read -r item; do … done < <(cmd)`

```bash
while IFS= read -r item; do
  [ -n "$item" ] || continue
  process "$item"
done < <(list_ids)
```

- `IFS=` (empty, scoped to the `read`) stops trimming of leading/trailing whitespace.
- `-r` stops backslash escape interpretation.
- `< <(cmd)` (process substitution) runs the loop body in the **current** shell, so variables assigned inside survive after the loop. `cmd | while …` runs the body in a subshell and silently discards those assignments — a classic "my counter is always 0" bug.

## C3 — Scope `IFS` narrowly, never globally

Do not set a top-level `IFS=$'\n\t'` and leave it. Set `IFS` on the same line as the single command it applies to (it then reverts automatically), or inside a subshell.

```bash
csv_row='a,b,c'
# IFS=',' applies to THIS read only; global IFS is untouched afterwards
IFS=',' read -r -a fields <<<"$csv_row"
printf '%s\n' "${fields[@]}"
```

A mutated global `IFS` silently changes every later unquoted expansion and `read` in the script.

## C4 — Wrap regex and sort in `LC_ALL=C`

On macOS the default locale makes `[a-z]` match uppercase/accented letters and makes `sort` order case-insensitively. Force byte semantics, scoped to the command:

```bash
file=backlog.md
LC_ALL=C grep -oE '[A-Z]+-[0-9]{4}' "$file" | LC_ALL=C sort
```

Scope it to the individual command, not the whole script, so unrelated user-facing output keeps its locale.

## bash 3.2 Note (macOS system bash)

`mapfile` / `readarray` do not exist on bash 3.2. When bulk-loading a list into an array, feature-detect and fall back to the C2 loop:

```bash
if type mapfile >/dev/null 2>&1; then
  mapfile -t arr < <(list_ids)
else
  while IFS= read -r line; do arr+=("$line"); done < <(list_ids)
fi
```

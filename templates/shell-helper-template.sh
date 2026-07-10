#!/usr/bin/env bash
# shell-helper-template.sh — canonical skeleton for a Datarim shell helper library.
#
# PURPOSE
#   Encodes the framework's IFS / word-splitting / locale conventions so that any
#   helper that returns lists, iterates over them, or runs regex behaves the same
#   on macOS (bash 3.2, non-POSIX collation) and Linux (bash 5.x). These rules
#   surfaced as repeat word-splitting bugs (TUNE-0101 R2/R5) before being
#   formalised here.
#
# WHAT TO FILL IN
#   1. Replace the example functions with your own; keep the return/loop idioms.
#   2. Keep 'set -euo pipefail' unless a documented reason requires relaxing it.
#   3. Replace this header block with a project-specific one.
#
# THE FOUR CONVENTIONS (do not deviate without a signed-off note)
#   C1. List-returning functions emit ONE item per line via 'printf %s\n' —
#       never 'echo "a b c"' (space-joined values re-split on the caller's IFS).
#   C2. Consume lists with 'while IFS= read -r item; do ...; done < <(cmd)' —
#       'IFS=' preserves leading/trailing whitespace, '-r' preserves backslashes.
#   C3. Scope IFS narrowly. Do NOT set a global 'IFS=$'\n\t''; if a single block
#       needs it, set it in a subshell or restore it, with a comment on why.
#   C4. Wrap regex / character-class / sort operations in 'LC_ALL=C' so ranges
#       like '[a-z]' and byte ordering are stable across locales.
#
# USAGE
#   source shell-helper-template.sh   # library — functions, no side effects
set -euo pipefail

# ---------------------------------------------------------------------------
# C1 — list-returning function: one value per line, never space-joined.
# ---------------------------------------------------------------------------
# GOOD: printf '%s\n' terminates every element with a newline, so the caller
# can read it back losslessly regardless of spaces inside an element.
# BAD:  echo "$a $b $c"  ->  a single line; the caller's `for x in $(...)`
#       re-splits on spaces and mangles any element that itself contains a space.
list_task_ids() {
  # Emits e.g. TUNE-0111, one per line. Replace body with real source.
  printf '%s\n' "TUNE-0111" "TUNE-0101" "task with space in name"
}

# ---------------------------------------------------------------------------
# C2/C3 — iterate a list safely: `IFS= read -r`, process-substitution input.
# ---------------------------------------------------------------------------
# `IFS=` (empty, on the read only) stops read from stripping leading/trailing
# whitespace; `-r` stops backslash interpretation. Feeding the loop via
# `< <(cmd)` (process substitution) keeps the loop body in the CURRENT shell,
# so variables set inside survive after the loop — unlike `cmd | while ...`,
# whose body runs in a subshell and loses its assignments.
count_items() {
  local n=0 item
  while IFS= read -r item; do
    [ -n "$item" ] || continue   # skip blank lines defensively
    n=$((n + 1))
    printf 'item: [%s]\n' "$item"
  done < <(list_task_ids)
  printf 'total: %d\n' "$n"
}

# ---------------------------------------------------------------------------
# C3 — narrow IFS scoping when you must split on a specific delimiter.
# ---------------------------------------------------------------------------
# Set IFS on the same line as the command it applies to, or in a subshell —
# never leave a mutated global IFS behind for later code to trip over.
split_csv_row() {
  local row="$1" field
  # IFS=',' applies ONLY to this `read`; the global IFS is untouched.
  local -a fields=()
  IFS=',' read -r -a fields <<<"$row"
  for field in "${fields[@]}"; do
    printf '%s\n' "$field"
  done
}

# ---------------------------------------------------------------------------
# C4 — LC_ALL=C scoping for regex character ranges and byte-stable sort.
# ---------------------------------------------------------------------------
# On macOS the default locale makes '[a-z]' match accented/uppercase letters and
# makes `sort` order case-insensitively. Prefix the single command with LC_ALL=C
# to force byte semantics; scope it to the command, not the whole script.
extract_ids() {
  local file="$1"
  # LC_ALL=C applies only to this grep invocation.
  LC_ALL=C grep -oE '[A-Z]+-[0-9]{4}' "$file"
}

sort_stable() {
  # Byte-ordered, deterministic across machines.
  LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Optional: bulk-consume a list into an array (bash 4+). On bash 3.2 (macOS
# system bash) `mapfile`/`readarray` are absent — fall back to the C2 loop.
# ---------------------------------------------------------------------------
to_array() {
  local -a out=()
  if type mapfile >/dev/null 2>&1; then
    mapfile -t out < <(list_task_ids)
  else
    local line
    while IFS= read -r line; do out+=("$line"); done < <(list_task_ids)
  fi
  printf '%s\n' "${out[@]}"
}

# Executed only when run directly, never when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  count_items
fi

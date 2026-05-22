#!/usr/bin/env bash
# check-template-path-convention.sh — runtime markdown template-path validator (TUNE-0267).
#
# Per CLAUDE.md § Critical Rules #4 ("No absolute paths — Use $HOME/.claude/ or
# project-relative paths only"), every reference to a template asset in runtime
# markdown (commands/*.md, skills/**/*.md, agents/*.md) MUST be absolute, starting
# with `$HOME/.claude/templates/` or `${DATARIM_RUNTIME:-$HOME/.claude}/templates/`.
#
# Why: LLM-agents copy backtick-quoted refs into shell commands
# (e.g. `coworker write --context`); a bare `templates/<name>.<ext>` resolves
# relative to the agent's cwd and breaks the invocation in any project whose cwd
# doesn't carry a sibling `templates/` dir — TUNE-0267 root case.
#
# Exclusions:
#   * markdown intra-repo links: `[text](../templates/X)` / `[`text`](./templates/X)`
#     — renderer-side relative links, not LLM-actionable paths
#   * fenced code blocks (``` ... ```) — illustrative content, separately governed
#
# API:
#   check-template-path-convention.sh [--root <runtime-path>] [--quiet]
#     --root   override scan root (default: script-dir/..)
#     --quiet  suppress per-line offence output (exit code only)
#
# Exit codes:
#   0 — clean
#   1 — offences found (stdout: file:line:matched-text)
#   2 — usage / IO error

set -uo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: check-template-path-convention.sh [--root <runtime-path>] [--quiet]
  --root   scan root (default: script-dir/..)
  --quiet  exit code only, no offence lines
exit codes: 0 clean | 1 offences | 2 usage/IO
USAGE
    exit 2
}

ROOT=""
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || usage
            ROOT="$2"
            shift 2
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "[check-template-path-convention] unknown flag: $1" >&2
            usage
            ;;
    esac
done

if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ ! -d "$ROOT" ]; then
    echo "[check-template-path-convention] root does not exist: $ROOT" >&2
    exit 2
fi

# Collect runtime markdown files. Tolerate missing scope dirs (smaller installs).
files=()
for scope in commands skills agents; do
    scope_dir="$ROOT/$scope"
    [ -d "$scope_dir" ] || continue
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$scope_dir" -type f -name '*.md' 2>/dev/null)
done

if [ "${#files[@]}" -eq 0 ]; then
    exit 0
fi

tmp_out="$(mktemp -t check-tpath.XXXX)"
trap 'rm -f "$tmp_out"' EXIT

for f in "${files[@]}"; do
    # Defensive: skip files outside ROOT (symlink leak guard)
    case "$f" in
        "$ROOT"/*) ;;
        *) continue ;;
    esac
    rel="${f#"$ROOT"/}"

    LC_ALL=C awk -v file="$rel" '
        BEGIN { in_fence = 0 }
        /^[[:space:]]*```/ {
            in_fence = !in_fence
            next
        }
        in_fence { next }

        {
            line = $0

            # Per-line skip: markdown link form with backtick display text +
            # relative href both pointing at templates/. Renderer-side link,
            # not an LLM-actionable path.
            if (match(line, /\[`[^`]*templates\/[^`]*`\]\(\.\.?\/templates\//)) {
                next
            }

            content = line
            line_offset = 0

            while (match(content, /templates\/[a-zA-Z][a-zA-Z0-9._\/-]*[a-zA-Z0-9]/)) {
                match_str = substr(content, RSTART, RLENGTH)
                abs_pos = line_offset + RSTART

                pre_start = abs_pos - 30
                if (pre_start < 1) pre_start = 1
                before = substr(line, pre_start, abs_pos - pre_start)

                ok = 0
                if (before ~ /\$HOME\/\.claude\/$/) {
                    ok = 1
                } else if (before ~ /RUNTIME[^}]*\}\/$/) {
                    ok = 1
                } else if (before ~ /\]\(\.\.?\/$/) {
                    ok = 1
                } else if (before ~ /datarim\/$/) {
                    # explicit project-local override path (intentional semantics
                    # for per-project template overlays; not a bare-relative bug)
                    ok = 1
                }

                if (!ok) {
                    print file ":" NR ":" match_str
                }

                line_offset = abs_pos + RLENGTH - 1
                content = substr(content, RSTART + RLENGTH)
            }
        }
    ' "$f" >>"$tmp_out"
done

if [ -s "$tmp_out" ]; then
    [ "$QUIET" -eq 0 ] && cat "$tmp_out"
    exit 1
fi

exit 0

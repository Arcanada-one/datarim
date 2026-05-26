#!/usr/bin/env bash
# check-dev-tools-path-convention.sh — runtime markdown dev-tools path validator (TUNE-0313).
#
# Sister tool to check-template-path-convention.sh. Catches bare-relative
# `dev-tools/<script>.sh` (or `.py`) references in runtime markdown
# (commands/*.md, skills/**/*.md, agents/*.md, templates/*.md).
#
# Why: when an agent reads /dr-qa.md in another workspace
# (cwd = consumer project, not the framework repo) and follows
# `dev-tools/check-expectations-checklist.sh --verify <ID>`, the shell
# resolves the path against cwd, fails to find dev-tools/, and the
# agent falls back to manual verification. The runtime-prefixed form
# `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/<script>` always
# resolves to the installed symlink.
#
# Exclusions:
#   * fenced code blocks (``` ... ```) — illustrative content, separately governed
#   * markdown intra-repo links: [text](./dev-tools/...) — renderer-side relative
#   * prose mentions WITHOUT an invocation verb / args are out of scope here;
#     this validator targets the bare-relative-invocation pattern (a bare ref
#     followed by space + arg, OR inside a runnable code block). Prose like
#     "see `dev-tools/foo.sh`" is acceptable — it names the script for the
#     reader, not for the agent to execute via cwd.
#
# API:
#   check-dev-tools-path-convention.sh [--root <runtime-path>] [--quiet]
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
usage: check-dev-tools-path-convention.sh [--root <runtime-path>] [--quiet]
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
            echo "[check-dev-tools-path-convention] unknown flag: $1" >&2
            usage
            ;;
    esac
done

if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ ! -d "$ROOT" ]; then
    echo "[check-dev-tools-path-convention] root does not exist: $ROOT" >&2
    exit 2
fi

files=()
for scope in commands skills agents templates; do
    scope_dir="$ROOT/$scope"
    [ -d "$scope_dir" ] || continue
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$scope_dir" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
done

if [ "${#files[@]}" -eq 0 ]; then
    exit 0
fi

tmp_out="$(mktemp -t check-dtpath.XXXX)"
trap 'rm -f "$tmp_out"' EXIT

for f in "${files[@]}"; do
    case "$f" in
        "$ROOT"/*) ;;
        *) continue ;;
    esac
    rel="${f#"$ROOT"/}"

    case "$rel" in
        *.yml|*.yaml) is_yaml=1 ;;
        *) is_yaml=0 ;;
    esac

    LC_ALL=C awk -v file="$rel" -v is_yaml="$is_yaml" '
        BEGIN { in_fence = 0; fence_lang = "" }

        # Fence tracking with language capture
        /^[[:space:]]*```/ {
            if (in_fence == 0) {
                in_fence = 1
                # extract language token after the backticks
                lang_line = $0
                sub(/^[[:space:]]*```/, "", lang_line)
                sub(/[[:space:]].*$/, "", lang_line)
                fence_lang = tolower(lang_line)
            } else {
                in_fence = 0
                fence_lang = ""
            }
            next
        }

        {
            line = $0
            content = line
            line_offset = 0

            # Match bare-relative `dev-tools/<script>.{sh,py}` references.
            while (match(content, /dev-tools\/[a-z][a-z0-9_-]*\.(sh|py)/)) {
                match_str = substr(content, RSTART, RLENGTH)
                abs_pos = line_offset + RSTART

                pre_start = abs_pos - 40
                if (pre_start < 1) pre_start = 1
                before = substr(line, pre_start, abs_pos - pre_start)

                ok = 0
                # Accepted prefixes (any of these immediately before `dev-tools/`):
                if (before ~ /\$HOME\/\.claude\/$/) { ok = 1 }
                else if (before ~ /RUNTIME[^}]*\}\/$/) { ok = 1 }
                else if (before ~ /\$DATARIM_RUNTIME\/$/) { ok = 1 }
                else if (before ~ /code\/datarim\/$/) { ok = 1 }
                else if (before ~ /datarim\/$/) { ok = 1 }
                # Markdown intra-repo link href (renderer-side, not LLM-actionable):
                else if (before ~ /\]\(\.\.?\/$/) { ok = 1 }
                else if (before ~ /\]\(\.\.\/[A-Za-z0-9_-]+\/$/) { ok = 1 }

                # Invocation-context check: is this ACTUALLY an invocation
                # (followed by an arg / inside a runnable fence), or just prose?
                # Prose passes silently (see exclusion §3 in header).
                after_match_pos = abs_pos + RLENGTH
                after = substr(line, after_match_pos, 80)
                is_invocation = 0
                if (in_fence == 1 && (fence_lang == "bash" || fence_lang == "sh" || fence_lang == "shell" || fence_lang == "console" || fence_lang == "")) {
                    is_invocation = 1
                }
                # YAML/YML files: any followed-by-arg ref is invocation (no
                # prose ambiguity — YAML comments are operator-copyable docs).
                if (is_yaml == 1 && after ~ /^[[:space:]]+[^`]/) {
                    is_invocation = 1
                }
                # Followed by a space + non-backtick arg, AND preceded by an invocation verb in the same line
                if (after ~ /^[[:space:]]+[^`]/) {
                    # peek backwards in `line` for invocation verb within 60 chars before the match
                    pre_long_start = abs_pos - 60
                    if (pre_long_start < 1) pre_long_start = 1
                    pre_long = substr(line, pre_long_start, abs_pos - pre_long_start)
                    if (pre_long ~ /(`bash[[:space:]]|`sh[[:space:]]|invoke[[:space:]]+`|invoking[[:space:]]+`|run[[:space:]]+`|runs[[:space:]]+`|running[[:space:]]+`|call[[:space:]]+`|calls[[:space:]]+`|execute[[:space:]]+`|executes[[:space:]]+`|Run[[:space:]]+`|Invoke[[:space:]]+`)/) {
                        is_invocation = 1
                    }
                }

                if (!ok && is_invocation) {
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

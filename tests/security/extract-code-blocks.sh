#!/usr/bin/env bash
# extract-code-blocks.sh — extract bash/python fenced blocks from markdown files
#                          for downstream linting (shellcheck, bandit, semgrep).
#
# Origin: TUNE-0045 P2.1 (Datarim Security Baseline).
# Contract:
#   - Extracts ` ```bash`, ` ```sh`, ` ```python`, ` ```python3` fenced blocks.
#   - Skips blocks inside `<!-- security:counter-example -->` ... `<!-- /security:counter-example -->`.
#   - Skips blocks whose first non-blank content line is `# nosec-extract` or `# noshellcheck-extract`.
#   - Emits `<output-dir>/<source-basename>.<n>.<ext>` and `<output-dir>/manifest.txt`.
#
# Usage:
#   extract-code-blocks.sh -o <output-dir> <markdown-file> [<markdown-file>...]

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: extract-code-blocks.sh -o <output-dir> <markdown-file> [<markdown-file>...]

Extracts bash/sh/python/python3 fenced code blocks from markdown for downstream linting.

Options:
  -o <output-dir>   Where extracted files land. Created if missing.
  -h, --help        Show this help.

Skip rules:
  - Blocks inside <!-- security:counter-example --> ... <!-- /security:counter-example --> are skipped.
  - Blocks whose first content line is `# nosec-extract` or `# noshellcheck-extract` are skipped.

Output:
  <output-dir>/<basename>.<n>.<sh|py>
  <output-dir>/manifest.txt   (one extracted path per line)
EOF
}

OUTPUT_DIR=""
INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o)
      shift
      [[ $# -gt 0 ]] || { echo "extract-code-blocks: -o requires an argument" >&2; exit 2; }
      OUTPUT_DIR="$1"
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do INPUTS+=("$1"); shift; done
      ;;
    -*)
      echo "extract-code-blocks: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      INPUTS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "extract-code-blocks: -o <output-dir> is required" >&2
  usage >&2
  exit 2
fi

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "extract-code-blocks: no input markdown files supplied" >&2
  usage >&2
  exit 2
fi

for f in "${INPUTS[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "extract-code-blocks: input file not found: $f" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"
MANIFEST="$OUTPUT_DIR/manifest.txt"
: > "$MANIFEST"

ext_for_lang() {
  case "$1" in
    bash|sh) echo "sh" ;;
    python|python3|py) echo "py" ;;
    *) echo "" ;;
  esac
}

extract_one() {
  local src="$1"
  local base
  base="$(basename "$src" .md)"

  awk -v src="$src" -v base="$base" -v outdir="$OUTPUT_DIR" -v manifest="$MANIFEST" '
    BEGIN {
      in_counter = 0
      in_block = 0
      block_idx = 0
      first_line_seen = 0
      skip_block = 0
    }

    # Counter-example fence open / close (HTML-comment markers, line-anchored)
    /^[[:space:]]*<!--[[:space:]]*security:counter-example[[:space:]]*-->[[:space:]]*$/ {
      in_counter = 1
      next
    }
    /^[[:space:]]*<!--[[:space:]]*\/security:counter-example[[:space:]]*-->[[:space:]]*$/ {
      in_counter = 0
      next
    }

    # Inside a code block
    in_block == 1 {
      # Closing fence (must be exactly ``` with no language)
      if ($0 ~ /^```[[:space:]]*$/) {
        if (skip_block == 0 && ext != "") {
          out = outdir "/" base "." block_idx "." ext
          for (i = 1; i <= n; i++) print buf[i] > out
          close(out)
          print out >> manifest
        }
        in_block = 0
        skip_block = 0
        first_line_seen = 0
        n = 0
        ext = ""
        next
      }

      # First content line — check for skip markers (only meaningful for shell/python)
      if (first_line_seen == 0 && $0 ~ /[^[:space:]]/) {
        first_line_seen = 1
        if ($0 ~ /^[[:space:]]*#[[:space:]]*nosec-extract[[:space:]]*$/ \
            || $0 ~ /^[[:space:]]*#[[:space:]]*noshellcheck-extract[[:space:]]*$/) {
          skip_block = 1
        }
      }

      n++
      buf[n] = $0
      next
    }

    # Opening fence with a language we recognise
    in_block == 0 && /^```[a-zA-Z0-9_+-]+[[:space:]]*$/ {
      lang = $0
      sub(/^```/, "", lang)
      sub(/[[:space:]]+$/, "", lang)

      if (lang == "bash" || lang == "sh") {
        ext = "sh"
      } else if (lang == "python" || lang == "python3" || lang == "py") {
        ext = "py"
      } else {
        ext = ""
      }

      # Even if extension unknown, we still need to swallow until the closing fence
      # so that the awk state machine does not leak into prose.
      in_block = 1
      block_idx++
      n = 0
      first_line_seen = 0
      skip_block = (in_counter == 1) ? 1 : 0
      next
    }

    { next }
  ' "$src"
}

for f in "${INPUTS[@]}"; do
  extract_one "$f"
done

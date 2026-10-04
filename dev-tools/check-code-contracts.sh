#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMAT="text"
while [ $# -gt 0 ]; do
  case "$1" in --root) ROOT="$2"; shift 2;; --format) FORMAT="$2"; shift 2;; *) echo "usage: check-code-contracts.sh [--root PATH] [--format text|json]" >&2; exit 2;; esac
done
case "$FORMAT" in text) exec python3 "$SCRIPT_DIR/code-contracts-lint.py" "$ROOT";; json) exec python3 "$SCRIPT_DIR/code-contracts-lint.py" "$ROOT" --json;; *) echo "invalid format" >&2; exit 2;; esac

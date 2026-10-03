#!/usr/bin/env bash
# dev-tools/check-cli-audit-schema.sh — validator + purge mode for cli audit log.
# Source: TUNE-0271 plan § Detailed Design 4.2 + AC § V-AC-5, V-AC-20.
#
# Modes:
#   --day YYYY-MM-DD          validate one day's JSONL (10 keys, enums, version)
#   --purge-older-than 90d    delegate purge to cli/lib/audit.sh::audit_purge
#   -h | --help               usage
#
# Environment:
#   DATARIM_CLI_AUDIT_DIR     override audit dir (default <root>/datarim/audit)
#   DATARIM_ROOT              override root (default = walk up from cwd)
#
# Exit codes:
#   0  OK
#   1  validation failure
#   2  usage error

set -eu

usage() {
    cat <<'EOF'
check-cli-audit-schema.sh — validate/purge cli audit JSONL.

Usage:
  check-cli-audit-schema.sh --day YYYY-MM-DD
  check-cli-audit-schema.sh --purge-older-than 90d
EOF
}

mode=""
day=""
purge_arg=""
while [ $# -gt 0 ]; do
    case "$1" in
        --day) mode=day; day="${2:-}"; shift 2 ;;
        --purge-older-than) mode=purge; purge_arg="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf '[check-cli-audit-schema] unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$mode" ]; then
    usage >&2; exit 2
fi

# Locate cli/lib/audit.sh — walk up from this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_LIB="$REPO_ROOT/cli/lib/audit.sh"
if [ ! -f "$AUDIT_LIB" ]; then
    printf '[check-cli-audit-schema] cli/lib/audit.sh not found at %s\n' "$AUDIT_LIB" >&2
    exit 2
fi
# shellcheck source=../cli/lib/audit.sh
. "$AUDIT_LIB"

audit_dir="$(cli_audit_dir)"

case "$mode" in
    day)
        if ! printf '%s' "$day" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            printf '[check-cli-audit-schema] --day expects YYYY-MM-DD\n' >&2
            exit 2
        fi
        target="$audit_dir/cli-audit-$day.jsonl"
        if [ ! -f "$target" ]; then
            printf '[check-cli-audit-schema] no audit file for %s (path: %s)\n' "$day" "$target" >&2
            exit 1
        fi
        python3 - "$target" <<'PY'
import json, sys
REQUIRED = {"schema_version","ts","session_id","calling_agent","subcommand",
            "args_hash","reversibility","outcome","duration_ms","exit_code"}
REV_ENUM = {"reversible","irreversible"}
OUT_ENUM = {"success","abort","error","kill_switched"}
path = sys.argv[1]
errors = 0
with open(path, "r", encoding="utf-8") as f:
    for ln, raw in enumerate(f, start=1):
        raw = raw.rstrip("\n")
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except Exception as e:
            print(f"line {ln}: not valid JSON ({e})", file=sys.stderr)
            errors += 1
            continue
        missing = REQUIRED - set(obj)
        if missing:
            print(f"line {ln}: missing keys: {sorted(missing)}", file=sys.stderr)
            errors += 1
        if obj.get("schema_version") != 1:
            print(f"line {ln}: schema_version != 1", file=sys.stderr)
            errors += 1
        if obj.get("reversibility") not in REV_ENUM:
            print(f"line {ln}: reversibility not in {sorted(REV_ENUM)}", file=sys.stderr)
            errors += 1
        if obj.get("outcome") not in OUT_ENUM:
            print(f"line {ln}: outcome not in {sorted(OUT_ENUM)}", file=sys.stderr)
            errors += 1
        ah = str(obj.get("args_hash", ""))
        if not ah.startswith("sha256:") or len(ah) != len("sha256:") + 64:
            print(f"line {ln}: args_hash bad shape", file=sys.stderr)
            errors += 1
sys.exit(1 if errors else 0)
PY
        ;;
    purge)
        case "$purge_arg" in
            90d) audit_purge ;;
            *) printf '[check-cli-audit-schema] only --purge-older-than 90d supported in Phase 3\n' >&2; exit 2 ;;
        esac
        ;;
esac

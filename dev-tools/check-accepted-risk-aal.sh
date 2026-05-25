#!/usr/bin/env bash
# dev-tools/check-accepted-risk-aal.sh — validator for accepted-risk-aal.yml.
# Source: TUNE-0271 plan § Detailed Design 4.4.
#
# Modes:
#   --task TUNE-NNNN          ensure entry id "tune-NNNN-..." is present + valid
#   --file <path>             override default location
#   --warn-window-days N      pre-expiry stderr warning window (default 7)
#   --check-expiry-only       only check expires >= today (skip other fields)
#   --help
#
# Exit codes:
#   0   OK (entry present, not expired)
#   1   validation failure
#   2   usage error
#   23  entry expired (intentional sentinel — CLI uses this to gate AAL 3)

set -eu

usage() {
    cat <<'EOF'
check-accepted-risk-aal.sh — validate AAL mandate-override register.

Usage:
  check-accepted-risk-aal.sh --task TUNE-NNNN [--file PATH] [--warn-window-days N]
  check-accepted-risk-aal.sh --file PATH (validate schema)
EOF
}

task=""
file=""
warn_days="${DATARIM_AAL_WARN_DAYS:-7}"
check_expiry_only=0

while [ $# -gt 0 ]; do
    case "$1" in
        --task) task="${2:-}"; shift 2 ;;
        --file) file="${2:-}"; shift 2 ;;
        --warn-window-days) warn_days="${2:-}"; shift 2 ;;
        --check-expiry-only) check_expiry_only=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf '[check-aal] unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
file="${file:-$REPO_ROOT/accepted-risk-aal.yml}"

if [ ! -f "$file" ]; then
    printf '[check-aal] file not found: %s\n' "$file" >&2
    exit 1
fi

python3 - "$file" "$task" "$warn_days" "$check_expiry_only" <<'PY'
import sys, datetime
try:
    import yaml
except ImportError:
    print("[check-aal] python3 yaml package required", file=sys.stderr)
    sys.exit(1)

path, task, warn_days, expiry_only = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

errors = 0
if data.get("schema_version") != 1:
    print(f"[check-aal] schema_version != 1 (got {data.get('schema_version')!r})", file=sys.stderr)
    errors += 1

entries = data.get("entries") or []
if not isinstance(entries, list) or not entries:
    print("[check-aal] entries[] missing or empty", file=sys.stderr)
    sys.exit(1)

today = datetime.date.today()

def find_entry(task_id):
    if not task_id:
        return None
    slug_part = task_id.lower()
    for e in entries:
        if (e.get("id") or "").startswith(slug_part):
            return e
    return None

target = find_entry(task) if task else None
if task and not target:
    print(f"[check-aal] no entry matching task {task}", file=sys.stderr)
    sys.exit(1)

# Schema validation pass over ALL entries (cheap; under 10).
REQUIRED = {"id","title","accepted_at","expires","review_required_by","operator",
            "mandate_overridden","mandate_ceiling","declared_level","scope",
            "mitigations","risk_summary","rollback"}
for e in entries:
    missing = REQUIRED - set(e.keys())
    if missing:
        print(f"[check-aal] entry {e.get('id','?')} missing fields: {sorted(missing)}", file=sys.stderr)
        errors += 1
        continue
    try:
        acc = datetime.date.fromisoformat(str(e["accepted_at"]))
        exp = datetime.date.fromisoformat(str(e["expires"]))
        rev = datetime.date.fromisoformat(str(e["review_required_by"]))
    except Exception as exc:
        print(f"[check-aal] entry {e.get('id')} date parse: {exc}", file=sys.stderr)
        errors += 1
        continue
    if rev != exp:
        print(f"[check-aal] entry {e.get('id')} review_required_by != expires", file=sys.stderr)
        errors += 1
    if not isinstance(e.get("scope"), list) or not e["scope"]:
        print(f"[check-aal] entry {e.get('id')} scope must be non-empty list", file=sys.stderr)
        errors += 1
    if not isinstance(e.get("mitigations"), list) or not e["mitigations"]:
        print(f"[check-aal] entry {e.get('id')} mitigations must be non-empty list", file=sys.stderr)
        errors += 1
    if not isinstance(e.get("mandate_ceiling"), int) or not isinstance(e.get("declared_level"), int):
        print(f"[check-aal] entry {e.get('id')} mandate_ceiling/declared_level must be int", file=sys.stderr)
        errors += 1

if errors and not expiry_only:
    sys.exit(1)

# Expiry check for target entry (if given).
if target:
    exp = datetime.date.fromisoformat(str(target["expires"]))
    days_left = (exp - today).days
    if days_left < 0:
        print(f"[check-aal] entry {target['id']} EXPIRED on {exp} ({-days_left}d ago)", file=sys.stderr)
        sys.exit(23)
    if days_left <= warn_days:
        print(f"[warning] accepted-risk-aal entry {target['id']} expires in {days_left} days (on {exp}); review before that date", file=sys.stderr)

sys.exit(0)
PY

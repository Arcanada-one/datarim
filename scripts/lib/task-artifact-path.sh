# shellcheck shell=bash
# Resolve a canonical PRD or dedicated plan without guessing a revision.
# Undefined descriptor pointers retain legacy defaults (which may not exist).
# Explicit pointers require a regular, task-bound file in the matching directory.

_TASK_ARTIFACT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/schema-regex.sh
. "$_TASK_ARTIFACT_LIB_DIR/schema-regex.sh" || return 2

task_artifact_path() {
    local state="$1" task="$2" kind="$3"
    if ! [[ "$task" =~ $TASK_ID_RE ]]; then
        printf 'task-artifact-path: invalid task id: %s\n' "$task" >&2
        return 2
    fi
    case "$kind" in prd|plan) ;; *) printf 'task-artifact-path: invalid artifact kind\n' >&2; return 2 ;; esac
    python3 - "$state" "$task" "$kind" <<'PY'
from pathlib import Path
import json
import re
import sys


def fail(message):
    raise ValueError(message)


def reject_symlinks(root, relative):
    current = root
    for part in ("", *Path(relative).parts):
        if part:
            current /= part
        if current.is_symlink():
            fail(f"symlink forbidden: {current}")


def mapping_field(line):
    match = re.match(r"^([ \t]*)(.+?)[ \t]*:(?=[ \t]|$)[ \t]*(.*?)[ \t]*$", line)
    if not match:
        return None
    indent, key, value = match.groups()
    key = key.strip()
    if len(key) >= 2 and key[0] == key[-1] and key[0] in "\"'":
        key = key[1:-1]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        fail(f"unsupported descriptor key spelling: {key}")
    return indent, key, value


def flat_value(value):
    """Validate the descriptor's supported flat scalar/ID-list syntax."""
    if value.startswith('"'):
        try:
            parsed, end = json.JSONDecoder().raw_decode(value)
        except json.JSONDecodeError:
            fail("invalid or unclosed descriptor quoted scalar")
        suffix = value[end:]
        if suffix and not re.fullmatch(r"[ \t]+#.*", suffix):
            fail("unexpected text after descriptor quoted scalar")
        return parsed
    if value.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'(?:[ \t]+#.*)?", value)
        if not match:
            fail("invalid or unclosed descriptor scalar")
        return match.group(1).replace("''", "'")
    # A separated # starts a YAML comment; quoted literal # remains above.
    value = re.split(r"[ \t]+#", value, maxsplit=1)[0].rstrip()
    if value.startswith("#"):
        value = ""
    if value.startswith(("&", "*", "!", "|", ">", "{")):
        fail("unsupported descriptor scalar syntax")
    if value.startswith("["):
        if not re.fullmatch(r"\[[ \t]*(?:[A-Za-z0-9_-]+(?:[ \t]*,[ \t]*[A-Za-z0-9_-]+)*)?[ \t]*\]", value):
            fail("invalid descriptor flow list")
        return value
    if ": " in value:
        fail("descriptor scalar must quote mapping syntax")
    return None if value in ("", "null", "~") else value


def descriptor_fields(path, keys=("id", "task_id", "prd", "plan"), flat=False):
    if not path.exists():
        return {}
    if not path.is_file():
        fail(f"descriptor is not a regular file: {path}")
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        return {}
    fields = {}
    seen = set()
    previous = None
    for line in lines[1:]:
        if line == "---":
            return fields
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        field = mapping_field(line)
        if not field:
            if previous and line[0].isspace():
                fail(f"descriptor field must be scalar: {previous}")
            if line[0].isspace():
                continue
            fail("unsupported descriptor frontmatter mapping")
        indent, key, value = field
        if flat:
            if indent:
                fail("descriptor fields must be top-level flat values")
            if key in seen:
                fail(f"duplicate descriptor field: {key}")
            seen.add(key)
            parsed = flat_value(value)
            if key in keys and value.startswith("["):
                fail(f"descriptor field must be scalar: {key}")
        else:
            parsed = None
        if indent and key in keys:
            fail(f"descriptor field must be top-level: {key}")
        if indent and previous:
            fail(f"descriptor field must be scalar: {previous}")
        if indent or key not in keys:
            previous = None
            continue
        if key in fields:
            fail(f"duplicate descriptor field: {key}")
        if flat:
            value = parsed
        else:
            value = flat_value(value)
        fields[key] = value
        previous = key
    fail("descriptor frontmatter is not closed")


def resolve(state, task, kind):
    root = Path(state).absolute()
    if ".." in root.parts or not root.is_dir():
        fail("invalid datarim root")
    if root.is_symlink():
        fail("symlink forbidden at datarim root")
    # The caller owns root selection. Normalize host aliases (e.g. macOS /var)
    # before enforcing the state-relative, no-symlink artifact boundary.
    root = root.resolve(strict=True)
    descriptor = f"tasks/{task}-task-description.md"
    reject_symlinks(root, descriptor)
    fields = descriptor_fields(root / descriptor, flat=True)
    for key in ("id", "task_id"):
        if key in fields and fields[key] != task:
            fail(f"descriptor {key} must equal {task}")
    pointer = fields.get(kind)
    default = f"prd/PRD-{task}.md" if kind == "prd" else f"plans/{task}-plan.md"
    if pointer is not None:
        if not any(fields.get(key) == task for key in ("id", "task_id")):
            fail("selected artifact requires task-bound descriptor identity")
        stem = f"prd/PRD-{task}" if kind == "prd" else f"plans/{task}-plan"
        if not re.fullmatch(re.escape(stem) + r"(?:-v[1-9][0-9]*)?\.md", pointer):
            fail(f"invalid task-bound {kind} path: {pointer}")
    relative = pointer if pointer is not None else default
    reject_symlinks(root, relative)
    target = root / relative
    if pointer is not None and not target.is_file():
        fail(f"selected {kind} artifact missing or not a regular file: {target}")
    if target.exists() and not target.is_file():
        fail(f"{kind} artifact is not a regular file: {target}")
    if pointer is not None:
        for key, value in descriptor_fields(target, ("id", "task_id")).items():
            if key in ("id", "task_id") and value != task:
                fail(f"selected {kind} {key} must equal {task}")
    return target


try:
    print(resolve(*sys.argv[1:]))
except (ValueError, OSError, UnicodeError) as error:
    print(f"task-artifact-path: {error}", file=sys.stderr)
    sys.exit(2)
PY
}

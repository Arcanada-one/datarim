#!/usr/bin/env bash
# dev-tools/check-role-registry.sh — validator for config/roles.yaml.
# Validates the fleet role registry: schema + cross-field invariants.
#
# Validates:
#   1. JSON-schema conformance (config/role-registry.schema.json).
#   2. Cross-field invariants the schema cannot express:
#        - max_parallel <= global_max_parallel for every role;
#        - role IDs MUST be unique;
#        - autonomous roles (default_aal >= 3) MUST forbid the Layer-6 floor
#          {prod-deploy, secret-rotation};
#        - starter_skill resolves to an existing skills/fleet/* directory.
#        - optional agent and domain_skills projections resolve to shipped files.
#
# Usage:
#   check-role-registry.sh [--file PATH] [--root PATH] [--help]
#
# Exit codes:
#   0  OK
#   1  validation failure
#   2  usage error

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE=""

usage() {
    cat <<'EOF'
check-role-registry.sh — validate the fleet role registry (config/roles.yaml).

Usage:
  check-role-registry.sh [--file PATH] [--root PATH] [--help]

Exit codes: 0 OK | 1 validation failure | 2 usage error.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --file) FILE="${2:-}"; shift 2 ;;
        --root) ROOT="${2:-}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$FILE" ] || FILE="$ROOT/config/roles.yaml"
SCHEMA="$ROOT/config/role-registry.schema.json"

[ -f "$FILE" ]   || { echo "ERROR: roles file not found: $FILE" >&2; exit 1; }
[ -f "$SCHEMA" ] || { echo "ERROR: schema not found: $SCHEMA" >&2; exit 1; }

# All structural + cross-field checks in one Python pass (pyyaml + jsonschema).
python3 - "$FILE" "$SCHEMA" "$ROOT" <<'PY'
import sys, os
import yaml, json
try:
    import jsonschema
except ImportError:
    print("ERROR: python jsonschema module not available", file=sys.stderr)
    sys.exit(1)

roles_path, schema_path, root = sys.argv[1], sys.argv[2], sys.argv[3]

class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        if not isinstance(key_node, yaml.nodes.ScalarNode):
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "mapping keys must be scalar",
                key_node.start_mark,
            )
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate YAML key: {key}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)

try:
    with open(roles_path, encoding="utf-8") as f:
        data = yaml.load(f, Loader=UniqueKeyLoader)
except (OSError, TypeError, yaml.YAMLError) as exc:
    problem = getattr(exc, "problem", None) or str(exc)
    print(f"FAIL: invalid role registry YAML: {problem}", file=sys.stderr)
    sys.exit(1)
with open(schema_path) as f:
    schema = json.load(f)

errors = []

# 1. JSON-schema conformance
try:
    jsonschema.validate(instance=data, schema=schema)
except jsonschema.ValidationError as e:
    errors.append(f"schema: {e.message} (at {'/'.join(str(p) for p in e.absolute_path)})")

# Proceed with cross-field checks only when basic shape is present.
registry = data if isinstance(data, dict) else {}
gmp = registry.get("global_max_parallel")
roles_value = registry.get("roles")
roles = roles_value if isinstance(roles_value, list) else []
LAYER6_FLOOR = {"prod-deploy", "secret-rotation"}
seen_role_ids = set()

for r in roles:
    if not isinstance(r, dict):
        continue
    rid = r.get("id", "<no-id>")
    if isinstance(rid, str):
        if rid in seen_role_ids:
            errors.append(f"duplicate role id '{rid}'")
        else:
            seen_role_ids.add(rid)
    mp = r.get("max_parallel")
    if isinstance(mp, int) and isinstance(gmp, int) and mp > gmp:
        errors.append(f"role '{rid}': max_parallel {mp} > global_max_parallel {gmp}")
    aal = r.get("default_aal")
    if isinstance(aal, int) and aal >= 3:
        forbidden = set(r.get("forbidden_actions") or [])
        missing = LAYER6_FLOOR - forbidden
        if missing:
            errors.append(f"role '{rid}': autonomous (default_aal={aal}) missing Layer-6 forbidden floor: {sorted(missing)}")
    skill = r.get("starter_skill")
    if skill:
        skill_dir = os.path.join(root, skill)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isdir(skill_dir) or not os.path.isfile(skill_md):
            errors.append(f"role '{rid}': starter_skill '{skill}' does not resolve to an existing skill (missing {skill}/SKILL.md)")
        else:
            # Parse ONLY the frontmatter block (between the first two '---'
            # delimiters); the markdown body breaks a full-file YAML parse.
            fm_lines, in_fm, seen = [], False, 0
            with open(skill_md, encoding="utf-8", errors="replace") as sf:
                for ln in sf:
                    if ln.rstrip("\n") == "---":
                        seen += 1
                        if seen == 1:
                            in_fm = True
                            continue
                        if seen == 2:
                            break
                    elif in_fm:
                        fm_lines.append(ln)
            budget = None
            if fm_lines:
                try:
                    fm = yaml.safe_load("".join(fm_lines)) or {}
                    budget = (fm.get("metadata") or {}).get("context_budget_tokens")
                except yaml.YAMLError:
                    budget = None
            if not isinstance(budget, int):
                errors.append(f"role '{rid}': starter_skill '{skill}' SKILL.md frontmatter missing integer metadata.context_budget_tokens")
    agent = r.get("agent")
    if agent:
        agent_path = os.path.join(root, agent)
        if not os.path.isfile(agent_path):
            errors.append(f"role '{rid}': agent '{agent}' does not resolve to an existing file")
    for domain_skill in r.get("domain_skills") or []:
        domain_skill_md = os.path.join(root, domain_skill, "SKILL.md")
        if not os.path.isfile(domain_skill_md):
            errors.append(f"role '{rid}': domain_skill '{domain_skill}' does not resolve to an existing skill")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(roles)} roles valid ({roles_path})")
sys.exit(0)
PY

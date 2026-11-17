#!/usr/bin/env bash
set -euo pipefail
sbom="datarim-${TAG}-sbom.cdx.json"
# Scan the release tarball contents only — never the runner workspace (env paths).
extract_dir="$(mktemp -d "${RUNNER_TEMP:?}/sbom-src.XXXXXX")"
trap 'rm -rf "$extract_dir"' EXIT
tar -xzf "${TARBALL:?}" -C "$extract_dir"
# Prefer the single archive prefix directory when present (git archive layout).
scan_dir="$extract_dir"
shopt -s nullglob
entries=("$extract_dir"/*)
shopt -u nullglob
if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
  scan_dir="${entries[0]}"
fi
# Stable component identity; report paths relative to the scanned tree.
syft scan "dir:${scan_dir}" \
  --base-path "${scan_dir}" \
  --source-name "datarim" \
  --source-version "${TAG}" \
  -o "cyclonedx-json=${sbom}"
# Relativize any remaining absolute paths under the scan root so host/user/runner
# prefixes never appear in the published CycloneDX document.
python3 - "$sbom" "$scan_dir" "$extract_dir" <<'PY'
import json
import os
import sys
from pathlib import Path

sbom_path = Path(sys.argv[1])
roots = []
for raw in sys.argv[2:]:
    path = Path(raw).resolve()
    roots.append(str(path))
    roots.append(str(path) + os.sep)
    roots.append(raw)
    if not raw.endswith(os.sep):
        roots.append(raw + os.sep)
prefixes = sorted(set(roots), key=len, reverse=True)


def scrub(value: str) -> str:
    for prefix in prefixes:
        normalized = prefix.rstrip(os.sep)
        if value == normalized or value == prefix:
            return '.'
        needle = prefix if prefix.endswith(os.sep) else prefix + os.sep
        if value.startswith(needle):
            rel = value[len(needle):].lstrip(os.sep)
            return rel if rel else '.'
        if value.startswith(prefix):
            rel = value[len(prefix):].lstrip(os.sep)
            return rel if rel else '.'
    return value


def walk(obj):
    if isinstance(obj, dict):
        return {key: walk(val) for key, val in obj.items()}
    if isinstance(obj, list):
        return [walk(val) for val in obj]
    if isinstance(obj, str):
        return scrub(obj)
    return obj


document = walk(json.loads(sbom_path.read_text(encoding='utf-8')))
component = document.setdefault('metadata', {}).setdefault('component', {})
name = component.get('name')
if not isinstance(name, str) or name.startswith('/') or name in {'.', ''}:
    component['name'] = 'datarim'
if not component.get('version'):
    component['version'] = os.environ.get('TAG', '')
sbom_path.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')
PY
# Sanity: bomFormat must be CycloneDX, components array non-empty.
jq -e '.bomFormat == "CycloneDX" and (.components | length > 0)' "$sbom" > /dev/null
echo "SBOM=$sbom" >> "$GITHUB_ENV"

#!/usr/bin/env python3
"""Project-owned Datarim overlay registration, validation, and diagnostics."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

SCOPES = ('skills', 'commands', 'agents', 'templates', 'dev-tools')


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def overlay_path(root: Path) -> Path:
    return root / 'datarim/local'


def valid_relative(value: str) -> bool:
    path = Path(value)
    return (not path.is_absolute() and '..' not in path.parts and
            len(path.parts) >= 2 and path.parts[0] in SCOPES and
            all(part not in ('', '.') for part in path.parts))


def collect(root: Path, source: Path) -> tuple[dict[str, Path], dict[str, str | None], list[str]]:
    """Return overlay paths, recorded bases, and changed upstream bases."""
    local = overlay_path(root)
    if (root / 'datarim').is_symlink():
        raise ValueError('unsafe datarim directory symlink')
    if not local.exists():
        return {}, {}, []
    if local.is_symlink() or not local.is_dir():
        raise ValueError('unsafe datarim/local directory')
    manifest_path = local / 'manifest.json'
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError('overlay manifest missing or unsafe; use local-overlay.py add')
    record = json.loads(manifest_path.read_text(encoding='utf-8'))
    if record.get('schema') != 1 or not isinstance(record.get('files'), dict):
        raise ValueError('invalid overlay manifest schema')
    bases = record['files']
    if any(not isinstance(k, str) or not valid_relative(k) or
           (v is not None and (not isinstance(v, str) or len(v) != 64 or
            any(c not in '0123456789abcdef' for c in v))) for k, v in bases.items()):
        raise ValueError('invalid overlay manifest entry')
    paths = {}
    for scope in SCOPES:
        base = local / scope
        if not base.exists():
            continue
        if base.is_symlink() or not base.is_dir():
            raise ValueError(f'unsafe overlay scope: {scope}')
        for path in base.rglob('*'):
            if path.is_symlink():
                raise ValueError(f'overlay symlink refused: {path}')
            if path.is_file():
                relative = str(path.relative_to(local))
                if relative not in bases:
                    raise ValueError(f'unregistered overlay file: {relative}; use local-overlay.py add')
                paths[relative] = path
    if set(paths) != set(bases):
        raise ValueError('overlay manifest lists missing files: '+', '.join(sorted(set(bases)-set(paths))))
    drift = []
    for relative, base_hash in bases.items():
        upstream = source / relative
        current = sha(upstream.read_bytes()) if upstream.is_file() else None
        if current != base_hash:
            drift.append(relative)
    return paths, bases, drift


def register(root: Path, source: Path, relative: str) -> None:
    if not valid_relative(relative):
        raise ValueError('overlay path must be inside skills, commands, agents, templates, or dev-tools')
    local = overlay_path(root)
    if (root / 'datarim').is_symlink() or local.is_symlink():
        raise ValueError('unsafe overlay directory symlink')
    target = local / relative
    if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(local.resolve()):
        raise ValueError('overlay target must be an existing regular file')
    manifest_path = local / 'manifest.json'
    if manifest_path.exists():
        if manifest_path.is_symlink():
            raise ValueError('unsafe overlay manifest')
        record = json.loads(manifest_path.read_text(encoding='utf-8'))
        if record.get('schema') != 1 or not isinstance(record.get('files'), dict):
            raise ValueError('invalid overlay manifest schema')
    else:
        record = {'schema': 1, 'files': {}}
    if relative in record['files']:
        raise ValueError('already registered: '+relative)
    upstream = source / relative
    record['files'][relative] = sha(upstream.read_bytes()) if upstream.is_file() else None
    manifest_path.write_text(json.dumps(record, indent=2, sort_keys=True)+'\n', encoding='utf-8')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('add', 'status'))
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--source', type=Path)
    parser.add_argument('path', nargs='?')
    args = parser.parse_intermixed_args()
    root = args.project.resolve()
    source_arg = args.source
    if source_arg is None:
        installed = root / '.datarim-runtime/installation.json'
        if installed.is_file():
            source_arg = Path(json.loads(installed.read_text()).get('source_path') or
                              Path(__file__).resolve().parents[1])
        else:
            source_arg = Path(__file__).resolve().parents[1]
    source = source_arg.resolve()
    try:
        if args.action == 'add':
            if not args.path:
                parser.error('add requires relative path')
            register(root, source, args.path)
            print(json.dumps({'status': 'registered', 'path': args.path}))
        else:
            paths, _, drift = collect(root, source)
            runtime = root / '.datarim-runtime'
            modified = []
            runtime_check = "not_measured"
            manifest = runtime / 'installation.json'
            if manifest.is_file():
                old = json.loads(manifest.read_text())
                if isinstance(old.get('runtime_files'), dict):
                    runtime_check = 'measured'
                for relative, expected in old.get('runtime_files', {}).items():
                    path = runtime / relative
                    if not path.is_file() or path.is_symlink() or sha(path.read_bytes()) != expected:
                        modified.append(relative)
            print(json.dumps({'present': overlay_path(root).is_dir(), 'file_count': len(paths),
                              'upstream_base_changed': drift, 'runtime_modified': modified,
                              'runtime_modification_check': runtime_check}))
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError) as exc:
        print(f'OVERLAY_ERROR: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

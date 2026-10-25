#!/usr/bin/env python3
"""Write a vetted consumer evolution file into the project overlay only."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from local_overlay import collect, overlay_path, register, valid_relative  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--relative', required=True)
    parser.add_argument('--input', type=Path, required=True)
    args = parser.parse_args()
    root, source = args.root.resolve(), args.source.resolve()
    route = subprocess.run([sys.executable, str(Path(__file__).with_name('evolution-route.py')),
                            '--root', str(root)], capture_output=True, text=True)
    if route.returncode != 0:
        print(route.stderr, file=sys.stderr)
        return 2
    decision = json.loads(route.stdout)
    if decision['scope'] != 'consumer' or not decision['auto_apply']:
        print('EVOLUTION_WRITE_REFUSED: consumer auto-apply target required', file=sys.stderr)
        return 2
    if not valid_relative(args.relative) or args.input.is_symlink() or not args.input.is_file():
        print('EVOLUTION_WRITE_REFUSED: unsafe relative path or input', file=sys.stderr)
        return 2
    try:
        local = overlay_path(root)
        target = local / args.relative
        if any(parent.is_symlink() for parent in (target, *target.parents) if parent == local or parent.is_relative_to(local)):
            raise ValueError('overlay path contains symlink')
        if target.is_symlink() or (target.exists() and not target.is_file()):
            raise ValueError('unsafe overlay target')
        current, _, _ = collect(root, source)
        if target.exists() and args.relative not in current:
            raise ValueError('unregistered existing overlay target')
        data = args.input.read_bytes()
        if not data:
            raise ValueError('empty proposal input')
        prior = target.read_bytes() if target.exists() else None
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        try:
            if prior is None:
                register(root, source, args.relative)
        except Exception:
            if prior is None:
                target.unlink()
            else:
                target.write_bytes(prior)
            raise
        print(json.dumps({'status': 'written', 'scope': 'consumer', 'path': str(target)}))
    except (OSError, ValueError, UnicodeError) as exc:
        print(f'EVOLUTION_WRITE_REFUSED: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

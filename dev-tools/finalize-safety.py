#!/usr/bin/env python3
"""Read-only ownership and merge gates for /dr-finalize cleanup."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True)


def load_ledger(path: Path) -> dict:
    if path.is_symlink() or not path.is_file():
        raise ValueError('task-owned ledger missing or unsafe')
    data = json.loads(path.read_text())
    if data.get('schema') != 1 or not isinstance(data.get('owned'), dict):
        raise ValueError('invalid task-owned ledger')
    return data['owned']


def check_path(owned: dict, root: Path, target: Path) -> None:
    exact = str(target.absolute())
    if exact not in owned.get('paths', []):
        raise ValueError('item absent from task-owned ledger: '+exact)
    if not target.resolve(strict=False).is_relative_to(root.resolve()):
        raise ValueError('item outside task workspace: '+exact)
    if any(parent.is_symlink() for parent in (target, *target.parents)
           if parent == root or parent.is_relative_to(root)):
        raise ValueError('symlink cleanup refused: '+exact)
    if git(root, 'ls-files', '--error-unmatch', '--', exact).returncode == 0:
        raise ValueError('tracked file cleanup refused: '+exact)


def check_branch(owned: dict, repo: Path, branch: str) -> None:
    if branch not in owned.get('branches', []):
        raise ValueError('branch absent from task-owned ledger: '+branch)
    if git(repo, 'check-ref-format', '--branch', branch).returncode != 0:
        raise ValueError('unsafe branch name')
    if git(repo, 'status', '--porcelain').stdout.strip():
        raise ValueError('checkout is dirty; branch cleanup refused')
    default = git(repo, 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
    if default.returncode != 0:
        raise ValueError('default branch cannot be observed')
    base = default.stdout.strip()
    if git(repo, 'show-ref', '--verify', f'refs/heads/{branch}').returncode != 0:
        raise ValueError('task branch missing: '+branch)
    refs = [branch]
    remote_ref = 'refs/remotes/origin/' + branch
    if git(repo, 'show-ref', '--verify', remote_ref).returncode == 0:
        refs.append(remote_ref)
    for ref in refs:
        merged = git(repo, 'merge-base', '--is-ancestor', ref, base).returncode == 0
        same_tree = (git(repo, 'rev-parse', f'{ref}^{{tree}}').stdout ==
                     git(repo, 'rev-parse', f'{base}^{{tree}}').stdout)
        if not (merged or same_tree):
            raise ValueError('branch not proven merged into default branch: '+ref)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('path', 'branch', 'tracker'))
    parser.add_argument('--ledger', type=Path)
    parser.add_argument('--workspace', type=Path)
    parser.add_argument('--repo', type=Path)
    parser.add_argument('--target')
    parser.add_argument('--config', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'tracker':
            if args.config is None or not args.config.is_file():
                print(json.dumps({'status': 'not applied', 'reason': 'tracker integration is not configured'}))
                return 0
            data = json.loads(args.config.read_text())
            if not data.get('integration') or not data.get('final_status'):
                print(json.dumps({'status': 'not applied', 'reason': 'tracker mapping is incomplete'}))
            else:
                print(json.dumps({'status': 'configured', 'integration': data['integration'],
                                  'final_status': data['final_status']}))
            return 0
        if not args.ledger or not args.target:
            parser.error('ownership check requires --ledger and --target')
        owned = load_ledger(args.ledger)
        if args.action == 'path':
            if not args.workspace:
                parser.error('path check requires --workspace')
            check_path(owned, args.workspace.resolve(), Path(args.target))
        else:
            if not args.repo:
                parser.error('branch check requires --repo')
            check_branch(owned, args.repo.resolve(), args.target)
        print(json.dumps({'status': 'allowed', 'action': args.action, 'target': args.target}))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f'FINALIZE_REFUSED: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

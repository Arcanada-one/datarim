#!/usr/bin/env python3
"""Atomic task ownership registration and /dr-finalize cleanup gates."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

KINDS = {'path': 'paths', 'worktree': 'worktrees', 'branch': 'branches',
         'process': 'processes', 'container': 'containers'}


def safe_ancestors(path: Path) -> None:
    if '..' in path.parts:
        raise ValueError('parent traversal refused')
    for candidate in (path, *path.parents):
        if candidate.is_symlink():
            raise ValueError('symlink path refused: '+str(candidate))


def validate_value(kind: str, value: str, workspace: Path | None) -> str:
    if not value or '\x00' in value or '\n' in value:
        raise ValueError('empty or multiline ownership value refused')
    if kind in ('path', 'worktree'):
        target = Path(value)
        if not target.is_absolute():
            raise ValueError('owned path must be absolute')
        safe_ancestors(target)
        if target == Path('/') or target == Path.home() or len(target.parts) < 3:
            raise ValueError('broad cleanup path refused')
        if not target.exists() or (kind == 'worktree' and not target.is_dir()):
            raise ValueError('owned path must already exist at registration time')
        if kind == 'path':
            if workspace is None:
                raise ValueError('path registration requires --workspace')
            safe_ancestors(workspace)
            if not workspace.is_absolute() or not target.is_relative_to(workspace):
                raise ValueError('temporary path outside declared workspace')
        return str(target)
    if kind == 'branch':
        if git(Path.cwd(), 'check-ref-format', '--branch', value).returncode != 0:
            raise ValueError('unsafe branch name')
    elif kind == 'process':
        if not re.fullmatch(r'[1-9][0-9]*:[1-9][0-9]*', value):
            raise ValueError('process identity must be PID:start-tick')
    elif kind == 'container':
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', value):
            raise ValueError('unsafe container identity')
    return value


def add_owned(ledger: Path, kind: str, value: str, workspace: Path | None) -> bool:
    safe_ancestors(ledger)
    entry = validate_value(kind, value, workspace)
    ledger.parent.mkdir(parents=True, exist_ok=True)
    safe_ancestors(ledger)
    lock_fd = os.open(ledger.parent, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        safe_ancestors(ledger)
        if ledger.exists():
            owned = load_ledger(ledger)
        else:
            owned = {name: [] for name in KINDS.values()}
        if any(not isinstance(owned.get(name), list) or
               any(not isinstance(item, str) for item in owned[name])
               for name in KINDS.values()):
            raise ValueError('invalid task-owned ledger entries')
        bucket = owned[KINDS[kind]]
        if entry in bucket:
            return False
        bucket.append(entry)
        record = {'schema': 1, 'owned': owned}
        fd, temporary = tempfile.mkstemp(prefix='.finalize-', dir=ledger.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, 'w', encoding='utf-8') as stream:
                json.dump(record, stream, indent=2, sort_keys=True)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, ledger)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        return True
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)


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


def check_worktree(owned: dict, repo: Path, target: Path) -> None:
    exact = str(target.absolute())
    if exact not in owned.get('worktrees', []):
        raise ValueError('worktree absent from task-owned ledger: '+exact)
    safe_ancestors(target)
    worktrees = git(repo, 'worktree', 'list', '--porcelain')
    if worktrees.returncode != 0 or f'worktree {exact}\n' not in worktrees.stdout:
        raise ValueError('worktree is not registered in the named repository')
    status = git(target, 'status', '--porcelain', '--untracked-files=all', '--ignored')
    if status.returncode != 0 or status.stdout.strip():
        raise ValueError('worktree is dirty; cleanup refused')


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
    parser.add_argument('action', choices=('add', 'path', 'worktree', 'branch', 'tracker'))
    parser.add_argument('--ledger', type=Path)
    parser.add_argument('--workspace', type=Path)
    parser.add_argument('--repo', type=Path)
    parser.add_argument('--target')
    parser.add_argument('--kind', choices=tuple(KINDS))
    parser.add_argument('--value')
    parser.add_argument('--config', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'add':
            if not args.ledger or not args.kind or not args.value:
                parser.error('add requires --ledger, --kind and --value')
            created = add_owned(args.ledger, args.kind, args.value, args.workspace)
            print(json.dumps({'status': 'recorded' if created else 'already recorded',
                              'kind': args.kind, 'value': args.value}))
            return 0
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
        elif args.action == 'worktree':
            if not args.repo:
                parser.error('worktree check requires --repo')
            check_worktree(owned, args.repo.resolve(), Path(args.target))
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

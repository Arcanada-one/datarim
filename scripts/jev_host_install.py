#!/usr/bin/env python3
"""Install a revision-pinned, framework-neutral Jev host runtime explicitly."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1]
EVENTS = {
    'claude': [('UserPromptSubmit', None), ('PreToolUse', 'Bash|Write|Edit|MultiEdit'),
               ('PostToolUse', 'Write|Edit|MultiEdit')],
    'codex': [('UserPromptSubmit', None), ('PreToolUse', 'Bash|exec_command|shell|apply_patch'),
              ('PostToolUse', 'Bash|exec_command|shell|apply_patch')],
    'cursor': [('beforeSubmitPrompt', None), ('beforeShellExecution', None),
               ('postToolUse', None)],
}


def merge_hooks(original, client, runtime, owned_roots, *, register=True):
    """Replace only Jev commands; preserve foreign commands in mixed entries."""
    out = json.loads(json.dumps(original))
    if not isinstance(out, dict) or not isinstance(out.get('hooks', {}), dict):
        raise ValueError('Hook config and hooks must be objects')
    if client == 'cursor':
        if out.get('version', 1) != 1:
            raise ValueError('Unsupported Cursor hook config version')
        out['version'] = 1
    hooks = out.setdefault('hooks', {})
    def owned(command):
        try:
            words = shlex.split(command)
        except (ValueError, TypeError):
            return False
        for word in words:
            path = Path(word)
            if path.name not in ('jev_hook.py', 'project_hook.py', 'hook_user_prompt.py', 'hook_pre_tool.py', 'hook_post_tool.py'):
                continue
            if path.is_absolute() and any(path.is_relative_to(root) for root in owned_roots):
                return True
        return False
    # Remove legacy Jev entries even when their event is no longer registered.
    for event, entries in list(hooks.items()):
        if not isinstance(entries, list):
            raise ValueError('Hook entries must be arrays')
        kept = []
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError('Hook entry must be an object')
            if client == 'cursor':
                if not owned(entry.get('command', '')):
                    kept.append(entry)
            else:
                commands = entry.get('hooks', [])
                if not isinstance(commands, list) or any(not isinstance(h, dict) for h in commands):
                    raise ValueError('Hook commands must be objects')
                remaining = [h for h in commands if not owned(h.get('command', ''))]
                if remaining:
                    kept.append(dict(entry, hooks=remaining))
        hooks[event] = kept
    for event, matcher in (EVENTS[client] if register else []):
        command = shlex.join([sys.executable, str(runtime/'scripts/jev_hook.py'), client, event])
        item = {'command': command, 'timeout': 9}
        if client == 'cursor':
            if event == 'beforeShellExecution':
                item['failClosed'] = True
        else:
            item = {'hooks': [dict(item, type='command')]}
            if matcher:
                item['matcher'] = matcher
        hooks.setdefault(event, []).append(item)
    return out


def safe_path(home, relative):
    path = home/relative
    for item in (path, *path.parents):
        if item == home:
            break
        if item.is_symlink():
            raise ValueError('Refusing a symlink in managed host paths: '+str(item))
    return path


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.jev-write-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def install(args):
    home = Path(args.home).resolve(strict=True)
    source = SOURCE
    sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
    if dirty and not args.dry_run:
        raise ValueError('Commit and verify the source revision before host installation')
    base = safe_path(home, '.local/share/jev')
    runtime = safe_path(home, '.local/share/jev/releases/'+sha)
    config = safe_path(home, '.config/jev/config.json')
    key = safe_path(home, '.config/jev/credentials/api-key')
    state = safe_path(home, '.local/state/jev')
    owned = [base/'releases'] + [Path(p).resolve(strict=True) for p in args.replace_legacy_root]
    existing = json.loads(config.read_text()) if config.exists() else json.loads(
        (source/'plugins/dr-jev-control/config/jev-control.json').read_text())
    if not isinstance(existing, dict):
        raise ValueError('Host config must be an object')
    if args.datarim_project is not None:
        existing['datarim_projects'] = sorted({str(Path(p).resolve(strict=True)) for p in args.datarim_project})
    else:
        existing.setdefault('datarim_projects', [])
    existing.setdefault('telemetry', {}).update(path=None, store_prompt_text=False)
    if existing.get('api', {}).get('base_url') != 'https://api.typesafe.ai/v1/systemone':
        raise ValueError('Host Jev requires the pinned provider endpoint')
    files = {config: (json.dumps(existing, indent=2)+'\n').encode()}
    pointer = safe_path(home, '.config/jev/installation.json')
    files[pointer] = (json.dumps({'schema': 1, 'runtime': str(runtime)}, indent=2)+'\n').encode()
    paths = {'claude': '.claude/settings.json', 'codex': '.codex/hooks.json', 'cursor': '.cursor/hooks.json'}
    for client in args.client:
        target = safe_path(home, paths[client])
        original = json.loads(target.read_text()) if target.exists() else {}
        files[target] = (json.dumps(merge_hooks(original, client, runtime, owned), indent=2)+'\n').encode()
    for name in ('jev', 'jevcodex', 'jevclaude', 'jevcursor'):
        target = safe_path(home, '.local/bin/'+name)
        if target.exists():
            old = target.read_text()
            if '# Jev managed host launcher' not in old:
                raise ValueError('Unmanaged launcher exists: '+str(target))
        files[target] = ('#!/bin/sh\n# Jev managed host launcher\nexec '+shlex.join(
            [sys.executable, str(runtime/'scripts/jev.py')])+(' --agent='+name[3:] if name != 'jev' else '')+' "$@"\n').encode()
    if key.exists() and (not key.is_file() or key.stat().st_mode & 0o077):
        raise ValueError('Existing key must be a private regular file')
    if args.dry_run:
        print(json.dumps({'source_sha': sha, 'source_dirty': bool(dirty), 'runtime': str(runtime),
                          'files': [str(p) for p in files], 'key_file': str(key),
                          'codex_trust': 'requires native /hooks review; never bypassed'}, indent=2))
        return
    original = {path: path.read_bytes() if path.exists() else None for path in files}
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = state/('install-backup-'+str(time.time_ns()))
    backup.mkdir(mode=0o700)
    atomic_write(backup/'files.json', json.dumps({str(p): v.decode() if v is not None else None
                                                for p,v in original.items()}).encode())
    runtime.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not runtime.exists():
        stage = Path(tempfile.mkdtemp(prefix='.stage-', dir=runtime.parent))
        try:
            (stage/'scripts').mkdir()
            for name in ('jev.py', 'jev_hook.py', 'project_scope.py'):
                shutil.copy2(source/'scripts'/name, stage/'scripts'/name)
            plugin = stage/'plugins/dr-jev-control'
            plugin.mkdir(parents=True)
            for directory in ('scripts', 'config'):
                shutil.copytree(source/'plugins/dr-jev-control'/directory, plugin/directory,
                                ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
            metadata = {'schema': 1, 'runtime': str(runtime), 'source_sha': sha,
                        'config': str(config), 'key_file': str(key), 'state_dir': str(state),
                        'clients': args.client, 'with_jev': True}
            atomic_write(stage/'host-installation.json', json.dumps(metadata, indent=2).encode())
            stage.rename(runtime)
        finally:
            if stage.exists():
                shutil.rmtree(stage)
    metadata = json.loads((runtime/'host-installation.json').read_text())
    if metadata.get('runtime') != str(runtime) or metadata.get('source_sha') != sha:
        raise ValueError('Existing runtime identity mismatch')
    try:
        # Detect concurrent changes immediately before publishing any config.
        if any((p.read_bytes() if p.exists() else None) != data for p,data in original.items()):
            raise ValueError('Host configuration changed during preparation; rerun')
        key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not key.exists():
            fd = os.open(key, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600); os.close(fd)
        for path, data in files.items():
            atomic_write(path, data)
            if path.parent == home/'.local/bin':
                path.chmod(0o700)
    except Exception:
        for path, data in original.items():
            # Restore only files still equal to our proposed content.
            if path.is_file() and path.read_bytes() == files[path]:
                if data is None:
                    path.unlink()
                else:
                    atomic_write(path, data)
        raise
    report = {'installed': str(runtime), 'source_sha': sha, 'backup': str(backup),
              'key_file': str(key), 'native_live': 'not_measured'}
    if 'codex' in args.client:
        # Writing the hook file is not installing the hook. Codex gates hooks
        # behind TWO prompts, both in the TUI, and a refusal at either one is
        # silent: the client still reports the hooks as "Active", while the
        # ledger records no events for them. MEASURED on codex-cli 0.155.1 --
        # 73 PreToolUse events and zero UserPromptSubmit over 45 minutes,
        # because the newly written entries were still awaiting review.
        report['codex_hook_trust'] = {
            'state': 'not_measured',
            'gate_1': 'trust the working directory -- its own prompt says project-local '
                      'config, hooks and exec policies do not load until you do',
            'gate_2': '"Hooks need review" -> "Trust all and continue"; declining leaves '
                      'the hooks installed but never executed',
            'reinstall': 'trust is keyed to the command string, which contains '
                         'releases/<sha>, so every reinstall needs gate 2 again',
            'verify': 'jev doctor --agent=codex reads the enabled flags; the ledger is '
                      'the authority, not the client\'s Active counter'}
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', default=str(Path.home()))
    parser.add_argument('--client', action='append', choices=list(EVENTS), required=True)
    parser.add_argument('--datarim-project', action='append', default=None)
    parser.add_argument('--replace-legacy-root', action='append', default=[])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    args.client = sorted(set(args.client))
    try:
        install(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print('jev install: '+str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

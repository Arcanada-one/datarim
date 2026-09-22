#!/usr/bin/env python3
"""Install a pinned, project-local Datarim snapshot without changing user homes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parents[1]
BEGIN = '<!-- datarim-project:begin -->'
END = '<!-- datarim-project:end -->'
SCOPES = ('agents', 'skills', 'commands', 'templates', 'scripts', 'dev-tools', 'plugins', 'config', 'cli')
PRIVATE_IGNORES = ('/.datarim-runtime/', '/.datarim-runtime-previous/',
                   '/.datarim-uninstalled/', '/.datarim-install-*/',
                   '/config/credentials/', '/datarim/')


def private_ignores(text):
    for rule in PRIVATE_IGNORES:
        if rule not in text.splitlines():
            text += '\n' + rule + '\n'
    return text


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    target = root / relative
    if target.is_symlink() or not target.resolve().is_relative_to(root):
        raise ValueError(f'Refusing symlink or path escape: {relative}')
    for parent in target.parents:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError(f'Refusing symlink parent: {relative}')
    return target


def replace_block(text, block):
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1:
        raise ValueError('Malformed Datarim managed block; refusing overwrite')
    if BEGIN in text:
        before, rest = text.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        return before + block + after
    return text.rstrip() + '\n\n' + block + '\n'


def install(args):
    root = Path(args.project).resolve(strict=True)
    if root == Path.home().resolve() or root == Path('/') or root == SOURCE or SOURCE.is_relative_to(root):
        raise ValueError('Choose a consumer project, not home, filesystem root, or product source')
    runtime = safe_path(root, '.datarim-runtime')
    for context in args.context:
        path = Path(context)
        if path.is_absolute() or '..' in path.parts or context in ('', '.'):
            raise ValueError('Contexts must be explicit relative subdirectories')
        target = safe_path(root, context)
        if not target.is_dir() or not (target / '.git').exists():
            raise ValueError(f'Context is not an existing nested repository: {context}')
    args.context = sorted(set(str(Path(c)) for c in args.context))
    previous = None
    if runtime.exists():
        manifest = runtime / 'installation.json'
        if not manifest.is_file():
            raise ValueError('Existing unmanaged .datarim-runtime; refusing overwrite')
        previous = json.loads(manifest.read_text())
        if previous.get('project') != str(root):
            raise ValueError('Installation project mismatch')
    for name in ('CLAUDE.md', 'CLAUDE.local.md', '.claude/CLAUDE.md'):
        if (root / name).exists() or (root / name).is_symlink():
            raise ValueError(f'Merge {name} into AGENTS.md and remove it before installing')
    source_hash = hashlib.sha256()
    for scope in (*SCOPES, 'AGENTS.md', 'VERSION'):
        base = SOURCE / scope
        candidates = sorted(base.rglob('*')) if base.is_dir() else [base]
        for path in candidates:
            if any(part in ('__pycache__', '.pytest_cache', 'credentials', '.DS_Store') for part in path.parts):
                continue
            if path.is_symlink():
                if not path.resolve().is_relative_to(SOURCE):
                    raise ValueError('Source contains an external symlink')
            if path.is_file():
                source_hash.update(str(path.relative_to(SOURCE)).encode())
                source_hash.update(path.read_bytes())
    files = {}
    agents = safe_path(root, 'AGENTS.md')
    block = f'''{BEGIN}
## Datarim project workflow

This project explicitly enables Datarim. Read `.datarim-runtime/AGENTS.md`
for the framework workflow and load skills from `.datarim-runtime/skills/`.
Resolve these paths from this project's root, never from your home directory.
Use project-local `datarim/` state only. Do not enable this workflow in another
project. The product source checkout is not a task knowledge base.
Activate the local CLI with `source .datarim-runtime/activate.sh`.
{END}'''
    files['AGENTS.md'] = replace_block(agents.read_text() if agents.exists() else '# Project instructions\n', block).encode()
    ignore = safe_path(root, '.gitignore')
    text = ignore.read_text() if ignore.exists() else ''
    files['.gitignore'] = private_ignores(text).encode()
    if args.with_jev:
        import shlex
        settings_path = safe_path(root, '.claude/settings.local.json')
        settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
        if not isinstance(settings, dict) or not isinstance(settings.get('hooks', {}), dict):
            raise ValueError('Claude settings and hooks must be objects')
        hooks = settings.setdefault('hooks', {})
        for event, matcher in [('UserPromptSubmit', None), ('PreToolUse', 'Bash|Write|Edit|MultiEdit'), ('PostToolUse', 'Write|Edit|MultiEdit')]:
            existing = hooks.get(event, [])
            if not isinstance(existing, list):
                raise ValueError('Claude hook event must be an array')
            # Keep all unrelated entries, including foreign hooks in a mixed array.
            kept = []
            for item in existing:
                if not isinstance(item, dict):
                    raise ValueError('Claude hook entry must be an object')
                commands = item.get('hooks', [])
                if not isinstance(commands, list) or any(not isinstance(h, dict) for h in commands):
                    raise ValueError('Claude hook commands must be an array of objects')
                remaining = [h for h in commands if '.datarim-runtime/scripts/project_hook.py' not in str(h.get('command', ''))]
                if remaining:
                    kept.append({**item, 'hooks': remaining})
            entry = {'hooks': [{'type': 'command', 'timeout': 9,
                     'command': shlex.join([sys.executable, str(runtime/'scripts/project_hook.py'), event])}]}
            if matcher:
                entry['matcher'] = matcher
            hooks[event] = kept + [entry]
        files['.claude/settings.local.json'] = (json.dumps(settings, indent=2)+'\n').encode()
    # Native discovery paths, preserving whole-directory foreign skill sets.
    for skill in sorted((SOURCE / 'skills').glob('*/SKILL.md')):
        files[f'.agents/skills/{skill.parent.name}/SKILL.md'] = (
            f'---\nname: {skill.parent.name}\ndescription: Load the project-local Datarim {skill.parent.name} skill when needed.\n---\n\n'
            f'Read `.datarim-runtime/skills/{skill.parent.name}/SKILL.md` from the project root.\n').encode()
    for command in sorted((SOURCE / 'commands').glob('*.md')):
        files[f'.agents/skills/{command.stem}/SKILL.md'] = (
            f'---\nname: {command.stem}\ndescription: Run the project-local Datarim {command.stem} workflow command.\n---\n\n'
            f'Read `.datarim-runtime/commands/{command.name}` from the project root.\n').encode()
        files[f'.claude/commands/{command.name}'] = command.read_bytes()
    # Each vendor discovers skills through its own project-local directory.
    for name, data in list(files.items()):
        if name.startswith('.agents/skills/'):
            for vendor in ('.claude', '.cursor'):
                files[name.replace('.agents/', vendor+'/', 1)] = data
    # All files are checked before the first mutation.
    for name, data in files.items():
        target = safe_path(root, name)
        if name in ('AGENTS.md', '.gitignore', '.claude/settings.local.json'):
            continue
        if target.exists() and target.read_bytes() != data:
            expected = (previous or {}).get('files', {}).get(name)
            if expected != digest(target.read_bytes()):
                raise ValueError(f'Unmanaged or locally modified file: {name}')
    key = safe_path(root, 'config/credentials/jev/api-key')
    if key.exists() and (not key.is_file() or key.stat().st_mode & 0o077):
        raise ValueError('Existing Jev key is not private (expected mode 0600)')
    if args.dry_run:
        print(json.dumps({'project': str(root), 'files': sorted(files), 'runtime': str(runtime), 'with_jev': args.with_jev}))
        return
    if previous and previous.get('source_digest') == source_hash.hexdigest() and previous.get('with_jev') == args.with_jev and previous.get('contexts', []) == args.context:
        if all((root/name).is_file() and (root/name).read_bytes() == data for name, data in files.items()):
            print(json.dumps({'status': 'unchanged', 'project': str(root)}))
            return
    stage = Path(tempfile.mkdtemp(prefix='.datarim-install-', dir=root))
    backups = {}
    old_runtime = root / '.datarim-runtime-previous'
    if old_runtime.exists():
        stage.rmdir()
        raise ValueError('Previous runtime already exists; verify and retire it before updating')
    try:
        for scope in SCOPES:
            if (SOURCE / scope).exists():
                shutil.copytree(SOURCE / scope, stage / scope, symlinks=False,
                                ignore=shutil.ignore_patterns('__pycache__', '.pytest_cache', '.DS_Store', 'credentials'))
        for name in ('AGENTS.md', 'VERSION'):
            shutil.copy2(SOURCE / name, stage / name)
        (stage / 'bin').mkdir()
        for name in ('jev', 'jevcodex', 'jevclaude', 'jevcursor'):
            (stage / 'bin' / name).symlink_to('../scripts/jev.py')
        # The activation affects only the current shell. Every entrypoint
        # independently checks cwd, including after leaving this directory.
        import shlex
        quoted = shlex.quote(str(runtime))
        (stage / 'activate.sh').write_text(
            f'export DATARIM_RUNTIME={quoted}\nexport PATH={quoted}/bin:"$PATH"\n')
        if args.with_jev:
            cfg = json.loads((stage / 'plugins/dr-jev-control/config/jev-control.json').read_text())
            cfg['telemetry']['path'] = str(runtime / 'state/jev/ledger.jsonl')
            (stage / 'jev-config.json').write_text(json.dumps(cfg, indent=2)+'\n')
            if previous and (runtime/'jev-config.json').is_file():
                shutil.copy2(runtime/'jev-config.json', stage/'jev-config.json')
        if previous and (runtime/'state').is_dir():
            if (runtime/'state').is_symlink() or any(p.is_symlink() for p in (runtime/'state').rglob('*')):
                raise ValueError('Runtime state must not be a symlink')
            shutil.copytree(runtime/'state', stage/'state', symlinks=False)
        try:
            sha = subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip()
        except subprocess.CalledProcessError:
            sha = None
        manifest = {'schema': 1, 'project': str(root), 'source_sha': sha, 'source_digest': source_hash.hexdigest(),
                    'with_jev': args.with_jev, 'contexts': args.context,
                    'files': {n: digest(v) for n, v in files.items()}}
        (stage / 'installation.json').write_text(json.dumps(manifest, indent=2)+'\n')
        for name in files:
            target = root / name
            backups[name] = target.read_bytes() if target.exists() else None
        (stage/'rollback-files.json').write_text(json.dumps({n: v.decode() if v is not None else None for n,v in backups.items()}, indent=2)+'\n')
        (stage/'rollback-files.json').chmod(0o600)
        # Uninstall restores pre-install originals, even after several updates.
        originals = dict(backups)
        if previous:
            original_path = runtime/'original-files.json'
            if not original_path.is_file() or original_path.is_symlink():
                raise ValueError('Missing original-file manifest; refusing unsafe update')
            originals.update({n: v.encode() if v is not None else None
                              for n, v in json.loads(original_path.read_text()).items()})
        (stage/'original-files.json').write_text(json.dumps({n: v.decode() if v is not None else None for n,v in originals.items()}, indent=2)+'\n')
        (stage/'original-files.json').chmod(0o600)
        if runtime.exists():
            runtime.rename(old_runtime)
        stage.rename(runtime)
        for name, data in files.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        if args.with_jev:
            key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            key.parent.chmod(0o700)
            fd = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600) if not key.exists() else None
            if fd is not None:
                os.close(fd)
        if args.init:
            state = safe_path(root, 'datarim')
            state.mkdir(exist_ok=True)
            for name in ('tasks.md', 'backlog.md'):
                target = safe_path(root, 'datarim/'+name)
                if not target.exists():
                    target.write_text('# '+name.removesuffix('.md').title()+'\n')
        print(json.dumps({'status': 'installed', **manifest}))
    except Exception:
        for name, data in backups.items():
            target = root / name
            if data is None:
                target.unlink(missing_ok=True)
            else:
                target.write_bytes(data)
        if old_runtime.exists():
            if runtime.exists():
                shutil.rmtree(runtime)
            old_runtime.rename(runtime)
        elif not previous and runtime.exists():
            shutil.rmtree(runtime)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def uninstall(args):
    root = Path(args.project).resolve(strict=True)
    runtime = safe_path(root, '.datarim-runtime')
    manifest = json.loads((runtime/'installation.json').read_text())
    if manifest.get('project') != str(root):
        raise ValueError('Installation belongs to another project')
    changed = []
    for name, expected in manifest['files'].items():
        target = safe_path(root, name)
        if target.exists() and digest(target.read_bytes()) != expected:
            changed.append(name)
    if changed:
        raise ValueError('Preserve locally modified managed files before uninstall: '+', '.join(changed))
    if args.dry_run:
        print(json.dumps({'uninstall': str(root), 'files': sorted(manifest['files'])}))
        return
    backup = root/'.datarim-uninstalled'
    if backup.exists():
        raise ValueError('An uninstall backup already exists')
    originals = json.loads((runtime/'original-files.json').read_text())
    for name in originals:
        safe_path(root, name)
    # Keep a protected recovery bundle. Never remove task state or keys.
    runtime.rename(backup)
    for name, original in originals.items():
        target = root/name
        if name == '.gitignore':
            target.write_text(private_ignores(original or ''))
        elif original is None:
            target.unlink(missing_ok=True)
        else:
            target.write_text(original)
    print(json.dumps({'status': 'uninstalled', 'backup': str(backup), 'keys_and_state': 'preserved'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--with-jev', action='store_true')
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--context', action='append', default=[], help='Explicit nested repository path')
    args = parser.parse_args()
    try:
        uninstall(args) if args.uninstall else install(args)
    except (ValueError, OSError) as exc:
        print(f'datarim install: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

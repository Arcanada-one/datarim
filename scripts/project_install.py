#!/usr/bin/env python3
"""Install a pinned, project-local Datarim snapshot without changing user homes."""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

SOURCE = Path(__file__).resolve().parents[1]
BEGIN = '<!-- datarim-project:begin -->'
END = '<!-- datarim-project:end -->'
SCOPES = ('agents', 'skills', 'commands', 'templates', 'scripts', 'dev-tools', 'plugins', 'config', 'cli')
PRIVATE_IGNORES = ('/.datarim-runtime/', '/.datarim-runtime-previous/',
                   '/.datarim-runtime-backups/',
                   '/.datarim-uninstalled/', '/.datarim-install-*/',
                   '/.datarim-install.lock',
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


def project_directory(value):
    root = Path(value).resolve(strict=True)
    protected = {Path(p).resolve() for p in ('/', '/etc', '/usr', '/bin', '/sbin', '/System',
                 '/Library', '/Applications', '/opt', '/var', '/tmp', '/home', '/Users')}
    if (root in protected or root == Path.home().resolve() or root in Path.home().resolve().parents
            or root == SOURCE or SOURCE.is_relative_to(root)):
        raise ValueError('Choose a consumer project, not home, a system directory, or product source')
    return root


@contextlib.contextmanager
def project_lock(root):
    path = safe_path(root, '.datarim-install.lock')
    fd = os.open(path, os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW|os.O_NONBLOCK, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError('Installation lock must be a regular file')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError('Another installation transaction owns this project') from exc
        yield
    finally:
        os.close(fd)


def install(args):
    root = project_directory(args.project)
    if args.dry_run:
        return _install(args)
    with project_lock(root):
        return _install(args)


def _install(args):
    root = Path(args.project).resolve(strict=True)
    if getattr(args, 'host_jev', False):
        from jev_hook import host_runtime
        host_runtime()  # A declaration alone must not silently remove all hooks.
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
    if args.with_jev or (previous or {}).get('with_jev'):
        from jev_host_install import merge_hooks
        for client, relative in [('claude', '.claude/settings.local.json'),
                                 ('codex', '.codex/hooks.json'), ('cursor', '.cursor/hooks.json')]:
            target = safe_path(root, relative)
            current = json.loads(target.read_text()) if target.exists() else {}
            register = args.with_jev and not getattr(args, 'host_jev', False)
            updated = merge_hooks(current, client, runtime, [runtime], register=register)
            files[relative] = (json.dumps(updated, indent=2)+'\n').encode()
    # Native discovery paths, preserving whole-directory foreign skill sets.
    for skill in sorted((SOURCE / 'skills').rglob('SKILL.md')):
        relative = str(skill.parent.relative_to(SOURCE/'skills'))
        name = relative.replace('/', '-')
        header = skill.read_text().split('---', 2)
        if len(header) != 3 or header[0].strip():
            raise ValueError(f'Skill has no YAML frontmatter: {relative}')
        target = f'.agents/skills/{name}/SKILL.md'
        if target in files:
            raise ValueError(f'Skill discovery name collision: {name}')
        files[target] = ('---'+header[1]+'---\n\n'
            f'Read `.datarim-runtime/skills/{relative}/SKILL.md` from the project root.\n').encode()
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
        if name in ('AGENTS.md', '.gitignore', '.claude/settings.local.json', '.codex/hooks.json', '.cursor/hooks.json'):
            continue
        if target.exists() and target.read_bytes() != data:
            expected = (previous or {}).get('files', {}).get(name)
            if expected != digest(target.read_bytes()):
                raise ValueError(f'Unmanaged or locally modified file: {name}')
    obsolete = set((previous or {}).get('files', {})) - set(files)
    for name in obsolete:
        target = safe_path(root, name)
        if target.exists() and digest(target.read_bytes()) != previous['files'][name]:
            raise ValueError(f'Locally modified retired discovery file: {name}')
    key = safe_path(root, 'config/credentials/jev/api-key')
    if key.exists() and (not key.is_file() or key.stat().st_mode & 0o077):
        raise ValueError('Existing Jev key is not private (expected mode 0600)')
    if args.dry_run:
        print(json.dumps({'project': str(root), 'files': sorted(files), 'runtime': str(runtime), 'with_jev': args.with_jev}))
        return
    if previous and previous.get('source_digest') == source_hash.hexdigest() and previous.get('with_jev') == args.with_jev and previous.get('host_jev', False) == getattr(args, 'host_jev', False) and previous.get('contexts', []) == args.context:
        if all((root/name).is_file() and (root/name).read_bytes() == data for name, data in files.items()):
            print(json.dumps({'status': 'unchanged', 'project': str(root)}))
            return
    stage = Path(tempfile.mkdtemp(prefix='.datarim-install-', dir=root))
    backups = {}
    old_runtime = safe_path(root, '.datarim-runtime-previous')
    archived_previous = None
    moved_current = False
    installed_new = False
    if old_runtime.exists():
        prior = old_runtime/'installation.json'
        if not prior.is_file() or json.loads(prior.read_text()).get('project') != str(root):
            stage.rmdir()
            raise ValueError('Previous runtime is not an owned project backup')
        archived_previous = safe_path(root, '.datarim-runtime-backups/'+uuid.uuid4().hex)
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
                    'with_jev': args.with_jev, 'host_jev': getattr(args, 'host_jev', False), 'contexts': args.context,
                    'files': {n: digest(v) for n, v in files.items()}}
        (stage / 'installation.json').write_text(json.dumps(manifest, indent=2)+'\n')
        for name in set(files) | obsolete:
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
        if archived_previous is not None:
            archived_previous.parent.mkdir(mode=0o700, exist_ok=True)
            old_runtime.rename(archived_previous)
        if runtime.exists():
            runtime.rename(old_runtime)
            moved_current = True
        stage.rename(runtime)
        installed_new = True
        for name, data in files.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        for name in obsolete:
            (root/name).unlink(missing_ok=True)
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
        if moved_current:
            if runtime.exists():
                shutil.rmtree(runtime)
            old_runtime.rename(runtime)
        elif installed_new and not previous and runtime.exists():
            shutil.rmtree(runtime)
        if archived_previous is not None and archived_previous.exists() and not old_runtime.exists():
            archived_previous.rename(old_runtime)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def uninstall(args):
    root = project_directory(args.project)
    if args.dry_run:
        return _uninstall(args)
    with project_lock(root):
        return _uninstall(args)


def _uninstall(args):
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
    parser.add_argument('--host-jev', action='store_true', help='Use already installed host Jev hooks; do not register duplicate project hooks')
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--context', action='append', default=[], help='Explicit nested repository path')
    args = parser.parse_args()
    if args.host_jev and not args.with_jev:
        parser.error('--host-jev requires --with-jev')
    try:
        uninstall(args) if args.uninstall else install(args)
    except (ValueError, OSError) as exc:
        print(f'datarim install: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

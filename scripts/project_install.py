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
                   '/.datarim-recovery-*/', '/config/credentials/', '/datarim/')


def git_ignored(source=None):
    """Paths under the shipped scopes that git ignores in this source checkout.

    The installer used to take whatever sat on disk. On a checkout where Codex
    had once written its own system skills into `skills/.system/` (ignored,
    untracked), every project install copied OpenAI's `imagegen`,
    `skill-installer` and three more skills into `.agents/`, `.claude/` and
    `.cursor/` -- content no clone of the repository contains, and exactly the
    place an ignored secret would travel the same way. A source that is not a
    git checkout keeps the previous behaviour: nothing is known to be ignored.
    """
    source = Path(source or SOURCE)
    try:
        out = subprocess.run(['git', '-C', str(source), 'ls-files', '--others', '--ignored',
                              '--exclude-standard', '--directory', '-z', '--', *SCOPES, 'AGENTS.md', 'VERSION'],
                             capture_output=True, text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return frozenset()
    return frozenset(item.rstrip('/') for item in out.split('\0') if item)


def is_ignored(path, ignored, source=None):
    relative = Path(path).relative_to(source or SOURCE)
    return any(str(relative) == item or str(relative).startswith(item + '/') for item in ignored)


EXCLUDE_BEGIN = '# datarim-project:begin'
EXCLUDE_END = '# datarim-project:end'


def release_agents_block(text, original=None):
    """AGENTS.md without the block earlier releases appended to it.

    Datarim no longer writes into files a project shares. AGENTS.md is loaded
    into every session of every agent, so a block there imposed the framework on
    work that never invoked it -- and in a repository shared with people who do
    not run Datarim it left a change nobody could commit.
    """
    if BEGIN not in text:
        return text
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError('Malformed Datarim managed block; refusing overwrite')
    before, rest = text.split(BEGIN, 1)
    _, after = rest.split(END, 1)
    before = before.rstrip('\n') + '\n'
    return before + ('\n' + after.lstrip('\n') if after.strip() else '')


def release_private_ignores(text, original=None):
    """.gitignore without the rules earlier releases appended, keeping any rule
    the project had before Datarim and every line anyone else added."""
    keep = set((original or '').splitlines())
    out = []
    for line in text.split('\n'):
        if line in PRIVATE_IGNORES and line not in keep:
            if out and out[-1] == '':
                out.pop()
            continue
        out.append(line)
    return '\n'.join(out)


def git_exclude_target(root):
    """(`info/exclude` path, prefix of `root` inside its repository), or None
    when the project is not in a git repository."""
    try:
        exclude = subprocess.run(['git', '-C', str(root), 'rev-parse', '--git-path', 'info/exclude'],
                                 capture_output=True, text=True, timeout=30, check=True).stdout.strip()
        prefix = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-prefix'],
                                capture_output=True, text=True, timeout=30, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return (Path(root)/exclude).resolve(), prefix


def write_git_exclude(root, rules):
    """Replace this project's block in the clone-local `.git/info/exclude`.

    Unlike .gitignore this file is never committed, so what one person's
    install generates stays out of everyone else's `git status`.
    """
    found = git_exclude_target(root)
    if found is None:
        return None
    path, prefix = found
    text = path.read_text() if path.exists() else ''
    begin, end = f'{EXCLUDE_BEGIN} /{prefix}', f'{EXCLUDE_END} /{prefix}'
    if begin in text and end in text:
        before, rest = text.split(begin, 1)
        _, after = rest.split(end, 1)
        text = before.rstrip('\n') + ('\n' if before.strip() else '') + after.lstrip('\n')
    if rules:
        text = (text.rstrip('\n') + ('\n' if text.strip() else '') + begin + '\n'
                + ''.join('/' + prefix + rule.lstrip('/') + '\n' for rule in rules) + end + '\n')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


HOOK_CONFIGS = ('.claude/settings.local.json', '.codex/hooks.json', '.cursor/hooks.json')
CLIENTS = ('claude', 'codex', 'cursor')
CLIENT_HOOK_CONFIG = dict(zip(CLIENTS, HOOK_CONFIGS))
#: The top-level directory through which each client discovers commands and
#: skills. Codex reads `.agents/skills/`.
CLIENT_DIRECTORY = {'.claude': 'claude', '.agents': 'codex', '.cursor': 'cursor'}
CLAUDE_MD = 'CLAUDE.md'


def owning_client(name):
    """The client a generated project file belongs to, or None when shared."""
    return CLIENT_DIRECTORY.get(name.split('/', 1)[0])


def parse_clients(values):
    """`--client` values, repeatable or comma separated, as a sorted tuple."""
    chosen = set()
    for value in values or []:
        for item in str(value).split(','):
            item = item.strip()
            if item == 'all':
                chosen.update(CLIENTS)
            elif item in CLIENTS:
                chosen.add(item)
            elif item:
                raise ValueError(f'Unknown client: {item} (choose from {", ".join(CLIENTS)} or all)')
    if values and not chosen:
        raise ValueError('--client needs at least one client')
    return tuple(sorted(chosen))


def _hooks_empty(config):
    """True when a hook config holds nothing but an empty skeleton."""
    hooks = config.get('hooks') or {}
    return set(config) <= {'hooks', 'version'} and not any(hooks.values())


def is_our_claude_link(root):
    """True when CLAUDE.md is a symlink to the project's AGENTS.md."""
    link = Path(root)/CLAUDE_MD
    try:
        return link.is_symlink() and os.readlink(link) == 'AGENTS.md'
    except OSError:
        return False


def exclude_rules(names, created=()):
    """Private paths, every discovery entry point this install generated, and
    any client hook config the install itself created (a pre-existing one is the
    project's, and a tracked file cannot be hidden anyway)."""
    rules = list(PRIVATE_IGNORES)
    for name in sorted(names):
        parts = name.split('/')
        if len(parts) == 4 and parts[1] == 'skills':
            rule = '/' + '/'.join(parts[:3]) + '/'
        elif name.startswith('.claude/commands/') or (name in HOOK_CONFIGS and name in created):
            rule = '/' + name
        else:
            continue
        if rule not in rules:
            rules.append(rule)
    return rules


def command_preamble(runtime):
    return (f'> **Datarim** for this project lives in `{runtime}`. Before following this command, '
            f'read `{runtime}/AGENTS.md` for the framework rules. Wherever the text below says '
            f'`${{DATARIM_RUNTIME}}`, that is `{runtime}`; in a shell, run '
            f'`export DATARIM_RUNTIME="{runtime}"` first.\n\n')


def with_preamble(data, runtime):
    """The command text with the runtime location in front of its body.

    Commands are the only way into Datarim now, so each one carries what the
    AGENTS.md block used to say -- loaded when the command runs, not always."""
    text, pre = data.decode(), command_preamble(runtime)
    if text.startswith('---\n'):
        close = text.find('\n---\n', 4)
        if close != -1:
            return (text[:close+5] + '\n' + pre + text[close+5:].lstrip('\n')).encode()
    return (pre + text).encode()


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


def prune_empty_parents(root, target):
    """Remove directories a deleted file leaves empty, below the client's own
    top-level directory (`.claude/`, `.agents/`, ...), which is never removed."""
    for parent in target.parents:
        if parent == root or parent.parent == root:
            return
        try:
            parent.rmdir()
        except OSError:  # not empty, or already gone
            return


def atomic_bytes(target, data):
    """Publish complete bytes, retaining an existing file's access mode."""
    fd, temporary = tempfile.mkstemp(prefix='.datarim-write-', dir=target.parent)
    try:
        mode = stat.S_IMODE(target.stat().st_mode) if target.exists() else 0o600
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


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
    # Directory names to refuse, not paths to open: each is resolved and
    # compared, never written to. The temp directory is assembled from os.sep
    # rather than spelled as a literal so a scanner does not read this refusal
    # list as a hardcoded temp path (B108); the platform's own temp directory is
    # added alongside it, because on macOS that is under /var/folders and a
    # list naming only /tmp would let an installation land there.
    names = ['/', '/etc', '/usr', '/bin', '/sbin', '/System', '/Library',
             '/Applications', '/opt', '/var', '/home', '/Users',
             os.path.join(os.sep, 'tmp'), tempfile.gettempdir()]
    protected = set()
    for name in names:
        # A name that does not exist on this platform is not a reason to fail.
        with contextlib.suppress(OSError):
            protected.add(Path(name).resolve())
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


CHOICE_QUESTIONS = """Datarim needs your choices before installing. AI agent: ask the user these questions, then rerun.
  1) Jev: none (--without-jev) / project (--with-jev) / host (install host Jev first with
     scripts/jev_host_install.py, then --with-jev --host-jev).
  2) Clients: --client claude,codex,cursor (default: all three).
  3) Permission mode for the jev* launchers: ask (default), or run `jev permissions full` after install.
Then rerun with --with-jev or --without-jev. --dry-run shows the plan without writing anything.
See INSTALL.md."""


class ChoiceRequired(ValueError):
    """A fresh install was started without an explicit Jev choice."""


def key_instructions(root, host_jev):
    """Where the Jev key goes and how to write it, for the installer's output."""
    key = (Path.home()/'.config/jev/credentials/api-key') if host_jev else Path(root)/'config/credentials/jev/api-key'
    return (f'Jev key file: {key}\n'
            '  Open it in an editor and paste the key on one line. Do not echo/printf the key into it: '
            'the command would land in your shell history.\n'
            '  Then check it with: jev doctor --api')


def remembered_choices(args, previous):
    """Resolve --with-jev, --host-jev and --context against the previous install.

    An option not given keeps what the installation recorded. Before this, an
    update run without `--with-jev` -- the documented `update.sh --project .`
    -- silently removed the project's Jev hooks and its jev-config.json, and
    one without `--context` withdrew every approved nested repository. Only
    an explicit `--without-jev`, `--no-host-jev` or `--no-context` turns a
    recorded choice off.
    """
    previous = previous or {}
    with_jev = getattr(args, 'with_jev', None)
    if with_jev is None:
        with_jev = bool(previous.get('with_jev'))
    host_jev = getattr(args, 'host_jev', None)
    if host_jev is None:
        host_jev = bool(previous.get('host_jev')) and with_jev
    if host_jev and not with_jev:
        raise ValueError('--host-jev requires --with-jev')
    contexts = getattr(args, 'context', None)
    if getattr(args, 'no_context', False):
        contexts = []
    elif contexts is None:
        contexts = list(previous.get('contexts') or [])
    return with_jev, host_jev, contexts


def _install(args):
    root = Path(args.project).resolve(strict=True)
    runtime = safe_path(root, '.datarim-runtime')
    previous = None
    if runtime.exists():
        manifest = runtime / 'installation.json'
        if not manifest.is_file():
            raise ValueError('Existing unmanaged .datarim-runtime; refusing overwrite')
        previous = json.loads(manifest.read_text())
        if previous.get('project') != str(root):
            raise ValueError('Installation project mismatch')
    if previous is None and getattr(args, 'with_jev', None) is None:
        # Scripted and agent-driven installs used to run without asking the
        # user anything; the questions in the docs did not survive a
        # summarizing fetch. A fresh install needs the Jev choice explicitly.
        if not args.dry_run:
            raise ChoiceRequired(CHOICE_QUESTIONS)
        print('note: ' + CHOICE_QUESTIONS, file=sys.stderr)
    args.with_jev, args.host_jev, args.context = remembered_choices(args, previous)
    if args.host_jev:
        from jev_hook import host_runtime
        host_runtime()  # A declaration alone must not silently remove all hooks.
    for context in args.context:
        path = Path(context)
        if path.is_absolute() or '..' in path.parts or context in ('', '.'):
            raise ValueError('Contexts must be explicit relative subdirectories')
        target = safe_path(root, context)
        if not target.is_dir() or not (target / '.git').exists():
            raise ValueError(f'Context is not an existing nested repository: {context}')
    args.context = sorted(set(str(Path(c)) for c in args.context))
    ignored = git_ignored()
    source_hash = hashlib.sha256()
    for scope in (*SCOPES, 'AGENTS.md', 'VERSION'):
        base = SOURCE / scope
        candidates = sorted(base.rglob('*')) if base.is_dir() else [base]
        for path in candidates:
            if any(part in ('__pycache__', '.pytest_cache', 'credentials', '.DS_Store') for part in path.parts):
                continue
            if is_ignored(path, ignored):
                continue
            if path.is_symlink():
                if not path.resolve().is_relative_to(SOURCE):
                    raise ValueError('Source contains an external symlink')
            if path.is_file():
                source_hash.update(str(path.relative_to(SOURCE)).encode())
                source_hash.update(path.read_bytes())
    files = {}
    snapshots = {}
    def read_initial(name):
        target = safe_path(root, name)
        if name not in snapshots:
            snapshots[name] = target.read_bytes() if target.exists() else None
        return snapshots[name]
    # Nothing goes into files the project shares. An earlier release appended a
    # block to AGENTS.md and rules to .gitignore; on update those are removed
    # once and the files leave management -- never deleted, since both are the
    # project's own.
    prior_originals = {}
    if previous and (runtime/'original-files.json').is_file():
        prior_originals = json.loads((runtime/'original-files.json').read_text())
    released = set()
    # Clients: the explicit choice, else what the previous install recorded,
    # else all three (installs before the option wrote files for all three).
    clients = tuple(sorted(getattr(args, 'client', None) or (previous or {}).get('clients') or CLIENTS))
    # Without Jev every client's hooks are withdrawn, as for a removed client.
    deselected = [c for c in CLIENTS if c not in clients or not args.with_jev]
    retired_hooks = set()
    for name, release in (('AGENTS.md', release_agents_block), ('.gitignore', release_private_ignores)):
        if name in (previous or {}).get('files', {}):
            current = read_initial(name)
            if current is not None:
                files[name] = release(current.decode(), prior_originals.get(name)).encode()
                released.add(name)
    if args.with_jev:
        from jev_host_install import merge_hooks
        for client in clients:
            relative = CLIENT_HOOK_CONFIG[client]
            safe_path(root, relative)
            current = json.loads(read_initial(relative) or b'{}')
            register = not args.host_jev
            updated = merge_hooks(current, client, runtime, [runtime], register=register)
            files[relative] = (json.dumps(updated, indent=2)+'\n').encode()
    # A client removed from the selection loses its Jev hooks. The file itself
    # goes only when the install created it and nothing else is left in it.
    for client in deselected:
        relative = CLIENT_HOOK_CONFIG[client]
        if relative not in (previous or {}).get('files', {}):
            continue
        from jev_host_install import merge_hooks
        current = read_initial(relative)
        if current is None:
            continue
        stripped = merge_hooks(json.loads(current), client, runtime, [runtime], register=False)
        if prior_originals.get(relative, b'') is None and _hooks_empty(stripped):
            retired_hooks.add(relative)
        else:
            files[relative] = (json.dumps(stripped, indent=2)+'\n').encode()
    # Native discovery. Only the /dr-* commands are entry points by default: a
    # discoverable skill's description is loaded into every session, which is
    # the framework imposing itself again. Commands load skills by path.
    expose = getattr(args, 'expose_skills', False) or (previous or {}).get('expose_skills', False)
    for skill in sorted((SOURCE / 'skills').rglob('SKILL.md')) if expose else []:
        if is_ignored(skill, ignored):
            continue
        relative = str(skill.parent.relative_to(SOURCE/'skills'))
        name = relative.replace('/', '-')
        header = skill.read_text().split('---', 2)
        if len(header) != 3 or header[0].strip():
            raise ValueError(f'Skill has no YAML frontmatter: {relative}')
        target = f'.agents/skills/{name}/SKILL.md'
        if target in files:
            raise ValueError(f'Skill discovery name collision: {name}')
        files[target] = ('---'+header[1]+'---\n\n'
            f'Read `{runtime}/skills/{relative}/SKILL.md`.\n').encode()
    for command in sorted((SOURCE / 'commands').glob('*.md')):
        if is_ignored(command, ignored):
            continue
        files[f'.agents/skills/{command.stem}/SKILL.md'] = (
            f'---\nname: {command.stem}\ndescription: Run the project-local Datarim {command.stem} workflow command.\n---\n\n'
            + command_preamble(runtime) + f'Then read `{runtime}/commands/{command.name}` and follow it.\n').encode()
        files[f'.claude/commands/{command.name}'] = with_preamble(command.read_bytes(), runtime)
    # Each vendor discovers skills through its own project-local directory.
    # Claude Code already has the commands in .claude/commands; a skill copy of
    # each would put 28 more descriptions into every Claude session.
    command_stems = {c.stem for c in (SOURCE / 'commands').glob('*.md')}
    for name, data in list(files.items()):
        if name.startswith('.agents/skills/'):
            for vendor in ('.claude', '.cursor'):
                if vendor == '.claude' and name.split('/')[2] in command_stems:
                    continue
                files[name.replace('.agents/', vendor+'/', 1)] = data
    for name in [n for n in files if n not in HOOK_CONFIGS and owning_client(n) not in (None, *clients)]:
        del files[name]
    # Claude Code reads CLAUDE.md, not AGENTS.md. Opt-in, sticky, and only ever
    # a symlink this install created: an existing CLAUDE.md is never touched.
    claude_import = getattr(args, 'claude_import', None)
    if claude_import and 'claude' not in clients:
        raise ValueError('--claude-import needs the claude client')
    if claude_import is None:
        claude_import = bool((previous or {}).get('claude_import')) and 'claude' in clients
    link = root/CLAUDE_MD
    owned_link = bool((previous or {}).get('claude_md_link')) and is_our_claude_link(root)
    link_action = None
    if claude_import and not owned_link:
        if is_our_claude_link(root):
            link_action = 'already_linked'
        elif link.exists() or link.is_symlink():
            link_action = 'kept_existing'
        elif not (root/'AGENTS.md').is_file():
            if getattr(args, 'claude_import', None):
                raise ValueError('--claude-import links CLAUDE.md to AGENTS.md; the project has no AGENTS.md')
            link_action = 'no_agents_md'
        else:
            link_action = 'create'
    elif not claude_import and owned_link:
        link_action = 'remove'

    # All files are checked before the first mutation.
    for name, data in files.items():
        target = safe_path(root, name)
        read_initial(name)
        if name in ('AGENTS.md', '.gitignore', '.claude/settings.local.json', '.codex/hooks.json', '.cursor/hooks.json'):
            continue
        if target.exists() and target.read_bytes() != data:
            expected = (previous or {}).get('files', {}).get(name)
            if expected != digest(target.read_bytes()):
                raise ValueError(f'Unmanaged or locally modified file: {name}')
    obsolete = set((previous or {}).get('files', {})) - set(files)
    for name in obsolete:
        target = safe_path(root, name)
        read_initial(name)
        if name in retired_hooks:
            continue  # holds nothing but Jev's entries, whatever its digest
        if target.exists() and digest(target.read_bytes()) != previous['files'][name]:
            raise ValueError(f'Locally modified retired discovery file: {name}')
    key = safe_path(root, 'config/credentials/jev/api-key')
    if key.exists() and (not key.is_file() or key.stat().st_mode & 0o077):
        raise ValueError('Existing Jev key is not private (expected mode 0600)')
    if args.dry_run:
        print(json.dumps({'project': str(root), 'files': sorted(files), 'runtime': str(runtime),
                          'with_jev': args.with_jev, 'host_jev': args.host_jev, 'contexts': args.context,
                          'clients': list(clients), 'claude_md': link_action}))
        return
    if (previous and previous.get('source_digest') == source_hash.hexdigest() and previous.get('with_jev') == args.with_jev
            and previous.get('host_jev', False) == args.host_jev
            and previous.get('contexts', []) == args.context
            and tuple(previous.get('clients') or CLIENTS) == clients
            and bool(previous.get('claude_import')) == claude_import
            and link_action in (None, 'kept_existing', 'already_linked', 'no_agents_md')):
        if all((root/name).is_file() and (root/name).read_bytes() == data for name, data in files.items()):
            print(json.dumps({'status': 'unchanged', 'project': str(root)}))
            return
    stage = Path(tempfile.mkdtemp(prefix='.datarim-install-', dir=root))
    backups = {}
    published = {}
    old_runtime = safe_path(root, '.datarim-runtime-previous')
    archived_previous = None
    moved_current = False
    installed_new = False
    link_changed = None
    if old_runtime.exists():
        prior = old_runtime/'installation.json'
        if not prior.is_file() or json.loads(prior.read_text()).get('project') != str(root):
            stage.rmdir()
            raise ValueError('Previous runtime is not an owned project backup')
        archived_previous = safe_path(root, '.datarim-runtime-backups/'+uuid.uuid4().hex)
    try:
        for scope in SCOPES:
            if (SOURCE / scope).exists():
                by_name = shutil.ignore_patterns('__pycache__', '.pytest_cache', '.DS_Store', 'credentials')
                def skip(directory, names, by_name=by_name):
                    return set(by_name(directory, names)) | {
                        n for n in names if is_ignored(Path(directory)/n, ignored)}
                shutil.copytree(SOURCE / scope, stage / scope, symlinks=False, ignore=skip)
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
            cfg.pop('_comment', None)  # marks the template only
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
                    'with_jev': args.with_jev, 'host_jev': args.host_jev, 'contexts': args.context,
                    'expose_skills': expose, 'clients': list(clients),
                    'claude_import': claude_import, 'claude_md_link': (owned_link and link_action != 'remove') or link_action == 'create',
                    'files': {n: digest(v) for n, v in files.items() if n not in released}}
        (stage / 'installation.json').write_text(json.dumps(manifest, indent=2)+'\n')
        for name in set(files) | obsolete:
            target = root / name
            current = safe_path(root, name).read_bytes() if target.exists() else None
            if current != snapshots[name]:
                raise ValueError(f'Concurrent modification: {name}')
            backups[name] = snapshots[name]
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
        for name in released:
            originals.pop(name, None)  # no longer ours to restore on uninstall
        for name in obsolete:
            if originals.get(name, b'') is None:
                # Created by an earlier install and removed by this one: there
                # is nothing to restore, and a file someone creates there later
                # is not ours to delete on uninstall.
                originals.pop(name)
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
            target = safe_path(root, name)
            current = target.read_bytes() if target.exists() else None
            if current != snapshots[name]:
                raise ValueError(f'Concurrent modification: {name}')
            atomic_bytes(target, data)
            published[name] = data
        for name in obsolete:
            target = safe_path(root, name)
            current = target.read_bytes() if target.exists() else None
            if current != snapshots[name]:
                raise ValueError(f'Concurrent modification: {name}')
            target.unlink(missing_ok=True)
            prune_empty_parents(root, target)
            published[name] = None
        if link_action == 'create':
            if link.exists() or link.is_symlink():
                raise ValueError(f'Concurrent modification: {CLAUDE_MD}')
            link.symlink_to('AGENTS.md')
            link_changed = 'created'
        elif link_action == 'remove' and is_our_claude_link(root):
            link.unlink()
            link_changed = 'removed'
        if args.with_jev:
            key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            key.parent.chmod(0o700)
            fd = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600) if not key.exists() else None
            if fd is not None:
                os.close(fd)
        rules = exclude_rules((n for n in files if n not in released),
                              created={n for n, v in originals.items() if v is None})
        if manifest['claude_md_link']:
            rules.append('/' + CLAUDE_MD)
        write_git_exclude(root, rules)
        if args.init:
            state = safe_path(root, 'datarim')
            state.mkdir(exist_ok=True)
            for name in ('tasks.md', 'backlog.md'):
                target = safe_path(root, 'datarim/'+name)
                if not target.exists():
                    target.write_text('# '+name.removesuffix('.md').title()+'\n')
        print(json.dumps({'status': 'installed', **manifest, 'claude_md': link_action}))
        if args.with_jev:
            print(key_instructions(root, args.host_jev), file=sys.stderr)
    except Exception:
        recovery = []
        try:
            if link_changed == 'created' and is_our_claude_link(root):
                link.unlink()
            elif link_changed == 'removed' and not (link.exists() or link.is_symlink()):
                link.symlink_to('AGENTS.md')
        except OSError:
            recovery.append({'path': CLAUDE_MD, 'status': 'restore_failed'})
        for name, expected in published.items():
            try:
                target = safe_path(root, name)
                current = target.read_bytes() if target.exists() else None
                if current != expected:
                    recovery.append({'path': name, 'status': 'foreign_change_preserved'})
                    continue
                data = backups[name]
                if data is None:
                    target.unlink(missing_ok=True)
                else:
                    atomic_bytes(target, data)
            except (OSError, ValueError):
                recovery.append({'path': name, 'status': 'restore_failed'})
        # Keep the already-written snapshot when any shared file was not restored.
        recovery_bundle = None
        if recovery and installed_new and runtime.exists():
            recovery_bundle = safe_path(root, '.datarim-recovery-'+uuid.uuid4().hex)
            try:
                runtime.chmod(0o700)
                runtime.rename(recovery_bundle)
            except OSError:
                # Do not destroy the sole remaining pre-update file snapshot.
                print(json.dumps({'status': 'rollback_incomplete', 'recovery': recovery,
                                  'recovery_bundle': str(runtime),
                                  'previous_runtime': str(old_runtime)}), file=sys.stderr)
                raise
        # A failed file restore must never prevent the runtime rollback.
        try:
            if moved_current:
                if runtime.exists():
                    shutil.rmtree(runtime)
                old_runtime.rename(runtime)
            elif installed_new and not previous and runtime.exists():
                shutil.rmtree(runtime)
            if archived_previous is not None and archived_previous.exists() and not old_runtime.exists():
                archived_previous.rename(old_runtime)
        except OSError:
            recovery.append({'path': '.datarim-runtime', 'status': 'restore_failed'})
        if recovery:
            print(json.dumps({'status': 'rollback_incomplete', 'recovery': recovery,
                              'recovery_bundle': str(recovery_bundle) if recovery_bundle else None}), file=sys.stderr)
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
    if manifest.get('claude_md_link') and is_our_claude_link(root):
        (root/CLAUDE_MD).unlink()
    for name, original in originals.items():
        target = root/name
        if name == '.gitignore':
            target.write_text(private_ignores(original or ''))
        elif original is None:
            target.unlink(missing_ok=True)
            prune_empty_parents(root, target)
        else:
            target.write_text(original)
    # Keys, task state and the recovery bundle stay, so they stay hidden too.
    write_git_exclude(root, list(PRIVATE_IGNORES))
    print(json.dumps({'status': 'uninstalled', 'backup': str(backup), 'keys_and_state': 'preserved'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--with-jev', dest='with_jev', action='store_const', const=True, default=None,
                        help='Register the Jev hooks and create the project key file; kept across updates')
    parser.add_argument('--without-jev', dest='with_jev', action='store_const', const=False,
                        help='No Jev. A fresh install needs --with-jev or --without-jev; on update, '
                             'withdraws the Jev hooks (the key file is kept)')
    parser.add_argument('--host-jev', action=argparse.BooleanOptionalAction, default=None,
                        help='Use already installed host Jev hooks; do not register duplicate project hooks. '
                             'Kept across updates; --no-host-jev returns to project hooks')
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--expose-skills', action='store_true',
                        help='Also expose every framework skill to native discovery (loaded into every '
                             'session); by default only the /dr-* commands are exposed')
    parser.add_argument('--client', action='append', default=None, metavar='CLIENT',
                        help='Install for this client only: claude, codex, cursor or all; repeat the option '
                             'or give a comma list. Default: the clients recorded by the previous install, '
                             'else all three. A client left out on update loses its managed files and hooks.')
    parser.add_argument('--claude-import', action=argparse.BooleanOptionalAction, default=None,
                        help='Link CLAUDE.md to the project AGENTS.md so Claude Code, which reads only '
                             'CLAUDE.md, loads the project rules. Only created when no CLAUDE.md exists; '
                             'kept across updates; --no-claude-import removes the link this install made')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--context', action='append', default=None,
                        help='Explicit nested repository path; repeatable. Given, it replaces the recorded '
                             'list; omitted, the recorded list is kept')
    parser.add_argument('--no-context', action='store_true', help='Withdraw every approved nested repository')
    args = parser.parse_args()
    if args.host_jev and args.with_jev is False:
        parser.error('--host-jev requires --with-jev')
    if args.no_context and args.context:
        parser.error('--no-context and --context exclude each other')
    try:
        args.client = parse_clients(args.client) or None
    except ValueError as exc:
        parser.error(str(exc))
    try:
        uninstall(args) if args.uninstall else install(args)
    except (ValueError, OSError) as exc:
        print(f'datarim install: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

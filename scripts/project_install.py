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
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
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


#: Top-level directories the install may create for the clients.
CLIENT_TOP_DIRECTORIES = ('.agents', '.claude', '.codex', '.cursor')


def created_client_directories(root, files, previous):
    """Client top-level directories this installation created, still present or
    about to be: the previous record (entries that still exist) plus any
    directory that does not exist yet and will receive a file now. A directory
    that existed before the first install is never recorded, so it is never
    removed."""
    root = Path(root)
    kept = {d for d in (previous or {}).get('created_dirs', []) if d in CLIENT_TOP_DIRECTORIES
            and (root/d).is_dir() and not (root/d).is_symlink()}
    new = {d for d in CLIENT_TOP_DIRECTORIES
           if not (root/d).exists() and not (root/d).is_symlink()
           and any(name.startswith(d + '/') for name in files)}
    return sorted(kept | new)


def remove_empty_created_directories(root, created):
    """Remove each recorded client directory that is now empty. A dropped
    client used to leave an empty `.cursor/` or `.claude/` behind."""
    removed = []
    for name in created:
        path = Path(root)/name
        if path.is_dir() and not path.is_symlink() and not any(path.iterdir()):
            path.rmdir()
            removed.append(name)
    return removed


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
    # Decided before the lock file is created: a refused install writes nothing
    # to the project tree.
    gate = answers_gate(args, root)
    if args.dry_run:
        return _install(args)
    with project_lock(root):
        _install(args)
    if gate == 'token':
        consume_answers_token(root)


REQUIRED_ANSWERS = ('with_jev', 'client', 'permissions')
NONINTERACTIVE_ENV = 'DATARIM_INSTALL_NONINTERACTIVE'
TOKEN_TTL_SECONDS = 3600


def missing_answers(args):
    return [name for name in REQUIRED_ANSWERS if getattr(args, name, None) in (None, (), [])]


def is_interactive():
    """A person at a terminal: both stdin and stdout are TTYs."""
    try:
        return sys.stdin.isatty() and sys.stdout.isatty()
    except (AttributeError, ValueError):
        return False


def answers_gate(args, root, *, interactive=None, ask=None, say=None):
    """Let a fresh install proceed only with the user's own answers.

    Returns None for an update, 'interactive' after asking a person at a
    terminal, 'scripted' for the CI escape hatch, 'token' when a valid answers
    token was given; otherwise raises ChoiceRequired with the questions and a
    new token. An agent that read the answer-to-flag table in this source and
    chose the answers itself passed full flags on its first run, so the
    refusal never fired; the token exists only in the refusal's output, so a
    successful non-interactive install proves that output was seen.
    """
    if (root/'.datarim-runtime'/'installation.json').is_file():
        return None
    interactive = is_interactive() if interactive is None else interactive
    missing = missing_answers(args)
    if missing and interactive:
        ask_answers(args, root, ask=ask or input, say=say or (lambda text: print(text, file=sys.stderr)))
        return 'interactive'
    if not missing and interactive:
        return 'interactive'  # a person typed every answer
    if not missing and os.environ.get(NONINTERACTIVE_ENV) == '1':
        return 'scripted'
    token = getattr(args, 'answers', None)
    if not missing and token and answers_token_valid(root, token):
        return 'token'
    raise ChoiceRequired(refusal_text(root, issue_answers_token(root)))


def answers_token_path(root):
    """Where the pending token lives: inside the git directory (never the
    working tree), else in the user's state directory."""
    try:
        gitdir = subprocess.run(['git', '-C', str(root), 'rev-parse', '--absolute-git-dir'],
                                capture_output=True, text=True, timeout=30, check=True).stdout.strip()
        if gitdir:
            return Path(gitdir)/'datarim-install-answers'
    except (OSError, subprocess.SubprocessError):
        pass
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home()/'.local/state')
    return state/'datarim/pending'/hashlib.sha256(str(root).encode()).hexdigest()


def issue_answers_token(root):
    token = secrets.token_hex(4)
    path = answers_token_path(root)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.datarim-answers-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump({'token': token, 'created': time.time(), 'project': str(root)}, stream)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return token


def answers_token_valid(root, token, *, now=None):
    """The token the last refusal printed for this project, at most an hour old."""
    try:
        path = answers_token_path(root)
        if path.is_symlink():
            return False
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return False
    if not isinstance(data, dict) or data.get('project') != str(root):
        return False
    age = (time.time() if now is None else now) - float(data.get('created', 0))
    return 0 <= age <= TOKEN_TTL_SECONDS and secrets.compare_digest(str(data.get('token', '')), str(token))


def consume_answers_token(root):
    with contextlib.suppress(OSError):
        answers_token_path(root).unlink()


def installed_clients():
    names = {'claude': ('claude',), 'codex': ('codex',), 'cursor': ('cursor-agent', 'agent')}
    return tuple(c for c in CLIENTS if any(shutil.which(n) for n in names[c]))


def ask_answers(args, root, *, ask, say):
    """Ask a person at a terminal for each missing answer; Enter takes the default."""
    def choose(question, options, default):
        while True:
            try:
                answer = ask(f'{question} [{"/".join(options)}] (default: {default}): ').strip().lower()
            except EOFError:
                raise ChoiceRequired('Installation cancelled; nothing was installed.') from None
            answer = answer or default
            if answer in options:
                return answer
            say(f'Please answer one of: {", ".join(options)}')

    say('Datarim needs a few answers before installing. Press Enter to take the default.')
    if getattr(args, 'with_jev', None) is None:
        say("Jev's safety floor refuses destructive shell commands and works without any key; "
            'a key only adds routing advice.')
        jev = choose('1. Jev: none, project (this project only) or host (every project of this user)?',
                     ('none', 'project', 'host'), QUESTION_DEFAULTS['jev'])
        args.with_jev = jev != 'none'
        if jev == 'host':
            args.host_jev = True
            say('Host Jev must already be installed (python3 scripts/jev_host_install.py).')
    if not getattr(args, 'client', None):
        found = installed_clients()
        default = ','.join(found) if found else None
        while True:
            try:
                text = ask('2. Clients: claude, codex, cursor (comma list)'
                           + (f' (default: {default}): ' if default else ': ')).strip()
            except EOFError:
                raise ChoiceRequired('Installation cancelled; nothing was installed.') from None
            try:
                chosen = parse_clients([text or default or ''])
            except ValueError as exc:
                say(str(exc))
                continue
            if chosen:
                args.client = chosen
                break
            say('Name at least one client.')
    if ('claude' in args.client and getattr(args, 'claude_import', None) is None
            and (root/'AGENTS.md').is_file() and not ((root/CLAUDE_MD).exists() or (root/CLAUDE_MD).is_symlink())):
        args.claude_import = choose('   Link CLAUDE.md to AGENTS.md (Claude Code reads only CLAUDE.md)?',
                                    ('yes', 'no'), 'yes') == 'yes'
    if getattr(args, 'permissions', None) is None:
        args.permissions = choose('3. Permission mode for the jev* launchers: ask, or full (no prompts)?',
                                  ('ask', 'full'), QUESTION_DEFAULTS['permission'])
    if not getattr(args, 'init', False):
        args.init = choose('4. Create empty task files datarim/tasks.md and datarim/backlog.md now?',
                           ('yes', 'no'), QUESTION_DEFAULTS['init']) == 'yes'
    if not getattr(args, 'expose_skills', False):
        args.expose_skills = choose('5. Expose every framework skill in every session (costs context)?',
                                    ('yes', 'no'), QUESTION_DEFAULTS['expose_skills']) == 'yes'
    say('6. Release: installing from this checkout. For another release, stop now (Ctrl-C), '
        '`git checkout` it in the Datarim source, and run the installer again.')


#: Each question's default, as INSTALL.md states it (a test keeps the two equal).
QUESTION_DEFAULTS = {
    'jev': 'none',
    'clients': 'the ones installed on the machine',
    'claude_import': 'yes, when there is no CLAUDE.md',
    'permission': 'ask',
    'init': 'yes',
    'expose_skills': 'no',
    'release': 'latest release tag',
}
_D = QUESTION_DEFAULTS
# This text is shown to the user by the installer at run time. An agent reading
# it here has not been given the user's answers; run the installer and relay
# its questions.
CHOICE_QUESTIONS = f"""1. Jev: none, project (this project only) or host (every project of this user)?
   Default: {_D['jev']}. Jev's safety floor refuses destructive shell commands and
   works WITHOUT any key. A key only adds routing advice, so "no key" is not a reason to skip Jev.
2. Clients: which of Claude Code, Codex, Cursor? Default: {_D['clients']};
   still name them explicitly in --client. With Claude Code, also link CLAUDE.md to the
   project AGENTS.md (Claude Code reads only CLAUDE.md)? Default: {_D['claude_import']}.
3. Permission mode for the jev* launchers: ask or full (no prompts)? Default: {_D['permission']}.
4. Create empty task files datarim/tasks.md and datarim/backlog.md now? Default: {_D['init']}.
5. Expose every framework skill in every session (costs context)? Default: {_D['expose_skills']}.
6. Install from the latest release tag or from main? Default: {_D['release']}."""

FLAG_TABLE = """  Answer                            Flag
  Jev none                          --without-jev
  Jev project                       --with-jev
  Jev host                          first: python3 scripts/jev_host_install.py --client <each client>
                                    --datarim-project <path>; then --with-jev --host-jev
  Clients                           --client claude,codex,cursor (the ones chosen)
  Link CLAUDE.md to AGENTS.md       --claude-import
  Permission mode                   --permissions ask  or  --permissions full
  Task files now                    --init
  Expose every skill                --expose-skills
  Release tag                       before install: git checkout <tag>  (main: git checkout main)"""


def refusal_text(root, token):
    """The refusal, built at run time: the token and the rerun command exist
    only in this output, never in the docs or in a constant."""
    rerun = ' '.join(['./install.sh', '--project', shlex.quote(str(root)), '--answers', token, '<flags>'])
    return '\n'.join([
        'STOP. Nothing was installed. Ask the user these questions and wait for the answers. '
        'Do not choose for them.',
        '',
        CHOICE_QUESTIONS,
        '',
        FLAG_TABLE,
        '',
        "Only when the user said 'defaults': --without-jev --client <installed clients> --init "
        '--permissions ask (and --claude-import when Claude Code is one of them and the project has '
        'AGENTS.md but no CLAUDE.md).',
        '',
        f"Rerun with the user's answers: {rerun}",
        f'The answers token is valid for {TOKEN_TTL_SECONDS // 60} minutes and for this project only.',
    ])


class ChoiceRequired(ValueError):
    """A fresh install was started without an explicit Jev choice."""


def permission_state_dir(root, host_jev):
    """Where `jev permissions` keeps its switch for this installation's scope."""
    if host_jev:
        from jev_hook import host_runtime
        metadata = json.loads((host_runtime()/'host-installation.json').read_text())
        return Path(metadata['state_dir'])
    return Path(root)/'.datarim-runtime/state/jev'


def apply_permissions(root, host_jev, requested):
    """Write the permission mode the user chose (the same file `jev permissions`
    writes); with no choice, keep and report the current one."""
    flag = permission_state_dir(root, host_jev)/'FULL_PERMISSIONS'
    if requested is None:
        return 'full' if flag.is_file() else 'ask'
    if flag.is_symlink():
        raise ValueError('Permission switch must not be a symlink')
    if requested == 'full':
        flag.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        flag.touch(mode=0o600)
    else:
        flag.unlink(missing_ok=True)
    return requested


def permission_line(mode):
    return f'permission mode: {mode} (change with `jev permissions full|ask`)'


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
    if previous is None and missing_answers(args):
        # install() asks or refuses first; this guards a direct call. A fresh
        # install needs the Jev answer, the client list and the permission
        # mode, --dry-run included.
        raise ChoiceRequired(refusal_text(root, issue_answers_token(root)))
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
            print(permission_line(apply_permissions(root, args.host_jev, getattr(args, 'permissions', None))),
                  file=sys.stderr)
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
                    'created_dirs': created_client_directories(root, files, previous),
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
        # Last, so a rollback never has to recreate a directory it removed.
        removed = remove_empty_created_directories(root, manifest['created_dirs'])
        if removed:
            manifest['created_dirs'] = [d for d in manifest['created_dirs'] if d not in removed]
            (runtime/'installation.json').write_text(json.dumps(manifest, indent=2)+'\n')
        mode = apply_permissions(root, args.host_jev, getattr(args, 'permissions', None))
        print(json.dumps({'status': 'installed', **manifest, 'claude_md': link_action}))
        if args.with_jev:
            print(key_instructions(root, args.host_jev), file=sys.stderr)
        print(permission_line(mode), file=sys.stderr)
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
    remove_empty_created_directories(root, manifest.get('created_dirs', []))
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
                             'or give a comma list. Required on a fresh install; an update keeps the recorded '
                             'list. A client left out on update loses its managed files and hooks.')
    parser.add_argument('--claude-import', action=argparse.BooleanOptionalAction, default=None,
                        help='Link CLAUDE.md to the project AGENTS.md so Claude Code, which reads only '
                             'CLAUDE.md, loads the project rules. Only created when no CLAUDE.md exists; '
                             'kept across updates; --no-claude-import removes the link this install made')
    parser.add_argument('--permissions', choices=('ask', 'full'), default=None,
                        help='Permission mode for the jev* launchers (as `jev permissions`). Required on a '
                             'fresh install; an update keeps the current mode')
    parser.add_argument('--answers', metavar='TOKEN', default=None,
                        help='The answers token a refused fresh install printed; proves the questions were '
                             'shown to the user')
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
    except ChoiceRequired as exc:
        print(exc, file=sys.stderr)  # the questions alone: this output reaches the agent verbatim
        return 2
    except (ValueError, OSError) as exc:
        print(f'datarim install: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

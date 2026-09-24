#!/usr/bin/env python3
"""Jev dispatcher for Claude Code, Codex and Cursor; Datarim is opt-in."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from project_scope import ScopeError, activate, project_root


#: Client options that take a separate value (Claude Code 2.1.280, codex-cli
#: 0.156.1, cursor-agent 2026.08), per client: `-c` and `-p` are switches in
#: Claude and take values in Codex. Jev's own --model/--effort/--resume/--agent/
#: --mode win; a client option with several values still needs --.
CLIENT_VALUE_OPTIONS = {
    'claude': frozenset((
        '--permission-mode', '--permission-prompts', '--append-system-prompt', '--system-prompt',
        '--system-prompt-snapshot', '--settings', '--setting-sources', '--mcp-config', '--output-format',
        '--input-format', '--session-id', '--fallback-model', '--agents', '--json-schema', '--max-budget-usd',
        '--name', '-n', '--debug-file', '--betas', '--autocompact', '--environment', '--file', '--tools',
        '--plugin-dir', '--plugin-url', '--remote-control-session-name-prefix')),
    'codex': frozenset((
        '-c', '--config', '--enable', '--disable', '--remote', '--remote-auth-token-env', '-i', '--image',
        '-m', '--local-provider', '-p', '--profile', '-s', '--sandbox', '-a', '--ask-for-approval')),
    'cursor': frozenset((
        '--api-key', '-H', '--header', '-e', '--endpoint', '--output-format', '--sandbox', '--plugin-dir',
        '--worktree-base')),
}


#: The words Jev itself handles as its first positional argument.
SUBCOMMANDS = ('doctor', 'stats', 'on', 'off', 'permissions', 'trust')


def bare_word_error(task):
    """The refusal for a single bare word that is not a subcommand, or None.

    `jev status --agent=claude` used to start a nested client session with
    "status" as its prompt. A one-word task with no spaces that is not an
    existing file is almost always a mistyped subcommand, so it is refused;
    a sentence, or an existing file named as the task, still launches.
    """
    if task is None or task in SUBCOMMANDS or re.search(r'\s', task) or not task:
        return None
    if Path(task).exists():
        return None
    return (f"unknown subcommand '{task}'; subcommands: {', '.join(SUBCOMMANDS)}; "
            'to send it as a task, quote a sentence or use --')


def parse(argv=None):
    alias = {'jevcodex': 'codex', 'jevclaude': 'claude', 'jevcursor': 'cursor'}.get(Path(sys.argv[0]).name)
    p = argparse.ArgumentParser(
        description=__doc__,
        epilog='Activate with: source .datarim-runtime/activate.sh. Options Jev does not know are passed to '
               'the client (e.g. jevclaude --dangerously-skip-permissions); give a client option its value '
               'as --flag=value, or put client arguments after --. '
               '`jev permissions full|ask` makes every launch skip (or keep) permission prompts.')
    p.add_argument('--agent', choices=['codex', 'claude', 'cursor'], default=alias)
    p.add_argument('--mode', choices=['economy', 'balanced', 'quality'], default='balanced')
    p.add_argument('--model')
    p.add_argument('--effort', choices=['low', 'medium', 'high'])
    p.add_argument('--resume')
    p.add_argument('--print', action='store_true')
    p.add_argument('--live', action='store_true')
    p.add_argument('--no-route', action='store_true')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--api', action='store_true', help='With doctor: explicitly test the Jev API')
    p.add_argument('--max-turns', type=int)
    p.add_argument('--max-seconds', type=float)
    p.add_argument('--continue-prompt')
    p.add_argument('--done-marker')
    p.add_argument('--version', action='version', version='Datarim Jev project dispatcher 1')
    p.add_argument('task', nargs='?', help='Task, or ' + ' / '.join(SUBCOMMANDS))
    p.add_argument('setting', nargs='?', help=argparse.SUPPRESS)
    values = list(sys.argv[1:] if argv is None else argv)
    extra = []
    if '--' in values:
        split = values.index('--')
        values, extra = values[:split], values[split + 1:]
    # Options Jev does not define belong to the client. Those that take a value
    # are moved together with it, so the value is not mistaken for Jev's task;
    # any other unknown option is a switch. Anything else goes after --.
    agent = alias
    for i, word in enumerate(values):
        if word == '--agent' and i + 1 < len(values):
            agent = values[i + 1]
        elif word.startswith('--agent='):
            agent = word.split('=', 1)[1]
    takes_value = CLIENT_VALUE_OPTIONS.get(agent, frozenset())
    ahead = []
    rest = []
    i = 0
    while i < len(values):
        word = values[i]
        if word in takes_value and i + 1 < len(values):
            ahead += [word, values[i + 1]]
            i += 2
            continue
        rest.append(word)
        i += 1
    a, unknown = p.parse_known_args(rest)
    extra = ahead + unknown + extra
    if a.setting is not None and a.task != 'permissions':
        p.error(f'unexpected argument: {a.setting}')
    refusal = bare_word_error(a.task)
    if refusal:
        p.error(refusal)
    if alias and a.agent != alias:
        p.error('An alias cannot select a different agent')
    if not a.live and any(x is not None for x in (a.max_turns, a.max_seconds, a.continue_prompt, a.done_marker)):
        p.error('Supervision limits require --live')
    if a.live and (a.model or a.effort or a.resume):
        p.error('Explicit model/effort/resume is currently supported in direct mode only')
    if (a.max_turns is not None and a.max_turns < 1) or (a.max_seconds is not None and a.max_seconds <= 0):
        p.error('Supervision limits must be positive')
    # CLI passthrough must not relocate the client outside verified scope.
    for value in extra:
        if value.startswith(('-C', '-w')) or value.split('=', 1)[0] in ('--cwd', '--directory', '--workspace', '--cd', '--worktree', '--add-dir'):
            p.error('Client directory/worktree overrides bypass project scope; launch from the approved context')
    return a, extra


#: What each client calls "do not ask". The Jev safety floor still runs in
#: every one of these modes: it is a hook, and hooks are not permission prompts.
FULL_PERMISSION_FLAGS = {
    'claude': ['--dangerously-skip-permissions'],
    'codex': ['--dangerously-bypass-approvals-and-sandbox'],
    'cursor': ['--force', '--approve-mcps'],
}
#: Options with which the operator already chose a permission policy.
PERMISSION_CHOICES = {
    'claude': ('--dangerously-skip-permissions', '--permission-mode', '--allow-dangerously-skip-permissions'),
    'codex': ('--dangerously-bypass-approvals-and-sandbox', '--yolo', '--full-auto', '-a', '--ask-for-approval',
              '-s', '--sandbox'),
    'cursor': ('--force', '-f', '--yolo', '--sandbox', '--auto-review'),
}


def full_permissions(state):
    """JEV_PERMISSIONS=full|ask overrides the stored `jev permissions` choice."""
    chosen = os.environ.get('JEV_PERMISSIONS', '').strip().lower()
    if chosen in ('full', 'ask'):
        return chosen == 'full'
    return (Path(state)/'FULL_PERMISSIONS').is_file()


def permission_flags(agent, extra):
    """Flags to add for full permissions; none when the operator chose a policy."""
    given = {x.split('=', 1)[0] for x in extra}
    if given & set(PERMISSION_CHOICES[agent]):
        return []
    return [f for f in FULL_PERMISSION_FLAGS[agent] if f not in given]


def binary(agent):
    name = {'claude': 'claude', 'codex': 'codex', 'cursor': 'cursor-agent'}[agent]
    return shutil.which(os.environ.get(agent.upper()+'_BIN', name)) or (shutil.which('agent') if agent == 'cursor' else None)


def datarim_enabled(root):
    """True when this project has an explicit Datarim installation.

    Measured from the installation manifest, not from an environment variable.
    The previous form read an environment variable that nothing in the tree
    ever sets (activate.sh exports DATARIM_RUNTIME), so the field could not
    become true even inside a correctly installed project — it reported "not
    enabled" for every possible state, which is indistinguishable from a real
    answer.

    Resolution walks up from the given directory, because a working directory
    inside an enabled project is still that project — reporting "not enabled"
    from a subdirectory would answer a different question than the one asked.
    The walk stops at the home directory so a stray manifest above it cannot
    enable unrelated work, and the manifest must still name the directory it
    sits in, so a copied installation does not count.
    """
    try:
        start = Path(root).resolve()
        home = Path.home().resolve()
        for candidate in (start, *start.parents):
            manifest = candidate/'.datarim-runtime/installation.json'
            if manifest.is_file() and not manifest.is_symlink():
                data = json.loads(manifest.read_text())
                return data.get('schema') == 1 and data.get('project') == str(candidate)
            if candidate == home:
                break
        return False
    except (OSError, ValueError):
        return False


# Codex's per-event key in `[hooks.state."<file>:<key>:<i>:<j>"]`
# (codex-rs hooks/src/lib.rs, `hook_event_key_label`).
CODEX_EVENT_KEYS = {
    'PreToolUse': 'pre_tool_use', 'PermissionRequest': 'permission_request',
    'PostToolUse': 'post_tool_use', 'PreCompact': 'pre_compact', 'PostCompact': 'post_compact',
    'SessionStart': 'session_start', 'SessionEnd': 'session_end',
    'UserPromptSubmit': 'user_prompt_submit', 'SubagentStart': 'subagent_start',
    'SubagentStop': 'subagent_stop', 'Stop': 'stop', 'Interrupt': 'interrupt'}
CODEX_CONTEXT_EVENTS = ('PreToolUse', 'PostToolUse', 'SessionStart', 'UserPromptSubmit',
                        'SubagentStart')


def codex_hook_hash(event, group, handler):
    """The hash Codex compares against `trusted_hash`, for a command hook.

    Reproduces codex-rs `hook_hash` (hooks/src/engine/discovery.rs) and
    `version_for_toml` (config/src/fingerprint.rs): sha256 over compact JSON with
    sorted keys, of the event key plus the matcher group holding only this
    handler, after Codex's own normalisation -- the timeout defaulted and
    clamped, `async` made explicit, an additionalContextLimit equal to the
    2,500 default dropped. Checked against hashes Codex itself wrote after a
    TUI "Trust all": identical for a hook with a matcher and one without.
    """
    timeout = handler.get('timeout')
    if event in ('SessionEnd', 'Interrupt'):
        timeout = max(1, min(3, 1 if timeout is None else timeout))
    else:
        timeout = max(1, 600 if timeout is None else timeout)
    normal = {'type': 'command', 'command': handler.get('command', ''), 'timeout': timeout,
              'async': bool(handler.get('async', False))}
    if handler.get('statusMessage') is not None:
        normal['statusMessage'] = handler['statusMessage']
    limit = handler.get('additionalContextLimit')
    if limit is not None and limit != 2500 and event in CODEX_CONTEXT_EVENTS:
        normal['additionalContextLimit'] = limit
    identity = {'event_name': CODEX_EVENT_KEYS[event], 'hooks': [normal]}
    if group.get('matcher') is not None:
        identity['matcher'] = group['matcher']
    text = json.dumps(identity, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    return 'sha256:' + hashlib.sha256(text.encode()).hexdigest()


def _codex_state_block(text, key):
    """The body of `[hooks.state."<key>"]`, or None. The key is matched whole:
    matching on its tail let a plugin's block (`hookify@...:hooks/hooks.json:
    user_prompt_submit:0:0`) answer for ours."""
    match = re.search(r'^\[hooks\.state\."' + re.escape(key) + r'"\]\n((?:(?!\[).*\n?)*)',
                      text, re.M)
    return match.group(1) if match else None


def codex_hook_trust(sha, home=None, *, hooks=None, entry=None):
    """Whether Codex will execute the Jev hooks it has installed.

    Codex runs a user hook only when its state block is not `enabled = false`
    AND its stored `trusted_hash` equals the hash of the hook as it stands now
    (codex-rs hooks/src/engine/discovery.rs: `hook_trust_status`,
    `hook_enabled`). The hash covers the command string, so changing the
    command silently turns a trusted hook into a `modified` one that Codex
    skips. Two earlier revisions of this check got that wrong -- one demanded
    an `enabled = true` key Codex writes only sometimes, the next took the
    mere presence of a block as trust -- and both reported `trusted` or
    `untrusted` from things the client does not look at. Measured on
    codex-cli 0.156.1 after a release-pinned reinstall: Jev's hooks had moved
    to `modified`, stopped running on three hosts, and the presence-based
    check said `trusted` on all three.

    States per hook: `trusted`, `modified` (trusted once, command changed),
    `untrusted` (never trusted), `disabled` (`enabled = false`). The overall
    `state` is `trusted` only when every Jev hook is.

    A project install registers its hooks in `<project>/.codex/hooks.json`
    with the project runtime's `jev_hook.py`; pass that file as `hooks` and
    that script as `entry`. Trust is still stored in the user's
    `~/.codex/config.toml`, keyed by the hooks file's own path, so the same
    reading applies. Without them the host files are read.
    """
    home = Path(home or Path.home())
    config = home/'.codex/config.toml'
    host = hooks is None
    hooks = Path(hooks) if hooks is not None else home/'.codex/hooks.json'
    if not hooks.is_file():
        return {'state': 'not_measured', 'reason': 'no Codex hook configuration', 'hooks_file': str(hooks)}
    if not config.is_file():
        return {'state': 'not_measured', 'reason': 'no Codex config.toml', 'hooks_file': str(hooks)}
    try:
        installed = json.loads(hooks.read_text())
        text = config.read_text()
    except (OSError, ValueError) as exc:
        return {'state': 'not_measured', 'reason': type(exc).__name__}
    entry = str(entry or home/'.local/share/jev/bin/jev-hook')
    ours, per_hook = [], {}
    for event, groups in (installed.get('hooks') or {}).items():
        if not isinstance(groups, list) or event not in CODEX_EVENT_KEYS:
            continue
        for i, group in enumerate(groups):
            if not isinstance(group, dict):
                continue
            for j, hook in enumerate(group.get('hooks') or []):
                command = str(hook.get('command', '')) if isinstance(hook, dict) else ''
                if entry not in command and not (host and f'releases/{sha}' in command):
                    continue
                ours.append(event)
                body = _codex_state_block(text, f'{hooks}:{CODEX_EVENT_KEYS[event]}:{i}:{j}')
                stored = re.search(r'^trusted_hash\s*=\s*"([^"]+)"', body or '', re.M)
                if body is not None and re.search(r'^enabled\s*=\s*false', body, re.M):
                    status = 'disabled'
                elif not stored:
                    status = 'untrusted'
                elif stored.group(1) == codex_hook_hash(event, group, hook):
                    status = 'trusted'
                else:
                    status = 'modified'
                per_hook.setdefault(status, []).append(event)
    if not ours:
        return {'state': 'not_measured', 'reason': 'no Jev hooks for this release', 'hooks_file': str(hooks)}
    pending = sorted({e for s, events in per_hook.items() if s != 'trusted' for e in events})
    out = {'state': 'untrusted' if pending else 'trusted',
           'installed': sorted(set(ours)), 'pending': pending}
    for status in ('modified', 'untrusted', 'disabled'):
        if per_hook.get(status):
            out[status] = sorted(set(per_hook[status]))
    return out


def _is_jev_codex_command(command, entry, event):
    """True only for exactly `<python> <entry> codex <event>`.

    A substring test would hand trust to `evil; <entry> codex X`: any other
    installer writing into hooks.json could smuggle a command in by naming ours.
    """
    import shlex
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    return (len(words) == 4 and Path(words[0]).name.startswith('python')
            and words[1:] == [entry, 'codex', event])


def codex_trust_own_hooks(home=None, *, hooks=None, entry=None):
    """Re-grant Codex trust to Jev's own hooks; returns the keys it wrote.

    Codex keys trust by position (`<file>:<event>:<i>:<j>`), so another tool
    inserting its hooks ahead of ours moves them to keys whose stored hash is
    someone else's, and Codex skips them without a word. Measured on a consumer host
    2026-09-23: an Orca relay reconnect rewrote hooks.json, and the Jev floor
    stopped running in Codex an hour after a clean "Trust all". This writes
    what "Trust all" would, for Jev's exact command only. A hook the operator
    set to `enabled = false` stays refused. config.toml is replaced atomically
    and the previous one kept as config.toml.pre-jev-trust.

    `hooks` and `entry` select a project install's hooks file and hook script,
    as in `codex_hook_trust`; only an explicit `jev trust` passes them.
    """
    home = Path(home or Path.home())
    config = home/'.codex/config.toml'
    hooks = Path(hooks) if hooks is not None else home/'.codex/hooks.json'
    if not config.is_file() or not hooks.is_file():
        return []
    installed = json.loads(hooks.read_text())
    text = config.read_text()
    entry = str(entry or home/'.local/share/jev/bin/jev-hook')
    written = []
    for event, groups in (installed.get('hooks') or {}).items():
        if not isinstance(groups, list) or event not in CODEX_EVENT_KEYS:
            continue
        for i, group in enumerate(groups):
            if not isinstance(group, dict):
                continue
            for j, hook in enumerate(group.get('hooks') or []):
                if not isinstance(hook, dict) or not _is_jev_codex_command(str(hook.get('command', '')), entry, event):
                    continue
                key = f'{hooks}:{CODEX_EVENT_KEYS[event]}:{i}:{j}'
                digest = codex_hook_hash(event, group, hook)
                body = _codex_state_block(text, key)
                if body is None:
                    text = text.rstrip('\n') + f'\n\n[hooks.state."{key}"]\ntrusted_hash = "{digest}"\n'
                elif re.search(r'^enabled\s*=\s*false', body, re.M):
                    continue
                else:
                    stored = re.search(r'^trusted_hash\s*=\s*"([^"]+)"', body, re.M)
                    if stored and stored.group(1) == digest:
                        continue
                    new = (re.sub(r'^trusted_hash\s*=.*$', f'trusted_hash = "{digest}"', body, count=1, flags=re.M)
                           if stored else f'trusted_hash = "{digest}"\n' + body)
                    head = f'[hooks.state."{key}"]\n'
                    at = text.index(head + body)
                    text = text[:at] + head + new + text[at + len(head + body):]
                written.append(key)
    if written:
        shutil.copy2(config, config.with_name('config.toml.pre-jev-trust'))
        tmp = config.with_name('.config.toml.jev-trust')
        tmp.write_text(text)
        os.chmod(tmp, config.stat().st_mode & 0o777)
        tmp.replace(config)
    return written


#: What the installers register per client (jev_host_install.EVENTS; a test
#: keeps the two equal -- the host runtime does not ship the installer).
REGISTERED_EVENTS = {
    'claude': ('UserPromptSubmit', 'PreToolUse', 'PostToolUse'),
    'codex': ('UserPromptSubmit', 'PreToolUse', 'PostToolUse'),
    'cursor': ('beforeSubmitPrompt', 'beforeShellExecution', 'postToolUse'),
}
CLIENTS = ('claude', 'codex', 'cursor')
PROJECT_HOOK_FILES = {'claude': '.claude/settings.local.json', 'codex': '.codex/hooks.json',
                      'cursor': '.cursor/hooks.json'}
HOST_HOOK_FILES = {'claude': '.claude/settings.json', 'codex': '.codex/hooks.json',
                   'cursor': '.cursor/hooks.json'}


def _names_our_hook(command, entries, client, event):
    """`<interpreter> <one of entries> <client> <event>`, the form the installers write."""
    import shlex
    try:
        words = shlex.split(str(command))
    except ValueError:
        return False
    return (len(words) == 4 and Path(words[0]).name.startswith('python') and words[1] in entries
            and words[2:] == [client, event])


def registration_findings(clients, hook_files, entries):
    """Findings for every selected client whose Jev hook file or entry is gone.

    The installer is the only writer of these entries, so a missing one means
    somebody removed it -- and the floor then silently does not run in that
    client. `findings: []` after a hand-deleted `.cursor/hooks.json` read as
    healthy.
    """
    findings = []
    for client in clients:
        path = Path(hook_files[client])
        if not path.is_file():
            findings.append(f'{client}: Jev hook file missing ({path}); rerun the installer to register it')
            continue
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            findings.append(f'{client}: Jev hook file unreadable ({path})')
            continue
        hooks = data.get('hooks') if isinstance(data, dict) else None
        hooks = hooks if isinstance(hooks, dict) else {}
        missing = []
        for event in REGISTERED_EVENTS[client]:
            commands = []
            for entry in hooks.get(event) or []:
                if not isinstance(entry, dict):
                    continue
                if client == 'cursor':
                    commands.append(entry.get('command', ''))
                else:
                    commands += [h.get('command', '') for h in entry.get('hooks') or [] if isinstance(h, dict)]
            if not any(_names_our_hook(c, entries, client, event) for c in commands):
                missing.append(event)
        if missing:
            findings.append(f'{client}: Jev hook not registered for {", ".join(missing)} in {path}; '
                            'rerun the installer to register it')
    return findings


def hook_liveness(ledgers, clients, selected, telemetry_enabled=True):
    """Per client: whether the ledger holds hook deliveries from it.

    A `hook_delivery` record is written by the hook itself after the client
    ran it, so it is the one signal that the client executes the hooks -- not
    that they are installed or that the client lists them as active. Absence
    is `not_measured`, never a failure: a client that was not used since the
    install has delivered nothing either.
    """
    seen = {}
    for path in ledgers:
        path = Path(path)
        if path.is_symlink() or not path.is_file():
            continue
        try:
            with path.open(errors='replace') as stream:
                for line in stream:
                    try:
                        record = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(record, dict) or record.get('event') != 'hook_delivery':
                        continue
                    data = record.get('data') if isinstance(record.get('data'), dict) else {}
                    context = record.get('hook_context') if isinstance(record.get('hook_context'), dict) else {}
                    client = data.get('client') or context.get('client')
                    if client not in CLIENTS:
                        continue
                    item = seen.setdefault(client, {'deliveries': 0, 'last': 0.0, 'events': set()})
                    item['deliveries'] += 1
                    if isinstance(record.get('ts'), (int, float)):
                        item['last'] = max(item['last'], float(record['ts']))
                    event = data.get('native_event') or context.get('native_event')
                    if isinstance(event, str):
                        item['events'].add(event)
        except OSError:
            continue
    out = {}
    for client in clients:
        if client in seen:
            import datetime
            item = seen[client]
            out[client] = {'state': 'live', 'deliveries': item['deliveries'],
                           'events': sorted(item['events']),
                           'last_delivery': datetime.datetime.fromtimestamp(
                               item['last'], datetime.timezone.utc).isoformat(timespec='seconds')}
        elif client not in selected:
            out[client] = {'state': 'not_measured', 'reason': 'no Jev hooks installed for this client'}
        elif not telemetry_enabled:
            out[client] = {'state': 'not_measured', 'reason': 'telemetry disabled; no delivery records'}
        else:
            out[client] = {'state': 'not_measured', 'reason': 'no hook deliveries recorded yet'}
    return out


def trust_message(written, trust, host_mode):
    """What `jev trust` did, in words that match what `jev doctor` reports.

    It used to print "Codex already trusts every Jev hook (or has none
    installed)" whenever it wrote nothing -- also for a project whose hooks
    Codex had never reviewed, while doctor said not_measured.
    """
    if written:
        return f'Jev: Codex trust re-granted to {len(written)} Jev hook(s)'
    if trust['state'] == 'trusted':
        return 'Jev: Codex already trusts every Jev hook'
    reason = str(trust.get('reason', ''))
    if reason == 'no Codex hook configuration' or reason.startswith('no Jev hooks'):
        return 'Jev: no Jev hooks are registered for Codex here; nothing to trust'
    if trust.get('disabled') and not trust.get('untrusted') and not trust.get('modified'):
        return ('Jev: the Jev hooks are disabled in Codex (/hooks); `jev trust` leaves that choice alone. '
                'Enable them in codex under /hooks')
    where = 'on this host' if host_mode else 'in the project'
    return ('Jev: Codex has not reviewed these ' + ('host' if host_mode else 'project') + ' hooks yet: '
            f'open codex {where} and choose \'Trust all and continue\'')


def scope_hooks(host_mode, root, runtime, manifest, home=None):
    """Where this scope's Jev hooks are registered and where they report.

    Returns the selected clients, their hook files, the hook scripts a
    registered command may name, and the ledgers and telemetry switch that
    decide whether a delivery could have been recorded.
    """
    home = Path(home or Path.home())
    if host_mode:
        selected = [c for c in manifest.get('clients') or CLIENTS if c in CLIENTS]
        files = {c: home/rel for c, rel in HOST_HOOK_FILES.items()}
        entries = (str(home/'.local/share/jev/bin/jev-hook'), str(Path(runtime)/'scripts/jev_hook.py'))
        state = Path(manifest.get('state_dir') or home/'.local/state/jev')
        ledgers = sorted(state.glob('projects/*/sessions/*/ledger.jsonl'))
        config = Path(manifest['config']) if manifest.get('config') else None
    else:
        registered = manifest.get('with_jev') and not manifest.get('host_jev')
        selected = [c for c in manifest.get('clients') or CLIENTS if c in CLIENTS] if registered else []
        files = {c: Path(root)/rel for c, rel in PROJECT_HOOK_FILES.items()}
        entries = (str(Path(runtime)/'scripts/jev_hook.py'),)
        ledgers = [Path(runtime)/'state/jev/ledger.jsonl']
        config = Path(runtime)/'jev-config.json'
    try:
        telemetry = json.loads(config.read_text()).get('telemetry') or {} if config else {}
        enabled = bool(telemetry.get('enabled', True))
    except (OSError, ValueError, AttributeError):
        enabled = True
    return {'selected': selected, 'files': files, 'entries': entries, 'ledgers': ledgers,
            'telemetry_enabled': enabled, 'config': config}


def main():
    a, extra = parse()
    installed = Path(__file__).resolve().parent.parent
    host_mode = (installed/'host-installation.json').is_file()
    try:
        if not host_mode:
            root = project_root()
            project_manifest = json.loads((root/'.datarim-runtime/installation.json').read_text())
            if project_manifest.get('host_jev'):
                from jev_hook import host_runtime
                installed = host_runtime()
                host_mode = True
        if host_mode:
            from jev_hook import environment
            env, root = environment({'cwd': str(Path.cwd())}, runtime=installed)
            os.environ.clear()
            os.environ.update(env)
            runtime = installed
        else:
            root = project_root()
            runtime = activate(root)
        os.environ.pop('TYPESAFE_API_KEY', None)
    except (ScopeError, OSError, ValueError) as exc:
        print(f'jev: {exc}', file=sys.stderr)
        return 2
    manifest = json.loads((runtime/('host-installation.json' if host_mode else 'installation.json')).read_text())
    plugin = runtime/'plugins/dr-jev-control/scripts'
    sys.path.insert(0, str(plugin))
    state = Path(os.environ['JEV_HOST_STATE']) if host_mode else runtime/'state/jev'
    if a.task in ('on', 'off'):
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        flag = state/'DISABLED'
        if a.task == 'off':
            flag.touch(mode=0o600)
        else:
            flag.unlink(missing_ok=True)
        print('Jev '+a.task+(' for this host' if host_mode else ' for this project'))
        return 0
    if a.task == 'permissions':
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        flag = state/'FULL_PERMISSIONS'
        if a.setting == 'full':
            flag.touch(mode=0o600)
        elif a.setting == 'ask':
            flag.unlink(missing_ok=True)
        elif a.setting is not None:
            print('jev: permissions takes full or ask', file=sys.stderr)
            return 2
        where = 'this host' if host_mode else 'this project'
        print(f'Jev launches on {where}: '+('full permissions (clients do not ask)' if full_permissions(state)
                                          else 'clients ask for permission as usual'))
        return 0
    scope = scope_hooks(host_mode, root, runtime, manifest)
    # A project install's Codex hooks live in the project; the host's in ~/.codex.
    codex_target = {} if host_mode else {'hooks': scope['files']['codex'], 'entry': scope['entries'][0]}
    if a.task == 'trust':
        written = codex_trust_own_hooks(**codex_target)
        trust = codex_hook_trust(manifest['source_sha'], **codex_target)
        print(trust_message(written, trust, host_mode))
        print('codex_hook_trust:', trust['state'])
        return 0 if written or trust['state'] == 'trusted' or trust.get('reason') == 'no Codex hook configuration' \
            or str(trust.get('reason', '')).startswith('no Jev hooks') else 1
    if a.task == 'doctor':
        import subprocess
        findings = []
        versions = {}
        for agent in ([a.agent] if a.agent else ['claude', 'codex', 'cursor']):
            exe = binary(agent)
            if not exe:
                findings.append(agent+': executable missing')
                continue
            result = subprocess.run([exe, '--version'], capture_output=True, text=True, timeout=15)
            versions[agent] = result.stdout.strip()
            if result.returncode:
                findings.append(agent+': version probe failed')
            if agent == 'claude':
                match = re.search(r'(\d+)\.(\d+)\.(\d+)', result.stdout)
                if not match or tuple(map(int, match.groups())) < (2, 1, 277):
                    findings.append('claude: native AGENTS requires >=2.1.277')
        key = Path(os.environ['TYPESAFE_API_KEY_FILE'])
        key_ready = key.is_file() and bool(key.stat().st_size)
        report = {'project': str(root), 'scope': 'host' if host_mode else 'project',
                  'datarim_enabled': datarim_enabled(root),
                  'versions': versions, 'findings': findings,
                  'key_ready': key_ready,
                  'native_agents_live': hook_liveness(scope['ledgers'], [a.agent] if a.agent else list(CLIENTS),
                                                      scope['selected'], scope['telemetry_enabled']),
                  'api': 'not_measured', 'source_sha': manifest['source_sha'],
                  'permissions': 'full' if full_permissions(state) else 'ask'}
        doctored = [c for c in scope['selected'] if not a.agent or c == a.agent]
        report['hook_clients'] = scope['selected']
        # The settings file Jev reads now. The plugin's jev-control.json is only
        # the template installers copy; editing it changes nothing installed.
        live = scope['config']
        report['config_path'] = str(live) if live is not None and Path(live).is_file() else None
        findings += registration_findings(doctored, scope['files'], scope['entries'])
        if not host_mode:
            gone = sorted(name for name in manifest.get('files', {})
                          if name not in PROJECT_HOOK_FILES.values() and not (root/name).exists())
            if gone:
                findings.append(f'{len(gone)} managed file(s) missing (first: {gone[0]}); '
                                'rerun the installer to restore them')
        if (not a.agent or a.agent == 'codex') and not host_mode and 'codex' not in scope['selected']:
            report['codex_hook_trust'] = {'state': 'not_measured',
                                          'reason': 'no Jev hooks installed for Codex in this project'}
        elif not a.agent or a.agent == 'codex':
            trust = codex_hook_trust(manifest['source_sha'], **codex_target)
            report['codex_hook_trust'] = trust
            if trust['state'] == 'untrusted':
                why = ('changed since you trusted them' if trust.get('modified') else
                       'disabled in /hooks' if trust.get('disabled') and not trust.get('untrusted')
                       else 'not trusted yet')
                findings.append('codex: hooks installed but ' + why + ' (' +
                                ', '.join(trust['pending']) + '); run `jev trust` (or open `codex` '
                                'and choose "Trust all and continue"), or they never run')
        if a.api:
            from route import load_cfg
            from jev_client import diagnose
            report['api'] = diagnose(load_cfg()) if key_ready else {'ok': False, 'reason': 'key missing'}
        print(json.dumps(report, indent=2))
        return 1 if findings or (a.api and not report['api'].get('api', {}).get('ok')) else 0
    if a.task == 'stats':
        if host_mode:
            os.environ['JEV_STATS_ROOT'] = str(state)
        os.execv(sys.executable, [sys.executable, str(plugin/'cli_report.py'), 'stats'])
    if not a.agent:
        print('jev: select --agent=codex, --agent=claude, or --agent=cursor', file=sys.stderr)
        return 2
    exe = binary(a.agent)
    if not exe:
        print(f'jev: {a.agent} executable not found', file=sys.stderr)
        return 127
    os.environ[a.agent.upper()+'_BIN'] = exe
    if full_permissions(state):
        added = permission_flags(a.agent, extra)
        if added:
            extra = added + extra
            if not a.dry_run:
                print('Jev: full permissions ('+' '.join(added)+'); `jev permissions ask` turns this off',
                      file=sys.stderr)
    if a.dry_run:
        print(json.dumps({'agent': a.agent, 'binary': exe, 'project': str(root),
                          'scope': 'host' if host_mode else 'project',
                          'datarim_enabled': datarim_enabled(root),
                          'live': a.live, 'network_calls': 0, 'task_present': bool(a.task),
                          'permissions': 'full' if full_permissions(state) else 'ask',
                          'client_arguments': extra}))
        return 0
    if host_mode and a.agent == 'codex' and not os.environ.get('JEV_NO_AUTO_TRUST'):
        # Without trust the floor does not run in Codex, in any permission mode.
        try:
            written = codex_trust_own_hooks()
        except (OSError, ValueError) as exc:
            print(f'Jev: could not re-grant Codex hook trust ({type(exc).__name__}); run `jev doctor`',
                  file=sys.stderr)
        else:
            if written:
                print(f'Jev: re-granted Codex trust to {len(written)} Jev hook(s) that another tool had moved',
                      file=sys.stderr)
    if not manifest.get('with_jev'):
        a.no_route = True
    if a.no_route:
        os.environ['DATARIM_JEV_DISABLE'] = '1'
    if a.live:
        if not a.task:
            print('jev: --live requires a task', file=sys.stderr)
            return 2
        args = [sys.executable, str(plugin/'live_supervisor.py'), '--runtime', a.agent, '--mode', a.mode]
        for field in ('max_turns', 'max_seconds', 'continue_prompt', 'done_marker'):
            value = getattr(a, field)
            if value is not None:
                args += ['--'+field.replace('_', '-'), str(value)]
        args += [a.task, '--', *extra]
        os.execv(sys.executable, args)
    tier = None
    if a.task and not a.no_route and not a.model:
        try:
            from route import route, load_cfg
            decision = route(a.task, load_cfg(), a.mode)
            tier = decision['model']
            from prompt_cache import save
            os.environ['JEV_PROMPT_CACHE'] = str(save(a.task, decision))
            print(f'Jev recommends {tier} ({a.mode})', file=sys.stderr)
        except Exception as exc:
            # Do not print raw provider exceptions or response bodies.
            print(f'Jev unavailable ({type(exc).__name__}); using client defaults', file=sys.stderr)
    args = [exe]
    model = a.model
    effort = a.effort
    if a.agent == 'codex':
        if tier:
            from runtimes import codex_tier_settings
            routed_model, routed_effort = codex_tier_settings(tier)
            effort = effort or routed_effort
            model = model or os.environ.get('DATARIM_CODEX_MODEL_'+tier.upper()) or routed_model
            # Name what was applied, in Codex's own vocabulary. "Jev recommends
            # opus" describes a tier the operator will never see: the client's
            # status line reports `<model> <effort>`.
            applied = ' '.join(x for x in (model, effort) if x)
            print(f'Jev applied {tier} as {applied}', file=sys.stderr)
        elif a.resume and not a.no_route:
            # Resume does NOT inherit the resumed session's model or effort: it
            # re-resolves both from the config chain in force now. MEASURED on
            # codex-cli 0.155.1 -- a session created as gpt-5.6-sol/low came
            # back as gpt-6-astra/medium when resumed with no overrides, an
            # upgrade to the most expensive model that nothing announces.
            # Without a task there is nothing to classify, so say so rather
            # than let the silence read as "the old tier was kept".
            print('Jev: resuming without a task, so no tier was chosen; Codex '
                  'will re-resolve its model and effort from ~/.codex/config.toml, '
                  'not from the resumed session', file=sys.stderr)
        if a.print:
            args += ['exec']
            if a.resume:
                args += ['resume', a.resume]
        elif a.resume:
            args += ['resume', a.resume]
        if effort:
            args += ['-c', 'model_reasoning_effort='+effort]
    else:
        if a.agent == 'claude':
            model = model or tier
            if effort:
                args += ['--effort', effort]
        elif tier:
            model = model or os.environ.get('DATARIM_CURSOR_MODEL_'+tier.upper())
            if not model:
                print('Cursor tier mapping is not configured; keeping its default model', file=sys.stderr)
        if a.agent == 'cursor' and effort:
            print('jev: Cursor has no common effort flag; choose --model instead', file=sys.stderr)
            return 2
        if a.print:
            args += ['--print']
        if a.resume:
            args += ['--resume', a.resume]
    if model:
        args += ['--model', model]
    args += extra
    if a.task is not None:
        args.append(a.task)
    # The client/hook reads the scoped key file when needed; do not export a
    # Jev credential into arbitrary agent child processes.
    os.environ.pop('TYPESAFE_API_KEY', None)
    os.execv(exe, args)


if __name__ == '__main__':
    raise SystemExit(main())

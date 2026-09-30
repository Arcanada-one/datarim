#!/usr/bin/env python3
import json,os,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
# The safety floor is imported FIRST and on its own: it has no dependency
# beyond the standard library, so an import failure anywhere in the advisory
# stack (jev_client, route) must not be able to take the guard down with it.
from safety_floor import destructive_reason, _split

# The advisory-layer imports are wrapped so a broken control plane degrades to
# "floor only" rather than "no hook at all". They stay module-level names so
# they remain patchable by tests.
try:
    from jev_client import evaluate,provenance
    from route import load_cfg,log
except Exception:  # pragma: no cover - exercised by the degraded-import test
    evaluate=load_cfg=log=provenance=None

# These are cost signals, not an authorization parser. In particular, the
# executor may already be root: neither a missing `sudo` nor the hook's uid
# proves that an installation script is an ordinary local test.
_PRIVILEGED_PATH = re.compile(
    r"\bsudoers(?:\.d)?\b|(?:^|/)systemd(?:/|[\s;\"']|$)|/(?:etc|usr/local|var/lib)(?:/|[\s;\"']|$)", re.I)
_INSTALL_SIGNAL = re.compile(
    r'''(?:^|[/\s"'])(?:bootstrap|install|setup|provision|deploy)(?=[/_.\s"'-]|$)''', re.I)
_RISK_COMMAND = re.compile(
    r'\b(rm|mv|chmod|chown|sudo|doas|ssh|scp|rsync|curl|wget|kubectl|helm|terraform|'
    r'ansible|docker|podman|systemctl|useradd|usermod|userdel|groupadd|visudo|crontab|'
    r'iptables|ip6tables|nft|npm\s+publish|git\s+(push|reset|clean|checkout|'
    r'switch|rebase|merge)|gh\s+|aws\s+|gcloud\s+|az\s+|psql|mysql|redis-cli)\b|sed\s+-i', re.I)
# Skip quoted/escaped literal bytes and standalone descriptor placeholders.
# An attached suffix (<input>output) is real shell syntax, not a placeholder.
# Targets are inspected separately: fd duplication and exact /dev/null are not
# output-file writes; neighboring redirects still need their own inspection.
_OUTPUT_REDIRECT = re.compile(
    r"'[^']*'|\"(?:\\.|[^\"\\])*\"|\\.|(?<!\S)<[A-Za-z_][\w.-]*>(?=\s*$)|(?P<write>>{1,2}\|?)")
_DISCARD_TARGET = re.compile(r'''\s*(?:/dev/null|'/dev/null'|"/dev/null"|&(?:[0-9]+|-))(?=$|[\s;&|<>])''')
_INLINE_CODE = re.compile(r'''(?<!\w)-(?:[a-z]*c|e(?=[\s'"]|$))|--(?:command|eval|split-string)\b|(?<!\w)-S|\beval\b|<<|\$\(|`''')
_SCRIPT_SUFFIX = re.compile(r'\.(?:sh|bash|zsh|py|js|mjs|cjs|ts|rb|pl)(?:$|[<>])', re.I)
_PRODUCTION_SIGNAL = re.compile(r'\b(?:DATABASE_URL|PGHOST|NODE_ENV\s*=\s*production)\b')
_CREDENTIAL_OPTION = re.compile(
    r'''(?<!\w)--?(?:api[-_]?key|password|passwd|token|secret|client[-_]?secret|access[-_]?key|credential|authorization)(?=[=\s'"]|$)''', re.I)


def _ansi_quotes(command):
    """Decode ANSI-C quoted words as data, never shell execution/expansion."""
    command = command.replace('\\\n', '')
    def decode(match):
        body = match.group(1)
        def escape(m):
            value = m.group(1)
            if value.startswith(('x', 'u', 'U')):
                return chr(int(value[1:], 16))
            if value[0] in '01234567':
                return chr(int(value, 8))
            return {'n': '\n', 'r': '\r', 't': '\t'}.get(value, value)
        try:
            body = re.sub(r'\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|[0-7]{1,3}|.)', escape, body)
        except (ValueError, OverflowError):
            return '$__JEV_UNKNOWN_ANSI__'
        # Re-quote decoded bytes for shlex, preserving them as a single word.
        return "'" + body.replace("'", "'\\''") + "'"
    return re.sub(r"\$'((?:\\.|[^'\\])*)'", decode, command)


def _execution_segments(command):
    """Split shell control punctuation outside quotes; never execute or expand."""
    command = command.replace('\\\n', '')
    start, quote, escaped = 0, None, False
    for index, char in enumerate(command):
        if escaped:
            escaped = False
            continue
        if char == '\\' and quote != "'":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in ('"', "'"):
            quote = char
        elif char in ';|&\n()':
            yield command[start:index]
            start = index + 1
    yield command[start:]


def _risk_argv(segment):
    argv = _split(_ansi_quotes(segment))
    while argv:
        previous = argv
        while argv and argv[0] in ('if', 'then', 'elif', 'else', 'do', 'while', 'until', '!', '{', '}'):
            argv = argv[1:]
        while argv and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', argv[0]):
            argv = argv[1:]
        if not argv:
            break
        name = argv[0].rsplit('/', 1)[-1]
        if name == 'eval' or (name == 'env' and any(x == '-S' or x.startswith(('--split-string', '-S')) for x in argv[1:])):
            return ['$__JEV_UNKNOWN_WRAPPER__']
        if name in ('sudo', 'doas'):
            return argv  # Privilege escalation itself needs advice.
        if name in ('command', 'nice', 'nohup', 'time', 'eval', 'exec', 'env'):
            argv = argv[1:]
            value_flags = {'-n'} if name == 'nice' else {'-u', '--unset', '-C', '--chdir'} if name == 'env' else {'-o', '--output', '-f', '--format'} if name == 'time' else set()
            while argv:
                flag = argv[0]
                if flag == '--':
                    argv = argv[1:]
                    break
                if flag.startswith('-'):
                    argv = argv[2:] if flag in value_flags else argv[1:]
                elif name == 'env' and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', flag):
                    argv = argv[1:]
                else:
                    break
        elif name in ('timeout', 'setsid', 'stdbuf', 'npx'):
            if name == 'npx' and any(x in ('-c', '--call') or x.startswith('--call=') for x in argv[1:]):
                return ['$__JEV_UNKNOWN_WRAPPER__']
            argv = argv[1:]
            value_flags = {'-k', '--kill-after', '-s', '--signal'} if name == 'timeout' else {'-p', '--package', '-c'} if name == 'npx' else {'-i', '-o', '-e', '--input', '--output', '--error'} if name == 'stdbuf' else set()
            while argv and argv[0].startswith('-'):
                flag = argv[0]
                argv = argv[2:] if flag in value_flags else argv[1:]
            if name == 'timeout' and argv:
                argv = argv[1:]  # duration
        elif name in ('pnpm', 'npm', 'yarn', 'bun', 'uv', 'poetry') and len(argv) > 1 and argv[1] in ('exec', 'run'):
            if re.fullmatch(r'(?:deploy|release|sync|migrate)(?:[-:\w]*)', argv[2] if len(argv) > 2 else ''):
                break
            argv = argv[2:]
            if argv and argv[0] == '--':
                argv = argv[1:]
        if argv == previous:
            break
    return argv


def repository_execution_signal(command):
    """Inspect execution operands; filenames inside print/code/test args are data."""
    if len(command) > 16384:
        return True
    interpreters = {'bash', 'sh', 'dash', 'zsh', 'ksh', '.', 'source',
                    'python', 'python3', 'node', 'nodejs', 'ruby', 'perl', 'tsx'}
    for segment in _execution_segments(command):
        argv = _risk_argv(segment)
        if not argv:
            continue
        name = argv[0].rsplit('/', 1)[-1]
        if '$' in argv[0] or '`' in argv[0]:
            return True  # Unknown executable, never resolve host environment.
        if argv[0].startswith(('./', '../')) or _SCRIPT_SUFFIX.search(argv[0]):
            return True
        if name in interpreters:
            args = argv[1:]
            if name in ('python', 'python3') and len(args) >= 2 and args[:2] in (['-m', 'pytest'], ['-m', 'unittest']):
                continue  # Other segments and path/redirect signals still checked.
            if any(re.fullmatch(r'-[a-z]*c.*' if name in ('bash', 'sh', 'dash', 'zsh', 'ksh') else r'-[a-z]*c.*|-[a-z]*e.*', arg) for arg in args):
                continue  # Inline text is inspected separately, not a script path.
            if any(not arg.startswith('-') for arg in args):
                return True  # Includes extensionless shell scripts and modules.
        if name in ('make', 'pnpm', 'npm', 'yarn', 'bun') and any(
                re.fullmatch(r'(?:deploy|release|sync|migrate)(?:[-:\w]*)', arg) for arg in argv[1:]):
            return True
        if name == 'arcana' and len(argv) > 1 and argv[1] in ('login', 'run'):
            return True
    return False


def _readonly_substitutions(command):
    """Remove only bounded, simple substitutions of known read-only commands.

    Nested/ambiguous expansions, options that execute helpers and unknown tools
    remain opaque and require advice. This is a cost exemption, not authority.
    """
    def substitute(match):
        content = match.group(1)
        # Only ordinary parameter reads are data; exotic/indirect expansions
        # remain unknown. Redirection inside outer quotes must still be seen.
        ordinary = re.sub(r'\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\}', '', content)
        normalized_content = ' '.join(_split(_ansi_quotes(content)))
        if '$' in ordinary or (('<' in content) and ('$' in content or '/dev/tcp/' in normalized_content or '/dev/udp/' in normalized_content)) or any(m.lastgroup == 'write' and not _DISCARD_TARGET.match(content, m.end())
                                  for m in _OUTPUT_REDIRECT.finditer(content)):
            return match.group(0)
        stages = list(_execution_segments(content))
        safe = bool(stages)
        for stage in stages:
            argv = _split(_ansi_quotes(stage))
            if not argv:
                safe = False
                break
            name = argv[0].rsplit('/', 1)[-1]
            if argv[0] not in (name, '/bin/'+name, '/usr/bin/'+name):
                return match.group(0)  # Unknown executable identity or repository path.
            readonly = (name == 'git' and len(argv) > 1 and argv[1] in
                        ('rev-parse', 'status') and
                        not any(x.startswith(('--ext-diff', '--textconv', '--exec')) for x in argv))
            readonly = readonly or (name in ('date', 'pwd', 'basename', 'dirname') and
                                    not any(x.startswith(('-s', '--set', '-f', '--file')) or (name == 'date' and '$' in x) for x in argv[1:]))
            readonly = readonly or name in ('grep', 'cut', 'tr', 'stat', 'head', 'tail', 'wc')
            safe = safe and readonly
        prefix = re.split(r'[;&|\n]', command[:match.start()])[-1].lstrip()
        data_position = bool(re.match(r'^(?:echo|printf)\s', prefix) or
                             re.search(r'(?:^|\s)[A-Za-z_][A-Za-z0-9_]*=[^\s]*$', prefix))
        return '' if safe and data_position else match.group(0)
    return re.sub(r'\$\(([^()`;&\n]*)\)', substitute, command)


def shell_risk_signal(command):
    """Check executed argv plus independent paths, environment and redirects."""
    if len(command) > 16384:
        return True
    reduced = _readonly_substitutions(command)
    normalized = ' '.join(_split(_ansi_quotes(command)))
    if '__JEV_UNKNOWN_' in normalized:
        return True
    if (_PRIVILEGED_PATH.search(normalized) or _PRODUCTION_SIGNAL.search(normalized)
            or repository_execution_signal(reduced) or '$(' in reduced or '`' in reduced):
        return True
    for segment in _execution_segments(reduced):
        argv = _risk_argv(segment)
        if not argv:
            continue
        name = argv[0].rsplit('/', 1)[-1]
        # Risk words in printf/echo/git-log arguments are not executable names.
        executable = ' '.join([name, *argv[1:]])
        if _RISK_COMMAND.match(executable) or _INSTALL_SIGNAL.match(name):
            return True
        if name in ('bash', 'sh', 'dash', 'zsh', 'ksh') and any(re.match(r'-[a-z]*c', x) for x in argv[1:]):
            return True
        if name in ('python', 'python3', 'node', 'ruby', 'perl') and any(re.match(r'-[a-z]*[ce]', x) for x in argv[1:]) and _RISK_COMMAND.search(executable):
            return True
    return any(match.lastgroup == 'write' and not _DISCARD_TARGET.match(command, match.end())
               for match in _OUTPUT_REDIRECT.finditer(command))


def descriptor_state(descriptor):
    """Omit oversized fields whole, then scrub before bounding the JSON.

    Do not truncate raw secret-bearing text into fragments. Whole-field omission
    also bounds work for the ledger's regex scrubber on huge unbroken strings.
    """
    from ledger import _scrub
    bounded = dict(descriptor)
    for key, value in descriptor.items():
        if isinstance(value, str) and len(value) > 4096:
            bounded[key] = '[oversized field omitted]'
            bounded['descriptor_truncated'] = True
    clean = _scrub(bounded)
    state = json.dumps(clean, ensure_ascii=False)
    while len(state) > 12000:
        clean['descriptor_truncated'] = True
        key = max((key for key in clean if isinstance(clean[key], str)),
                  key=lambda key: len(clean[key]))
        value = clean[key]
        quarter = len(value) // 4
        clean[key] = value[:quarter] + ' ...[truncated]... ' + value[-quarter:]
        state = json.dumps(clean, ensure_ascii=False)
    return state


def main():
    try:p=json.load(sys.stdin)
    except Exception:return 0
    # Valid JSON that is not an object (null, a list, a bare scalar) parses
    # fine and then fails at .get(). A hook must never exit non-zero: that is
    # the fail-open contract, and a traceback here would surface as a broken
    # hook in the host CLI.
    if not isinstance(p,dict):return 0
    tool=str(p.get('tool_name','')); inp=p.get('tool_input',{})

    # Hard local floor FIRST, before any config is consulted.
    # It is deterministic and local, so it must not depend on the control
    # plane's state: disabling Jev, or a corrupt config, tunes the ADVISORY
    # layer off and must never silently remove a destructive-command guard.
    # (Ordering regression found 2026-09-21: with the config check first,
    # DATARIM_JEV_DISABLE=1 let a recursive root delete through unblocked.)
    # Matching lives in safety_floor.py and runs on a normalised argv, because
    # literal-spelling patterns missed trivial variants -- see that module.
    shell_tool = tool.lower() in ('bash', 'shell', 'exec_command')
    cmd=str(inp.get('cmd', inp.get('command',''))) if shell_tool and isinstance(inp,dict) else ''
    reason=destructive_reason(cmd)
    if reason:
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":f"Jev deterministic safety floor blocked a destructive command ({reason})."}}));return 0

    # Advisory layer. Absent (import failed) means the floor above has already
    # had its say and there is nothing further to add.
    if load_cfg is None or evaluate is None:return 0
    cfg=load_cfg()
    if not cfg.get('hooks',{}).get('pretool_risk',True):return 0
    # Cost guard: only ask Jev about calls with a plausible mutation/external-risk signal.
    # Ordinary reads, known test-runner invocations and normal source edits stay
    # cheap; an arbitrary repository script can hide privileged/external writes.
    workdir = str(inp.get('workdir', inp.get('cwd', p.get('cwd', '')))) if isinstance(inp, dict) else ''
    privileged_workdir = bool(_PRIVILEGED_PATH.search(workdir))
    low=(tool.lower() in ('read','grep','glob','view')
         or (shell_tool and not privileged_workdir and not shell_risk_signal(cmd)))
    path=str(inp.get('file_path',inp.get('path',''))) if isinstance(inp,dict) else ''
    if tool.lower() == 'apply_patch' and isinstance(inp, dict):
        # Codex supplies patch text under `command`. Only path headers leave the
        # hook; source contents and added credential values remain local.
        patch_text = inp.get('command', inp.get('patch', ''))
        if isinstance(patch_text, str):
            path = '\n'.join(re.findall(r'^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$',
                                       patch_text, re.M))
    ordinary_edit=(tool.lower() in ('write','edit','multiedit','apply_patch')
                   and not privileged_workdir
                   and not _PRIVILEGED_PATH.search(path)
                   and not re.search(r'(\.env|secret|credential|production|prod\.|migration|deploy|settings\.json)',path,re.I))
    if low or ordinary_edit:return 0
    if tool.lower() == 'apply_patch':
        # Inspect every header above, then prioritize privileged targets within
        # the bounded descriptor. A late Move to must not vanish behind 100
        # ordinary files before the model sees why evaluation was requested.
        paths = path.splitlines()
        path = '\n'.join(sorted(paths, key=lambda item: not bool(_PRIVILEGED_PATH.search(item)))[:100])
    # Classify the operation, never read files or transmit tool output/edit bodies.
    descriptor = {'tool': tool, 'path': path}
    if workdir:
        descriptor['workdir'] = workdir
    signals = []
    if _PRIVILEGED_PATH.search(cmd + '\n' + path) or privileged_workdir:
        signals.append('privileged_path_or_workdir')
    if shell_tool and _INSTALL_SIGNAL.search(cmd):
        signals.append('installation_or_deploy')
    if shell_tool and repository_execution_signal(cmd):
        signals.append('repository_script_or_opaque_execution')
    if shell_tool and _PRODUCTION_SIGNAL.search(cmd):
        signals.append('production_environment_or_database')
    if shell_tool:
        descriptor['command'] = cmd
        normalized = ' '.join(_split(_ansi_quotes(cmd))) if len(cmd) <= 16384 else ''
        credential_option = bool(_CREDENTIAL_OPTION.search(cmd) or _CREDENTIAL_OPTION.search(normalized))
        if _INLINE_CODE.search(cmd) or _INLINE_CODE.search(normalized) or credential_option or len(cmd) > 4096:
            # Inline programs / here-docs can contain literal file bodies.
            # Send the cost signals and path tokens, not that source text.
            oversized = len(cmd) > 4096
            omission = ('oversized_command_omitted' if oversized else
                        'credential_argument_omitted' if credential_option else 'inline_code_omitted')
            descriptor['command'] = '[' + omission.replace('_', ' ') + ']'
            # Never copy substrings from omitted source: a credential or file
            # body may itself look like a privileged path. Emit fixed categories
            # only, and no command-derived paths at all for credential options.
            if not credential_option:
                roots = ('/etc/sudoers.d', '/etc/sudoers', '/etc/systemd',
                         '/usr/lib/systemd', '/lib/systemd', '/run/systemd',
                         '/etc', '/usr/local', '/var/lib')
                descriptor['path'] = '\n'.join(root for root in roots if root in cmd)
            signals.append(omission)
            if oversized:
                descriptor['descriptor_truncated'] = True
    descriptor['risk_signals'] = signals
    s=descriptor_state(descriptor)
    q={"risky":{"type":"noul","instructions":"Is this proposed tool call destructive, irreversible, security-sensitive, secret-exposing, production-changing, externally mutating, or otherwise deserving explicit review before autonomous execution?"}}
    api=cfg.get('api',{})
    budget={"timeout_seconds":api.get('hook_timeout_seconds',4),"retries":api.get('hook_retries',0)}
    try:r=evaluate(s,q,cfg,budget=budget); risk=float(r['answers']['risky']['noul']); log(cfg,'pretool',s,{"risk":risk,"tool":tool,"usage":r.get('usage',{}),"provenance":provenance(r)})
    except Exception:return 0
    th=cfg.get('routing',{}).get('risk_thresholds',{}); enforce=cfg.get('hooks',{}).get('enforce_jev_denials',False)
    if enforce and risk>=float(th.get('deny_autonomous',.94)):
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":f"Jev risk gate={risk:.3f}; explicit review requested."}}))
    elif risk>=float(th.get('require_review',.78)):
        print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":f"Jev risk advisory: {risk:.3f}. Re-check scope, reversibility, secrets, external effects, and validation before executing."}}))
    return 0
if __name__=='__main__':raise SystemExit(main())

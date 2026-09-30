#!/usr/bin/env python3
import json,os,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
# The safety floor is imported FIRST and on its own: it has no dependency
# beyond the standard library, so an import failure anywhere in the advisory
# stack (jev_client, route) must not be able to take the guard down with it.
from safety_floor import destructive_reason

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
_PRIVILEGED_PATH = re.compile(r'\bsudoers(?:\.d)?\b|(?:^|/)systemd(?:/|$)', re.I)
_INSTALL_SIGNAL = re.compile(
    r'''(?:^|[/\s"'])(?:bootstrap|install|setup|provision|deploy)(?=[/_.\s"'-]|$)''', re.I)
_RISK_COMMAND = re.compile(
    r'\b(rm|mv|chmod|chown|sudo|ssh|scp|rsync|curl|wget|kubectl|helm|terraform|'
    r'ansible|docker|podman|systemctl|npm\s+publish|git\s+(push|reset|clean|checkout|'
    r'switch|rebase|merge)|gh\s+|aws\s+|gcloud\s+|az\s+|psql|mysql|redis-cli)\b|sed\s+-i', re.I)
# Skip quoted/escaped literal bytes and standalone descriptor placeholders.
# An attached suffix (<input>output) is real shell syntax, not a placeholder.
# Duplication (2>&1) is not an output-file write; &>file and >>file still are.
_OUTPUT_REDIRECT = re.compile(
    r"'[^']*'|\"(?:\\.|[^\"\\])*\"|\\.|(?<!\S)<[A-Za-z_][\w.-]*>(?=\s|$)|(?P<write>>)(?!&)")
_SHELL_CODE = re.compile(r'\b(?:bash|sh|dash|zsh|ksh)\s+(?:--?[\w=-]+\s+)*-[a-z]*c\b', re.I)
_INLINE_CODE = re.compile(r'''(?<!\w)-(?:[a-z]*c|e(?=[\s'"]|$))|--(?:command|eval)\b|<<|\$\(|`''')


def shell_risk_signal(command):
    """Route plausible privileged writes and opaque shell code to native risky.

    Shell expansions can execute inside double quotes. Conservatively evaluate
    those and shell -c payloads instead of interpreting them or opening scripts.
    Only the redirection signal skips placeholders; it cannot mask other risks.
    """
    if (_RISK_COMMAND.search(command) or _PRIVILEGED_PATH.search(command)
            or _INSTALL_SIGNAL.search(command) or _SHELL_CODE.search(command)
            or '$(' in command or '`' in command):
        return True
    return any(match.lastgroup == 'write' for match in _OUTPUT_REDIRECT.finditer(command))


def descriptor_state(descriptor):
    """Scrub before bounding fields; preserve valid JSON and both command ends."""
    from ledger import _scrub
    clean = _scrub(descriptor)
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
    # Ordinary reads, tests, grep, git diff/status/log, and normal source edits do not pay an API round-trip.
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
    if shell_tool:
        descriptor['command'] = cmd
        if _INLINE_CODE.search(cmd):
            # Inline programs / here-docs can contain literal file bodies.
            # Send the cost signals and path tokens, not that source text.
            descriptor['command'] = '[inline code omitted]'
            targets = re.findall(r'/[A-Za-z0-9_./@+-]+', cmd)
            descriptor['path'] = '\n'.join(target for target in targets
                                           if _PRIVILEGED_PATH.search(target))[:4000]
            signals.append('inline_code_omitted')
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

#!/usr/bin/env python3
"""Native hook schemas over the shared Jev advisory engine.

Host mode reads only the host-owned configuration beside its installed runtime.
Project policy is opt-in. The deterministic shell floor does not depend on
configuration, credentials, classification, or project discovery.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

RUNTIME = Path(__file__).resolve().parent.parent
ENGINE = RUNTIME / 'plugins/dr-jev-control/scripts'
sys.path.insert(0, str(ENGINE))
from safety_floor import destructive_reason

EVENTS = {
    'claude': {'UserPromptSubmit': 'UserPromptSubmit', 'PreToolUse': 'PreToolUse',
               'PostToolUse': 'PostToolUse'},
    'codex': {'UserPromptSubmit': 'UserPromptSubmit', 'PreToolUse': 'PreToolUse',
              'PostToolUse': 'PostToolUse'},
    'cursor': {'beforeSubmitPrompt': 'UserPromptSubmit', 'beforeShellExecution': 'PreToolUse',
               'postToolUse': 'PostToolUse', 'afterFileEdit': 'PostToolUse'},
}


def normalize(client, event, payload):
    canonical = EVENTS[client][event]
    out = dict(payload)
    out['hook_event_name'] = canonical
    out['jev_client'] = client
    out['jev_native_event'] = event
    if str(out.get('tool_name', '')).lower() == 'exec_command' and isinstance(out.get('tool_input'), dict):
        inp = out['tool_input']
        out['tool_input'] = dict(inp, command=inp.get('cmd', inp.get('command', '')))
    if client == 'cursor':
        out['session_id'] = payload.get('conversation_id')
        out['turn_id'] = payload.get('generation_id')
        if 'tool_output' in payload:
            out['tool_response'] = payload['tool_output']
    if client == 'cursor' and event == 'beforeShellExecution':
        out.update(tool_name='Bash', tool_input={'command': payload.get('command', '')})
    elif client == 'cursor' and event == 'afterFileEdit':
        out.update(tool_name='Edit', tool_input={'file_path': payload.get('file_path', '')})
    return canonical, out


def workdir(payload):
    """Cursor's global hook process cwd is its config directory, not the project."""
    value = payload.get('cwd')
    if isinstance(value, str) and value:
        return Path(value).resolve(strict=True)
    roots = payload.get('workspace_roots')
    if isinstance(roots, list) and len(roots) == 1 and isinstance(roots[0], str):
        return Path(roots[0]).resolve(strict=True)
    raise ValueError('No unambiguous event working directory')


def environment(payload, *, runtime=RUNTIME):
    from project_scope import project_root
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('DATARIM_') or key in ('TYPESAFE_API_KEY', 'TYPESAFE_API_KEY_FILE',
                                               'JEV_STATE_DIR', 'JEV_HOST_STATE', 'JEV_PROJECT_STATE',
                                               'JEV_EVENT_CONTEXT'):
            if key != 'DATARIM_JEV_DISABLE':
                env.pop(key, None)
    host = runtime / 'host-installation.json'
    cwd = workdir(payload)
    if host.is_file() and not host.is_symlink():
        if host.stat().st_mode & 0o077:
            raise ValueError('Host manifest must be private')
        metadata = json.loads(host.read_text())
        if metadata.get('schema') != 1 or metadata.get('runtime') != str(runtime.resolve()):
            raise ValueError('Host runtime identity mismatch')
        cfg = Path(metadata['config'])
        if cfg.is_symlink() or cfg.stat().st_mode & 0o077:
            raise ValueError('Host configuration must be private')
        settings = json.loads(cfg.read_text())
        env['DATARIM_JEV_CONFIG'] = str(cfg)
        env['TYPESAFE_API_KEY_FILE'] = metadata['key_file']
        env['JEV_HOST_STATE'] = metadata['state_dir']
        identity = hashlib.sha256(str(cwd).encode()).hexdigest()
        project_state = Path(metadata['state_dir']) / 'projects' / identity
        env['JEV_PROJECT_STATE'] = str(project_state)
        session = str(payload.get('session_id') or 'unidentified')
        env['JEV_STATE_DIR'] = str(project_state / 'sessions' / hashlib.sha256(session.encode()).hexdigest())
        # A project cannot redirect the host key or endpoint through its config.
        try:
            root = project_root(cwd)
            approved = settings.get('datarim_projects', [])
            if str(root) in approved:
                env['DATARIM_PROJECT_ROOT'] = str(root)
                env['DATARIM_ROOT'] = str(root / '.datarim-runtime')
        except (OSError, ValueError):
            pass
    else:
        root = project_root(cwd)
        if root / '.datarim-runtime' != runtime:
            raise ValueError('Hook belongs to another installation')
        env.update(DATARIM_PROJECT_ROOT=str(root), DATARIM_ROOT=str(runtime),
                   DATARIM_RUNTIME=str(runtime), DATARIM_JEV_CONFIG=str(runtime/'jev-config.json'),
                   TYPESAFE_API_KEY_FILE=str(root/'config/credentials/jev/api-key'),
                   JEV_STATE_DIR=str(runtime/'state/jev'))
    env['JEV_EVENT_CONTEXT'] = json.dumps({
        'client': payload.get('jev_client'), 'native_event': payload.get('jev_native_event'),
        'canonical_event': payload.get('hook_event_name'),
        'session_id': payload.get('session_id'), 'turn_id': payload.get('turn_id'),
        'cwd_sha256': hashlib.sha256(str(cwd).encode()).hexdigest(),
    })
    return env, cwd


def native_output(client, event, result):
    if client == 'codex':
        body = result.get('hookSpecificOutput', {})
        if body.get('permissionDecision') == 'ask':
            # Codex rejects `ask` and then continues the tool. Require a new,
            # explicitly reviewed invocation using the supported deny contract.
            result = dict(result, hookSpecificOutput=dict(body, permissionDecision='deny'))
    if client != 'cursor':
        return result
    body = result.get('hookSpecificOutput', {})
    advice = body.get('additionalContext', '')
    decision = body.get('permissionDecision')
    reason = body.get('permissionDecisionReason', '')
    if event == 'beforeSubmitPrompt':
        # Cursor has no context-injection field at this event. Classification
        # remains a ledger observation, not an applied instruction.
        if result.get('decision') == 'block':
            return {'continue': False, 'user_message': result.get('reason', 'Jev requested review')}
        return {'continue': True}
    if event == 'beforeShellExecution':
        out = {'permission': 'deny' if decision in ('deny', 'ask') else 'allow'}
        if reason:
            out['user_message'] = reason
        if advice or reason:
            out['agent_message'] = advice or reason
        return out
    if event == 'postToolUse' and advice:
        return {'additional_context': advice}
    return {}


def run(client, event, payload):
    canonical, normalized = normalize(client, event, payload)
    inp = normalized.get('tool_input', {})
    if canonical == 'PreToolUse' and str(normalized.get('tool_name', '')).lower() in ('bash', 'shell', 'exec_command'):
        command = inp.get('command', '') if isinstance(inp, dict) else ''
        reason = destructive_reason(command) if isinstance(command, str) else None
        if reason:
            return native_output(client, event, {'hookSpecificOutput': {
                'hookEventName': canonical, 'permissionDecision': 'deny',
                'permissionDecisionReason': 'Jev deterministic safety floor: ' + reason}})
    try:
        env, cwd = environment(normalized)
        script = {'UserPromptSubmit': 'hook_user_prompt.py', 'PreToolUse': 'hook_pre_tool.py',
                  'PostToolUse': 'hook_post_tool.py'}[canonical]
        child = subprocess.run([sys.executable, str(ENGINE / script)], input=json.dumps(normalized),
                               text=True, capture_output=True, cwd=cwd, env=env, timeout=6)
        result = json.loads(child.stdout) if child.returncode == 0 and child.stdout.strip() else {}
        return native_output(client, event, result)
    except (OSError, ValueError, KeyError, TypeError, ImportError, subprocess.TimeoutExpired):
        # Floor has already examined the command. Cursor requires valid JSON to
        # allow it when only the advisory service is unavailable.
        return native_output(client, event, {})


def main():
    try:
        client, event = sys.argv[1:]
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        result = run(client, event, payload)
        if result:
            print(json.dumps(result))
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        return 0
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

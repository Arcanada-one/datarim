#!/usr/bin/env python3
"""Jev dispatcher for Claude Code, Codex and Cursor; Datarim is opt-in."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from project_scope import ScopeError, activate, project_root


def parse(argv=None):
    alias = {'jevcodex': 'codex', 'jevclaude': 'claude', 'jevcursor': 'cursor'}.get(Path(sys.argv[0]).name)
    p = argparse.ArgumentParser(description=__doc__, epilog='Activate with: source .datarim-runtime/activate.sh. Client arguments follow --.')
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
    p.add_argument('task', nargs='?', help='Task, or doctor / stats / on / off')
    values = list(sys.argv[1:] if argv is None else argv)
    extra = []
    if '--' in values:
        split = values.index('--')
        values, extra = values[:split], values[split + 1:]
    a = p.parse_args(values)
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
    """
    try:
        manifest = root/'.datarim-runtime/installation.json'
        if not manifest.is_file() or manifest.is_symlink():
            return False
        data = json.loads(manifest.read_text())
        return data.get('schema') == 1 and data.get('project') == str(root)
    except (OSError, ValueError):
        return False


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
                  'key_ready': key_ready, 'native_agents_live': 'not_measured',
                  'api': 'not_measured', 'source_sha': manifest['source_sha']}
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
    if a.dry_run:
        print(json.dumps({'agent': a.agent, 'binary': exe, 'project': str(root),
                          'scope': 'host' if host_mode else 'project',
                          'datarim_enabled': datarim_enabled(root),
                          'live': a.live, 'network_calls': 0, 'task_present': bool(a.task)}))
        return 0
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
            from runtimes import CODEX_TIER_MAP
            _, routed_effort = CODEX_TIER_MAP.get(tier, (None, None))
            effort = effort or routed_effort
            model = model or os.environ.get('DATARIM_CODEX_MODEL_'+tier.upper())
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

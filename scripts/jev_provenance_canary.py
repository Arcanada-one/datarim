#!/usr/bin/env python3
"""Offline process canary: real supervisor/cache/hooks; synthetic provider and CLI.

Never invoke a model, install a host runtime, or open a listening socket.
"""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
sys.path.insert(0, str(ROOT/'plugins/dr-jev-control/scripts'))
sys.path.insert(0, str(ROOT/'plugins/dr-jev-control/tests'))
import jev_client
import jev_hook
import ledger
import live_supervisor
import prompt_cache
import route
from test_supervisor_e2e import cfg


def main():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        config = cfg(min_tokens_between_switches=0)
        config['api'].update(transport='curl', model='jev-latest')
        config['telemetry']['path'] = str(root/'ledger.jsonl')
        settings = root/'config.json'
        settings.write_text(json.dumps(config))
        executable = root/'fake-cli'
        # Reuse the repository's native fake CLI, never resolve a host binary.
        fake = ROOT/'plugins/dr-jev-control/tests/fake_codex.py'
        import shlex
        executable.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(fake)) + ' "$@"\n')
        executable.chmod(0o700)
        response = {'model': 'jev-1.13.0', 'answers': {
            'model_tier': {'choice': 'sonnet'},
            'needed_tier': {'choice': 'opus', 'confidence': .99},
            'is_stuck': {'noul': .95}, 'work_simplified': {'noul': 0},
            'needs_more_thinking': {'noul': 0}}}
        env = {'CODEX_BIN': str(executable), 'FAKE_CODEX_LOG': str(root/'calls.jsonl'),
               'JEV_STATE_DIR': str(root), 'DATARIM_JEV_CONFIG': str(settings)}
        inventory = {k: [] for k in ('skills', 'agents', 'commands', 'templates')}
        with mock.patch.dict(os.environ, env), mock.patch.object(jev_client, '_curl', side_effect=lambda *a: copy.deepcopy(response)), mock.patch.object(jev_client, 'read_key', return_value='synthetic'), mock.patch.object(jev_client, '_kill_switch_reason', return_value=None), mock.patch.object(route, 'kill_switch_reason', return_value=None), mock.patch.object(route, 'inventory', return_value=inventory), contextlib.redirect_stdout(io.StringIO()):
            decision = route.route('Synthetic review', config)
            live_supervisor.run('Synthetic review', cfg=config, mode='balanced', extra_args=[], quiet=True,
                                explain=False, max_turns=3, runtime='codex', continue_prompt='Continue synthetic work')
        reroutes = ledger.read_events(config, events={'live_reroute'})
        dispatched = ledger.read_events(config, events={'live_switch_dispatch'})
        queued = next(r['data']['verdict'] for r in reroutes if r['data']['verdict'].get('switch'))
        assert dispatched, 'missing linked process dispatch'
        launch = dispatched[0]['data']['verdict']
        assert queued['outcome'] == 'deferred' and not queued['applied']
        assert launch['outcome'] == 'dispatched' and not launch['applied']
        assert queued['evidence'] == launch['evidence']
        counts = ledger.stats(config)['switches']
        assert counts['applied'] == 0 and counts['dispatched'] == 1

        # Native wrapper actually spawns the hook. Cache avoids another request.
        # The wrapper's context is isolated; provider routing is disabled in
        # the hook config as a fallback against any cache regression making I/O.
        hook_cfg = dict(config, api=dict(config['api']), routing=dict(config['routing']))
        hook_cfg['api']['retries'] = 0
        hook_cfg['api']['base_url'] = 'invalid:offline-canary'
        settings.write_text(json.dumps(hook_cfg))
        for index, client in enumerate(('claude', 'codex', 'cursor')):
            delivery_id = f'{index + 1:032x}'
            context = json.dumps({'delivery_id': delivery_id, 'client': client})
            with mock.patch.dict(os.environ, env):
                cache = prompt_cache.save('Synthetic review', decision)
            child_env = dict(os.environ, **env, JEV_PROMPT_CACHE=str(cache), JEV_EVENT_CONTEXT=context,
                             TYPESAFE_API_KEY='', TYPESAFE_API_KEY_FILE=str(root/'absent-key'))
            event = 'beforeSubmitPrompt' if client == 'cursor' else 'UserPromptSubmit'
            with mock.patch.object(jev_hook, 'environment', return_value=(child_env, root)):
                output = jev_hook.run(client, event, {'prompt': 'Synthetic review'})
            rows = ledger.read_events(config)
            advice = next(r for r in reversed(rows) if r['event'] == 'routing_advice')
            delivery = next(r for r in reversed(rows) if r['event'] == 'hook_delivery')
            assert advice['hook_context']['delivery_id'] == delivery['data']['delivery_id'] == delivery_id
            assert advice['data']['evidence'] == decision['evidence']
            assert delivery['data']['applied'] == 'not_measured'
            assert delivery['data']['advice_emitted'] == (client != 'cursor')
            assert 'evidence' not in output  # native vendor wire contract unchanged
        print(json.dumps({'schema': 'JevProvenanceCanary/v1', 'result': 'PASS',
                          'provider_calls': 0, 'real_model_calls': 0, 'runtime': 'synthetic CLI subprocess',
                          'deferred_then_dispatched': True, 'applied_switches': counts['applied'],
                          'hook_clients': 3, 'cached_request_identity_preserved': True,
                          'cursor_unsupported_advice_not_counted': True}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

"""Native request -> real consumer -> ledger controls; no model or socket calls."""
import contextlib
import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

S = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(S))
import jev_client
import ledger
import live_supervisor
import route
from live_policy import SwitchGate
from test_supervisor_e2e import cfg

RESPONSE = {'model': 'jev-1.13.0', 'answers': {
    'needed_tier': {'choice': 'opus', 'confidence': .99},
    'is_stuck': {'noul': .95}, 'work_simplified': {'noul': 0},
    'needs_more_thinking': {'noul': 0}}}


class ConsumerProvenance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cfg = cfg(min_tokens_between_switches=0)
        self.cfg['telemetry']['path'] = str(Path(self.tmp.name) / 'events.jsonl')
        self.cfg['api'].update(transport='curl', model='jev-latest')
        for name, value in [('_kill_switch_reason', None), ('read_key', 'synthetic-key')]:
            patch = mock.patch.object(jev_client, name, return_value=value)
            patch.start(); self.addCleanup(patch.stop)
        patch = mock.patch.object(route, 'kill_switch_reason', return_value=None)
        patch.start(); self.addCleanup(patch.stop)

    def evaluate(self, response=None, state='private task', questions=None):
        with mock.patch.object(jev_client, '_curl', return_value=copy.deepcopy(RESPONSE if response is None else response)):
            return jev_client.evaluate(state, questions or {}, self.cfg)

    def reroute(self, ok, detail, *, deferred=False):
        runtime = mock.Mock(reports_usage=True, in_process_switch=not deferred, tiers=('haiku', 'sonnet', 'opus'))
        runtime.apply_tier.return_value = (ok, detail)
        gate = SwitchGate(self.cfg, 'balanced', 'sonnet', now=0)
        obs = live_supervisor.TurnObserver()
        with mock.patch.object(jev_client, '_curl', return_value=copy.deepcopy(RESPONSE)), contextlib.redirect_stdout(io.StringIO()) as stdout:
            verdict = live_supervisor._reroute(runtime, gate, obs, self.cfg, 3, False)
        return verdict, gate, stdout.getvalue()

    def test_timeout_is_uncertain_but_policy_gate_still_commits(self):
        v, gate, text = self.reroute(False, {'subtype': 'timeout'})
        self.assertFalse(v['applied'])
        self.assertEqual(v['outcome'], 'uncertain')
        self.assertEqual(gate.tier, 'opus')
        self.assertEqual(gate.switches, 1)
        self.assertIn('unconfirmed', text)
        self.assertNotIn('assuming applied', text)
        s = ledger.stats(self.cfg)
        self.assertEqual(s['switches']['applied'], 0)
        self.assertEqual(s['switches']['uncertain'], 1)

    def test_deferred_is_not_applied(self):
        v, gate, text = self.reroute(True, {'subtype': 'deferred_to_next_turn'}, deferred=True)
        self.assertFalse(v['applied'])
        self.assertEqual(v['outcome'], 'deferred')
        self.assertEqual(gate.tier, 'opus')
        self.assertIn('next turn', text)
        self.assertEqual(ledger.stats(self.cfg)['switches']['applied'], 0)

    def test_acknowledged_switch_carries_request_and_policy_link(self):
        v, _, _ = self.reroute(True, {'subtype': 'success'})
        self.assertTrue(v['applied'])
        self.assertEqual(v['confirmation'], 'runtime_control_ack')
        evidence = v['evidence']
        self.assertEqual(evidence['requested_model'], 'jev-latest')
        self.assertEqual(evidence['model'], 'jev-1.13.0')
        self.assertEqual(len(evidence['decision_id']), 32)
        for key in ('request_sha256', 'questions_sha256', 'policy_sha256', 'candidates_sha256', 'recommendation_sha256'):
            self.assertEqual(len(evidence[key]), 64, key)
        rows = ledger.read_events(self.cfg)
        self.assertEqual(rows[-1]['data']['verdict']['evidence'], evidence)
        self.assertEqual(ledger.stats(self.cfg)['switches']['applied'], 1)

    def test_refusal_never_advances_gate(self):
        v, gate, _ = self.reroute(False, {'subtype': 'error'})
        self.assertFalse(v['applied'])
        self.assertEqual(v['outcome'], 'refused')
        self.assertEqual(gate.switches, 0)

    def test_request_id_is_per_call_and_provider_cannot_forge_it(self):
        pa = jev_client.provenance(self.evaluate(dict(RESPONSE, _client={'decision_id': 'forged'})))
        pb = jev_client.provenance(self.evaluate())
        self.assertNotEqual(pa['decision_id'], pb['decision_id'])
        self.assertNotEqual(pa['decision_id'], 'forged')
        self.assertEqual(pa['request_sha256'], pb['request_sha256'])

    def test_request_digest_is_scrubbed_wire_and_questions_digest_tracks_candidates(self):
        import hashlib
        questions = {'pick': {'type': 'choice', 'criteria': {'one': 'First'}}}
        payload = jev_client._payload('secret_token=synthetic-private-value', questions, self.cfg['api'])
        p = jev_client.provenance(self.evaluate(state='secret_token=synthetic-private-value', questions=questions))
        self.assertEqual(p['request_sha256'], hashlib.sha256(payload).hexdigest())
        self.assertNotIn('synthetic-private-value', json.dumps(p))
        self.assertNotEqual(p['questions_sha256'], jev_client.provenance(self.evaluate())['questions_sha256'])

    def test_missing_or_alias_model_is_not_a_resolved_version(self):
        for model in (None, 'jev-latest', {'private': 'value'}, 'private/path', 'jev-1.13.0\nprivate'):
            with self.subTest(model=model):
                p = jev_client.provenance(self.evaluate(dict(RESPONSE, model=model)))
                self.assertEqual(p['resolved_model_status'], 'not_measured')
        self.assertEqual(jev_client.provenance(self.evaluate())['resolved_model_status'], 'observed')

    def test_historical_timeout_and_deferred_are_not_reclassified_as_applied(self):
        for data in ({'switch': True, 'applied': True, 'tier_uncertain': True},
                     {'switch': True, 'applied': True, 'deferred': True},
                     {'switch': True, 'applied': True}):
            ledger.log_event(self.cfg, 'live_reroute', '', {'verdict': data})
        s = ledger.stats(self.cfg)['switches']
        self.assertEqual(s['applied'], 0)
        self.assertEqual(s['uncertain'], 1)
        self.assertEqual(s['deferred'], 1)
        self.assertEqual(s['not_measured'], 1)

    def test_retry_keeps_identity_and_counts_attempts(self):
        self.cfg['api']['retries'] = 1
        with mock.patch.object(jev_client, '_curl', side_effect=[jev_client.JevError('TIMEOUT', 'synthetic'), copy.deepcopy(RESPONSE)]) as send, mock.patch.object(jev_client.time, 'sleep'):
            p = jev_client.provenance(jev_client.evaluate('task', {}, self.cfg))
        self.assertEqual(p['attempts'], 2)
        self.assertEqual(send.call_args_list[0].args[2], send.call_args_list[1].args[2])
        self.assertEqual(len(p['decision_id']), 32)

    def test_disable_never_creates_a_request(self):
        with mock.patch.object(jev_client, '_kill_switch_reason', return_value='off'), mock.patch.object(jev_client, '_curl') as send:
            with self.assertRaises(jev_client.JevError):
                jev_client.evaluate('task', {}, self.cfg)
            send.assert_not_called()

    def test_failed_request_has_no_success_provenance(self):
        with mock.patch.object(jev_client, '_curl', side_effect=jev_client.JevError('INVALID_RESPONSE', 'bad')):
            with self.assertRaises(jev_client.JevError):
                jev_client.evaluate('task', {}, self.cfg)
        self.assertEqual(ledger.read_events(self.cfg), [])

    def test_bind_changes_each_axis_without_recording_inputs(self):
        from decision_evidence import bind
        p = jev_client.provenance(self.evaluate())
        kwargs = dict(policy={'threshold': .7}, candidates=['private candidate'], recommendation={'tier': 'sonnet'})
        a = bind(p, **kwargs)
        for field in kwargs:
            b = bind(p, **dict(kwargs, **{field: {'changed': True}}))
            self.assertNotEqual(a[field + '_sha256'], b[field + '_sha256'])
        self.assertNotIn('private candidate', json.dumps(a))

    def test_route_is_advisory_and_binds_catalog_and_policy(self):
        response = dict(RESPONSE, answers={'model_tier': {'choice': 'sonnet'}})
        empty = {k: [] for k in ('skills', 'agents', 'commands', 'templates')}
        with mock.patch.object(route, 'inventory', return_value=empty), mock.patch.object(jev_client, '_curl', return_value=copy.deepcopy(response)):
            out = route.route('private task', self.cfg)
        self.assertEqual(out['outcome'], 'advisory')
        self.assertEqual(out['evidence']['decision_id'], out['provenance']['decision_id'])
        self.assertEqual(ledger.read_events(self.cfg)[-1]['data']['evidence'], out['evidence'])

    def test_dispatch_does_not_confirm_model_or_merge_different_evidence(self):
        v, _, _ = self.reroute(True, {'subtype': 'deferred_to_next_turn'}, deferred=True)
        dispatched = dict(v, took_effect=True, outcome='dispatched', confirmation='process_started')
        ledger.log_event(self.cfg, 'live_switch_dispatch', '', {'verdict': dict(dispatched, evidence=dict(v['evidence'], policy_sha256='0' * 64))})
        self.assertEqual(ledger.stats(self.cfg)['switches']['deferred'], 1)
        ledger.log_event(self.cfg, 'live_switch_dispatch', '', {'verdict': dispatched})
        s = ledger.stats(self.cfg)['switches']
        self.assertEqual((s['applied'], s['dispatched'], s['deferred']), (0, 1, 0))

    def test_cached_advice_keeps_original_decision_link(self):
        import hook_user_prompt
        decision = {'ok': True, 'answers': {}, 'model': 'sonnet', 'candidates': {}, 'evidence': {'decision_id': 'a' * 32}}
        with mock.patch('prompt_cache.consume', return_value=decision), mock.patch.object(hook_user_prompt, 'load_cfg', return_value=self.cfg), mock.patch.object(hook_user_prompt, 'route') as classify, mock.patch('sys.stdin', io.StringIO('{"prompt":"synthetic task"}')), contextlib.redirect_stdout(io.StringIO()):
            hook_user_prompt.main()
        classify.assert_not_called()
        r = ledger.read_events(self.cfg)[-1]
        self.assertEqual(r['event'], 'routing_advice')
        self.assertEqual(r['data']['evidence'], decision['evidence'])
        self.assertEqual(r['data']['applied'], 'not_measured')

    def test_statistics_report_selection_not_component_application(self):
        import cli_report
        ledger.log_event(self.cfg, 'route', '', {'selection': {'agents': {'choice': 'reviewer', 'confidence': .9, 'applied': True}}})
        slot = ledger.stats(self.cfg)['confidence']['agents']
        self.assertEqual(slot['selected_rate'], 1)
        self.assertNotIn('applied_rate', slot)
        text = cli_report.render_stats(self.cfg)
        self.assertIn('selected', text)
        self.assertNotIn('→ applied', text)


if __name__ == '__main__':
    unittest.main()

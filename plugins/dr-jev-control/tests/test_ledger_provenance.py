#!/usr/bin/env python3
"""Every recorded decision must name the model that made it, its latency and the release.

The request goes to the alias `jev-latest`. Before this change the ledger kept
`usage` only, so no recorded decision could be tied to a model version: a corpus
spanning a version change was mixed and nothing said so. Measured on a live host
(2026-09-27): 1180 `route` and 16 056 `pretool` records, none with a model name.
"""
from __future__ import annotations

import io, json, os, sys, tempfile, unittest
from pathlib import Path
from unittest import mock

S = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(S))
import hook_pre_tool
import jev_client
import ledger
import route as route_mod

RESPONSE = {'model': 'jev-9.9.9', 'usage': {'input_tokens': 10, 'output_tokens': 2},
            'answers': {'risky': {'noul': 0.9}, 'model_tier': {'choice': 'sonnet'},
                        'production_risk': {'noul': 0.2}}}


def _cfg(path):
    return {'api': {'retries': 0}, 'telemetry': {'enabled': True, 'path': str(path)},
            'routing': {'enabled': True, 'modes': {}},
            'hooks': {'pretool_risk': True, 'enforce_jev_denials': False}}


class EvaluateRecordsClientFacts(unittest.TestCase):
    def test_latency_and_attempts_attached(self):
        with mock.patch.object(jev_client, 'read_key', lambda: 'k'), \
             mock.patch.object(jev_client, '_curl', lambda *a: json.loads(json.dumps(RESPONSE))), \
             mock.patch.object(jev_client, '_kill_switch_reason', lambda: None):
            out = jev_client.evaluate('s', {}, {'api': {'transport': 'curl', 'retries': 0}})
        self.assertIsInstance(out['_client']['latency_ms'], int)
        self.assertEqual(out['_client']['attempts'], 1)
        self.assertEqual({k: jev_client.provenance(out)[k] for k in ('model', 'latency_ms', 'attempts')}, {'model': 'jev-9.9.9', 'latency_ms': out['_client']['latency_ms'],
                                                      'attempts': 1})

    def test_provenance_of_malformed_response_is_empty_not_error(self):
        self.assertEqual({k: jev_client.provenance(None)[k] for k in ('model', 'latency_ms', 'attempts')}, {'model': None, 'latency_ms': None, 'attempts': None})
        self.assertEqual(jev_client.provenance({'_client': 'x'})['latency_ms'], None)


class LedgerRecordsProvenance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.path = Path(self.tmp.name) / 'ledger.jsonl'
        self.resp = dict(RESPONSE, _client={'latency_ms': 42, 'attempts': 1})

    def tearDown(self):
        self.tmp.cleanup()

    def records(self):
        return [json.loads(l) for l in self.path.read_text().splitlines()]

    def test_route_record_names_model_and_latency(self):
        with mock.patch.object(route_mod, 'evaluate', lambda *a, **k: self.resp), \
             mock.patch.object(route_mod, 'inventory', lambda: {k: [] for k in ('skills', 'agents', 'commands', 'templates')}):
            route_mod.route('task', _cfg(self.path), mode='balanced')
        rec = self.records()[-1]
        self.assertEqual(rec['event'], 'route')
        self.assertEqual({k: rec['data']['provenance'][k] for k in ('model', 'latency_ms', 'attempts')}, {'model': 'jev-9.9.9', 'latency_ms': 42, 'attempts': 1})
        self.assertIn('release', rec)

    def test_pretool_record_names_model_and_latency(self):
        payload = {'tool_name': 'Bash', 'tool_input': {'command': 'git push origin main'}}
        with mock.patch.object(hook_pre_tool, 'load_cfg', lambda: _cfg(self.path)), \
             mock.patch.object(hook_pre_tool, 'evaluate', lambda *a, **k: self.resp), \
             mock.patch('sys.stdin', io.StringIO(json.dumps(payload))), mock.patch('sys.stdout', io.StringIO()):
            hook_pre_tool.main()
        rec = self.records()[-1]
        self.assertEqual(rec['event'], 'pretool')
        self.assertEqual(rec['data']['provenance']['model'], 'jev-9.9.9')
        self.assertEqual(rec['data']['provenance']['latency_ms'], 42)


class ReleaseSha(unittest.TestCase):
    def _with_layout(self, meta):
        tmp = tempfile.TemporaryDirectory()
        root = Path(tmp.name) / 'releases' / ('a' * 40)
        scripts = root / 'plugins' / 'dr-jev-control' / 'scripts'; scripts.mkdir(parents=True)
        if meta is not None:
            (root / 'host-installation.json').write_text(meta)
        fake = scripts / 'ledger.py'; fake.write_text('')
        with mock.patch.object(ledger, '__file__', str(fake)), mock.patch.object(ledger, '_RELEASE', []):
            sha = ledger.release_sha()
        tmp.cleanup()
        return sha

    def test_host_release_is_named(self):
        self.assertEqual(self._with_layout(json.dumps({'source_sha': 'b' * 40})), 'b' * 40)

    def test_absent_malformed_or_non_sha_is_none(self):
        self.assertIsNone(self._with_layout(None))
        self.assertIsNone(self._with_layout('{not json'))
        self.assertIsNone(self._with_layout(json.dumps({'source_sha': '../../etc'})))


if __name__ == '__main__':
    unittest.main()

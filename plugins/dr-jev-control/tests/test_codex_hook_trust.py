#!/usr/bin/env python3
"""Codex runs a hook only after the operator trusts it, not when it is written.

These cover the gap that hid a whole class of hook events for 45 minutes: the
hooks were installed and the client reported them Active, while the ledger held
zero UserPromptSubmit events because the entries were still awaiting review.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from jev import codex_hook_trust  # noqa: E402

SHA = 'b13540486fc0ee34f7726dabcf9e1ba1a6ca35fc'
OTHER = '57d591d04d0d47e5798db3c970992df1b238004f'


def _hook(sha):
    return {'type': 'command', 'timeout': 9,
            'command': f'/usr/bin/python3 /home/a/.local/share/jev/releases/{sha}/scripts/jev_hook.py codex X'}


def _home(tmp, hooks, state):
    home = Path(tmp)
    (home/'.codex').mkdir(parents=True, exist_ok=True)
    (home/'.codex/hooks.json').write_text(json.dumps({'hooks': hooks}))
    (home/'.codex/config.toml').write_text(state)
    return home


def _block(event_key, index, enabled):
    """A state block carrying both `trusted_hash` and `enabled = true`.

    An untrusted hook has no block at all -- Codex writes one when the operator
    grants trust. Some blocks carry `enabled = true` and some do not, within
    one Codex version (DEV-BOX: 5 of 14 on 0.156.1; the Mac: 0 of 16);
    `_block_0156` below is the form without it.
    """
    if not enabled:
        return ''
    body = 'trusted_hash = "sha256:deadbeef"\nenabled = true\n'
    return f'[hooks.state."/home/a/.codex/hooks.json:{event_key}:{index}:0"]\n{body}\n'


def _block_0156(event_key, index):
    """The block carries `trusted_hash` and no `enabled` -- every block on the
    Mac and host-devs, and 9 of 14 on DEV-BOX, all on codex-cli 0.156.1."""
    return (f'[hooks.state."/home/a/.codex/hooks.json:{event_key}:{index}:0"]\n'
            'trusted_hash = "sha256:deadbeef"\n\n')


def _block_refused(event_key, index):
    """A version that writes an explicit refusal must still be honoured."""
    return (f'[hooks.state."/home/a/.codex/hooks.json:{event_key}:{index}:0"]\n'
            'trusted_hash = "sha256:deadbeef"\nenabled = false\n\n')


class CodexHookTrust(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()

    def test_a_written_hook_with_no_state_block_reads_as_untrusted(self):
        """The measured failure: installed, counted Active, never executed."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=False))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['pending'], ['UserPromptSubmit'])

    def test_an_enabled_hook_reads_as_trusted(self):
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'trusted')
        self.assertEqual(result['pending'], [])

    def test_one_untrusted_hook_among_trusted_ones_is_still_reported(self):
        """The real host state: PreToolUse ran while UserPromptSubmit did not."""
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}],
                      'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True) +
                     _block('user_prompt_submit', 0, enabled=False))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['pending'], ['UserPromptSubmit'])
        self.assertIn('PreToolUse', result['installed'])

    def test_trust_for_a_different_release_does_not_count_for_this_one(self):
        """Trust is keyed to the command string, which carries releases/<sha>."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(OTHER)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'not_measured')

    def test_a_foreign_hook_is_never_claimed_as_ours(self):
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [{'type': 'command',
                                                 'command': '/home/a/.local/bin/coworker-hook-guard'}]}]},
                     '')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'not_measured')

    def test_absent_configuration_is_not_measured_rather_than_trusted(self):
        """A missing file must not read as a pass: it answers nothing."""
        result = codex_hook_trust(SHA, Path(self.tmp)/'nowhere')
        self.assertEqual(result['state'], 'not_measured')

    def test_the_index_must_match_not_merely_the_event(self):
        """Two hooks on one event: trusting the foreign one is not trusting ours."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [{'type': 'command', 'command': '/bin/true'}]},
                                           {'hooks': [_hook(SHA)]}]},
                     _block('user_prompt_submit', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')

    # -- a block without `enabled` -------------------------------------------
    # The client writes `enabled = true` on some blocks only. A check that
    # demanded it reported `untrusted` on two hosts whose hooks were running --
    # measured with an isolated CODEX_HOME: state blocks present gave 4 `hook:`
    # lines from `codex exec`, the same home with every block stripped gave 0.

    def test_enabled_written_before_the_hash_reads_as_trusted(self):
        """The order seen on DEV-BOX: `enabled = true` first, then the hash."""
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}]},
                     '[hooks.state."/home/a/.codex/hooks.json:pre_tool_use:0:0"]\n'
                     'enabled = true\ntrusted_hash = "sha256:deadbeef"\n\n')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'trusted')

    def test_a_block_without_an_enabled_key_reads_as_trusted(self):
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block_0156('user_prompt_submit', 0))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'trusted')
        self.assertEqual(result['pending'], [])

    def test_an_explicit_enabled_false_is_still_a_refusal(self):
        """The negative half: presence alone must not override a refusal."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block_refused('user_prompt_submit', 0))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertEqual(result['pending'], ['UserPromptSubmit'])

    def test_a_hash_after_a_blank_line_inside_the_block_is_still_read(self):
        """Blank lines inside a block must not hide the grant behind them.

        This does not discriminate between the two body patterns tried here --
        `.*` matches the empty string, so both read such a block whole. It is
        kept as a statement about the file shape, not as a regression guard.
        """
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     '[hooks.state."/home/a/.codex/hooks.json:'
                     'user_prompt_submit:0:0"]\n\n'
                     'trusted_hash = "sha256:deadbeef"\n\n')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'trusted')

    def test_a_block_without_a_trusted_hash_is_not_a_grant(self):
        """An empty block is not evidence that the operator granted anything."""
        home = _home(self.tmp,
                     {'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     '[hooks.state."/home/a/.codex/hooks.json:'
                     'user_prompt_submit:0:0"]\n\n')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'untrusted')

    # -- slot reuse -------------------------------------------------------
    # Codex's `trusted_hash` is NOT computed over the command: measured on
    # 0.155.1, an Orca hook and a Jev hook in adjacent slots carried the same
    # hash. So an enabled slot proves the operator trusted *something* here,
    # and a reinstall landing in that slot inherits the grant. These cover the
    # case that shipped green: the command was substituted and the verdict
    # stayed `trusted` with nothing said.

    def test_an_enabled_slot_for_a_different_command_is_flagged_as_reused(self):
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True))
        (home/'.config/jev').mkdir(parents=True, exist_ok=True)
        (home/'.config/jev/codex-trust-witness.json').write_text(
            json.dumps({'pre_tool_use:0:0': '/some/entirely/other/command'}))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'trusted')
        self.assertEqual(result.get('slot_reused'), ['PreToolUse'])

    def test_a_slot_whose_recorded_command_matches_is_not_flagged(self):
        """The positive half: without it, a check that always flags would pass."""
        hook = _hook(SHA)
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [hook]}]},
                     _block('pre_tool_use', 0, enabled=True))
        (home/'.config/jev').mkdir(parents=True, exist_ok=True)
        (home/'.config/jev/codex-trust-witness.json').write_text(
            json.dumps({'pre_tool_use:0:0': hook['command']}))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'trusted')
        self.assertNotIn('slot_reused', result)

    def test_the_witness_is_written_only_when_every_slot_is_enabled(self):
        """A pending hook means the operator has not finished; recording the
        commands then would vouch for a grant that was never given."""
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}],
                      'UserPromptSubmit': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True))
        result = codex_hook_trust(SHA, home)
        self.assertEqual(result['state'], 'untrusted')
        self.assertFalse((home/'.config/jev/codex-trust-witness.json').exists())

    def test_the_witness_is_written_when_trust_is_complete(self):
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True))
        codex_hook_trust(SHA, home)
        witness = home/'.config/jev/codex-trust-witness.json'
        self.assertTrue(witness.exists())
        self.assertEqual(json.loads(witness.read_text())['pre_tool_use:0:0'],
                         _hook(SHA)['command'])
        # Secrets are not involved, but the file records a trust decision.
        self.assertEqual(witness.stat().st_mode & 0o777, 0o600)

    def test_an_unreadable_witness_does_not_break_the_check(self):
        """Corrupt JSON must not turn a measurable state into an exception."""
        home = _home(self.tmp,
                     {'PreToolUse': [{'hooks': [_hook(SHA)]}]},
                     _block('pre_tool_use', 0, enabled=True))
        (home/'.config/jev').mkdir(parents=True, exist_ok=True)
        (home/'.config/jev/codex-trust-witness.json').write_text('{not json')
        self.assertEqual(codex_hook_trust(SHA, home)['state'], 'trusted')


if __name__ == '__main__':
    unittest.main()

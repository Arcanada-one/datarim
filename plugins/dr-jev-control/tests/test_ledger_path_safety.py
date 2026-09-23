#!/usr/bin/env python3
"""What the ledger refuses to write to, and what it must not refuse.

`log_event` swallows every exception by design, so a path rule that is too
strict does not fail loudly -- it produces an empty ledger that reads exactly
like "nothing happened". Both directions are asserted here for that reason.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import ledger  # noqa: E402


def _cfg(path):
    return {'telemetry': {'enabled': True, 'path': str(path)}}


class LedgerPathSafety(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def test_a_symlinked_ledger_file_is_refused(self):
        """The substitution this guard exists for: point the ledger at a target
        and every appended record lands in someone else's file."""
        target = self.dir/'victim.txt'
        target.write_text('')
        link = self.dir/'ledger.jsonl'
        link.symlink_to(target)
        ledger.log_event(_cfg(link), 'route', 'task', {'model': 'sonnet'})
        self.assertEqual(target.read_text(), '', 'wrote through a symlink')

    def test_the_symlink_check_holds_without_O_NOFOLLOW(self):
        """Measured: on this platform O_NOFOLLOW refuses the open by itself, so
        asserting the outcome alone cannot tell whether the explicit check does
        anything -- deleting it leaves the suite green. O_NOFOLLOW is 0 where
        the platform lacks it (`getattr(os, 'O_NOFOLLOW', 0)`), and that is the
        case the Python-level check is actually covering, so it is the case
        this asserts."""
        target = self.dir/'victim.txt'
        target.write_text('')
        link = self.dir/'ledger.jsonl'
        link.symlink_to(target)
        real_open = os.open

        def open_without_nofollow(path, flags, *rest):
            return real_open(path, flags & ~getattr(os, 'O_NOFOLLOW', 0), *rest)

        with mock.patch.object(ledger.os, 'open', side_effect=open_without_nofollow):
            ledger.log_event(_cfg(link), 'route', 'task', {'model': 'sonnet'})
        self.assertEqual(target.read_text(), '', 'wrote through a symlink')

    def test_a_symlinked_parent_directory_does_not_block_the_write(self):
        """macOS ships /var as a symlink to private/var, so an ancestry rule
        rejects the platform's own temp paths -- silently, since log_event
        never raises. This asserts the ledger still records there."""
        real = self.dir/'real'
        real.mkdir()
        link = self.dir/'via-link'
        link.symlink_to(real, target_is_directory=True)
        path = link/'ledger.jsonl'
        ledger.log_event(_cfg(path), 'route', 'task', {'model': 'sonnet'})
        self.assertTrue((real/'ledger.jsonl').is_file(), 'no record written')
        self.assertEqual(len(ledger.read_events(_cfg(path))), 1)

    def test_the_written_ledger_is_owner_only(self):
        path = self.dir/'ledger.jsonl'
        ledger.log_event(_cfg(path), 'route', 'task', {'model': 'sonnet'})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_a_non_regular_ledger_target_is_refused(self):
        """A fifo would block the hook rather than record anything."""
        path = self.dir/'ledger.jsonl'
        os.mkfifo(path)
        ledger.log_event(_cfg(path), 'route', 'task', {'model': 'sonnet'})
        self.assertTrue(path.is_fifo())

    # No test asserts the S_ISREG check on its own. Measured on this platform:
    # O_NONBLOCK already refuses a reader-less fifo with ENXIO, and removing
    # S_ISREG leaves the suite green. Isolating it would mean opening a fifo
    # without O_NONBLOCK, which blocks forever -- a test that can hang the suite
    # is worse than the gap. Recorded rather than papered over with an
    # assertion that passes either way: the check is defence in depth for a
    # platform where the flag is absent, and nothing here proves it fires.


if __name__ == '__main__':
    unittest.main()

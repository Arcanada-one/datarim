"""Council regression probes; destructive command strings are never executed."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]/'scripts'
sys.path.insert(0, str(SCRIPTS))
import jev_client
from ledger import _scrub
from safety_floor import destructive_reason


class HookBoundaryTests(unittest.TestCase):
    def test_outbound_serialized_secret_and_short_bearer_are_removed(self):
        inputs = [json.dumps({'password': 'SYNTHETIC"remaining'}),
                  'curl -H "Authorization: '+ 'Bearer '+ 'SYNTHETICshort" https://example.invalid',
                  'Authorization: Basic SYNTHETICshort',
                  'password="SYNTHETIC\\"remaining"']
        for value in inputs:
            with self.subTest(value=value):
                payload = jev_client._payload(value, {}, {}).decode()
                self.assertNotIn('SYNTHETIC', payload)
                self.assertNotIn('remaining', payload)

    def test_field_redaction_preserves_usage_counts(self):
        value = _scrub({'password': 'short', 'input_tokens': 10,
                        'output_tokens': 5, 'ANTHROPIC_API_KEY': 'short'})
        self.assertEqual(value['password'], '<redacted>')
        self.assertEqual(value['ANTHROPIC_API_KEY'], '<redacted>')
        self.assertEqual((value['input_tokens'], value['output_tokens']), (10, 5))

    def test_kill_switch_stops_retry_before_second_transport_call(self):
        cfg = {'api': {'transport': 'urllib', 'retries': 2}}
        error = jev_client.JevError('TIMEOUT', 'synthetic timeout')
        with patch.object(jev_client, 'read_key', return_value='synthetic'), \
             patch.object(jev_client, '_kill_switch_reason', side_effect=[None, None, 'disabled']), \
             patch.object(jev_client, '_urllib', side_effect=error) as transport, \
             patch.object(jev_client.time, 'sleep'):
            with self.assertRaises(jev_client.JevError) as raised:
                jev_client.evaluate('task', {}, cfg)
        self.assertEqual(raised.exception.code, 'DISABLED')
        self.assertEqual(transport.call_count, 1)

    def test_floor_catches_known_wrappers_and_explicit_force(self):
        commands = ['rm -r /Users', 'git -C repo push --force',
                    'git push --force --force-if-includes',
                    'git push --force-with-lease --force', 'git push origin +HEAD:main',
                    'bash -c "echo safe; rm -rf /"', 'sudo -u root rm -rf /',
                    'env -i rm -rf /', 'rm -rf /Users/../Users']
        for command in commands:
            with self.subTest(command=command):
                self.assertIsNotNone(destructive_reason(command))

    def test_floor_benign_quoted_commands_and_scoped_operations(self):
        for command in ['echo "safe; rm -rf /"', 'git push --force-with-lease',
                        'bash -c "echo safe; printf ok"', 'env -i printf ok',
                        'rm -rf ./build', 'git -C repo status']:
            with self.subTest(command=command):
                self.assertIsNone(destructive_reason(command))

    def test_floor_blocks_writes_that_destroy_a_whole_filesystem(self):
        """Raw-device writes are more irreversible than the rm -rf the floor already blocks.

        MEASURED 2026-09-22 on dev-box against the installed host runtime: `rm -rf /` was
        denied while `dd if=/dev/zero of=/dev/sda` and `mkfs.ext4 /dev/sda1` were allowed.
        Both destroy every file on the device at once, below the filesystem, where neither
        permissions nor file-level backups help. The module's own stated criterion is
        "catastrophic-and-irreversible", so these belong inside it.
        """
        commands = ['dd if=/dev/zero of=/dev/sda',
                    'dd if=/dev/urandom of=/dev/nvme0n1 bs=1M',
                    'sudo dd if=/dev/zero of=/dev/sda1',
                    'mkfs.ext4 /dev/sda1',
                    'mkfs -t xfs /dev/nvme0n1p2',
                    'echo start; dd if=/dev/zero of=/dev/vda']
        for command in commands:
            with self.subTest(command=command):
                self.assertIsNotNone(destructive_reason(command))

    def test_floor_allows_ordinary_dd_and_mkfs_usage(self):
        """A narrow floor must not block the everyday, recoverable forms."""
        commands = ['dd if=backup.img of=/tmp/restore.img',
                    'dd if=/dev/zero of=./placeholder bs=1M count=10',
                    'dd if=/dev/sda of=/mnt/backup/disk.img',
                    'mkfs.ext4 /tmp/loopfile.img',
                    'echo "dd if=/dev/zero of=/dev/sda"',
                    # Paths that END in a device-looking name but are ordinary
                    # files. MUTATION-CHECKED: without these, anchoring the
                    # pattern to /dev/ could be dropped and no test would fail.
                    'dd if=/dev/zero of=/home/client/images/sda',
                    'dd if=backup of=./nvme0n1',
                    'mkfs.ext4 /var/tmp/vda']
        for command in commands:
            with self.subTest(command=command):
                self.assertIsNone(destructive_reason(command))

    def test_large_payload_does_not_outlive_hook_budget(self):
        start = time.monotonic()
        self.assertIsNotNone(destructive_reason('rm -rf '+'-x '*1400000+'/'))
        self.assertLess(time.monotonic()-start, 4.0)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'POSIX FIFO probe')
    def test_fifo_ledger_does_not_block_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            fifo = Path(directory).resolve()/'ledger'
            os.mkfifo(fifo)
            code = ('import sys;sys.path.insert(0,sys.argv[1]);from ledger import log_event;'
                    'log_event({"telemetry":{"path":sys.argv[2]}},"test","synthetic",{})')
            result = subprocess.run([sys.executable, '-c', code, str(SCRIPTS), str(fifo)],
                                    capture_output=True, timeout=2)
            self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()

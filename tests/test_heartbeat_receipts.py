"""Opt-in response-consumption snapshots must not launder old terminal state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

LIB = Path(__file__).resolve().parents[1] / "dev-tools/lib/heartbeat-status.sh"


class ReceiptHeartbeatTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.receipts = self.root / "receipts"
        self.receipts.mkdir()
        self.run_id = str(uuid.uuid4())
        self.env = dict(os.environ, DATARIM_INTERACTION_RUN_ID=self.run_id,
                        DATARIM_INTERACTION_RECEIPTS_DIR=str(self.receipts))
        self.status = self.root / "datarim/runtime/EXA-0001.status"

    def write(self, env=None):
        return subprocess.run(["bash", str(LIB), "write", "--root", str(self.root),
                               "--task-id", "EXA-0001", "--state", "done", "--now", "1800000000"],
                              env=self.env if env is None else env, capture_output=True, text=True, check=False)

    def receipt(self, **overrides):
        item = dict(runId=self.run_id, interactionId=str(uuid.uuid4()),
                    decisionId=str(uuid.uuid4()), contextDigest="a" * 64)
        item.update(overrides)
        (self.receipts / (item["interactionId"] + ".json")).write_text(json.dumps(item))
        return item

    def test_snapshot_is_at_write_not_read_and_same_second_is_valid(self):
        self.assertEqual(self.write().returncode, 0)
        old = self.status.read_bytes()
        item = self.receipt()
        self.assertEqual(self.status.read_bytes(), old)
        self.assertEqual(json.loads(old)["interaction_receipts"], [])
        self.assertEqual(self.write().returncode, 0)
        new = json.loads(self.status.read_bytes())
        self.assertEqual(new["updated_at"], json.loads(old)["updated_at"])
        self.assertEqual(new["interaction_run_id"], self.run_id)
        self.assertEqual(new["interaction_receipts"], [{key: value for key, value in item.items() if key != "runId"}])

    def test_invalid_receipt_does_not_replace_last_good_state(self):
        for override in ({"runId": str(uuid.uuid4())}, {"decisionId": "bad"}, {"contextDigest": "bad"}, {"answer": "secret"}):
            with self.subTest(override=override):
                self.assertEqual(self.write().returncode, 0)
                old = self.status.read_bytes()
                self.receipt(**override)
                self.assertNotEqual(self.write().returncode, 0)
                self.assertEqual(self.status.read_bytes(), old)
                for path in self.receipts.iterdir():
                    path.unlink()

    def test_action_execution_pair_survives_write_time_snapshot(self):
        ordinary = self.receipt()
        self.assertEqual(self.write().returncode, 0)
        old = self.status.read_bytes()
        actions = [self.receipt(actionExecution=dict(claimVersion=version, receiptDigest="b" * 64))
                   for version in (1, 2147483647)]
        read = subprocess.run(["bash", str(LIB), "read", "--root", str(self.root),
                               "--task-id", "EXA-0001"], env=self.env,
                              capture_output=True, check=False)
        self.assertEqual(read.returncode, 0)
        self.assertEqual(read.stdout, old)
        self.assertEqual(self.write().returncode, 0)
        snapshot = json.loads(self.status.read_bytes())
        expected = [{key: value for key, value in item.items() if key != "runId"}
                    for item in sorted([ordinary, *actions], key=lambda item: item["interactionId"])]
        self.assertEqual(snapshot["interaction_receipts"], expected)
        self.assertNotIn("actionExecution", next(item for item in expected
                                               if item["interactionId"] == ordinary["interactionId"]))
        self.assertEqual(snapshot["updated_at"], json.loads(old)["updated_at"])

    def test_malformed_action_execution_preserves_last_good_snapshot(self):
        pair = dict(claimVersion=1, receiptDigest="b" * 64)
        malformed = [None, [], "synthetic", {}, {"claimVersion": 1}, {"receiptDigest": "b" * 64},
                     dict(pair, extra="synthetic")]
        malformed += [dict(pair, claimVersion=value)
                      for value in (True, False, 0, -1, 2147483648, 1.0, 1.5, "1", None)]
        malformed += [dict(pair, receiptDigest=value)
                      for value in ("B" * 64, "b" * 63, "b" * 65, "g" * 64, "b" * 64 + "\n", 1, None)]
        self.receipt(actionExecution=pair)
        self.assertEqual(self.write().returncode, 0)
        old = self.status.read_bytes()
        for index, value in enumerate(malformed):
            with self.subTest(case=index):
                item = self.receipt(actionExecution=value)
                result = self.write()
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("invalid or unreadable consumption evidence", result.stderr)
                self.assertEqual(self.status.read_bytes(), old)
                (self.receipts / (item["interactionId"] + ".json")).unlink()

    def test_action_execution_does_not_relax_existing_identity_or_field_checks(self):
        pair = dict(claimVersion=1, receiptDigest="b" * 64)
        self.assertEqual(self.write().returncode, 0)
        old = self.status.read_bytes()
        for override in ({"runId": str(uuid.uuid4())}, {"interactionId": "invalid"},
                         {"decisionId": "bad"}, {"contextDigest": "bad"}, {"unknown": "synthetic"}):
            with self.subTest(override=override):
                item = self.receipt(actionExecution=pair, **override)
                self.assertEqual(self.write().returncode, 2)
                self.assertEqual(self.status.read_bytes(), old)
                (self.receipts / (item["interactionId"] + ".json")).unlink()

    def test_duplicate_action_execution_fields_fail_closed(self):
        self.assertEqual(self.write().returncode, 0)
        old = self.status.read_bytes()
        item = self.receipt()
        path = self.receipts / (item["interactionId"] + ".json")
        pairs = ['{"claimVersion":1,"claimVersion":2,"receiptDigest":"' + "b" * 64 + '"}',
                 '{"claimVersion":1,"receiptDigest":"' + "b" * 64 + '","receiptDigest":"' + "c" * 64 + '"}']
        for pair in pairs:
            path.write_text(json.dumps(item)[:-1] + ',"actionExecution":' + pair + '}')
            self.assertEqual(self.write().returncode, 2)
            self.assertEqual(self.status.read_bytes(), old)

    def test_symlink_and_oversize_and_stream_rejected(self):
        item = self.receipt()
        path = self.receipts / (item["interactionId"] + ".json")
        target = self.root / "outside.json"
        path.rename(target)
        path.symlink_to(target)
        self.assertNotEqual(self.write().returncode, 0)
        path.unlink()
        path.write_text(" " * 4097)
        self.assertNotEqual(self.write().returncode, 0)
        path.write_text(json.dumps(item) + json.dumps(item))
        self.assertNotEqual(self.write().returncode, 0)

    def test_partial_configuration_fails_and_legacy_stays_compatible(self):
        env = dict(self.env)
        del env["DATARIM_INTERACTION_RUN_ID"]
        self.assertNotEqual(self.write(env).returncode, 0)
        del env["DATARIM_INTERACTION_RECEIPTS_DIR"]
        self.assertEqual(self.write(env).returncode, 0)
        self.assertNotIn("interaction_receipts", json.loads(self.status.read_bytes()))


if __name__ == "__main__":
    unittest.main()

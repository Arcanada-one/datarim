"""Real-Git controls for preparation admission and the release workflow root path."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "dev-tools/check-history-bootstrap.py"
PARITY = ROOT / "dev-tools/check-version-tag-parity.sh"


class HistoryBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.repo = self.work / "source"
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q")
        self.git("config", "user.name", "Arcanada")
        self.git("config", "user.email", "release@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")
        self.run_command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.work / "signer"))
        self.git("config", "gpg.format", "ssh")
        self.git("config", "user.signingkey", str(self.work / "signer"))
        (self.repo / ".github").mkdir()
        key = (self.work / "signer.pub").read_text().split()[:2]
        (self.repo / ".github/ssh-signing-allowed-signers").write_text("Arcanada " + " ".join(key) + "\n")
        (self.repo / "VERSION").write_text("4.2.1\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fix: verified baseline")
        self.baseline = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("tag", "-s", "v4.2.1", "-m", "baseline\nbump_level=patch")
        self.tag_object = self.git("rev-parse", "v4.2.1").stdout.strip()
        (self.repo / "dev-tools").mkdir()
        shutil.copy2(HELPER, self.repo / "dev-tools/check-history-bootstrap.py")
        shutil.copy2(ROOT / "dev-tools/release-classify.sh", self.repo / "dev-tools/release-classify.sh")
        (self.repo / ".datarim").mkdir()
        self.contract = {
            "schema": "DatarimHistoryBootstrap/v1", "version": "4.2.2",
            "baseline_tag": "v4.2.1", "baseline_commit": self.baseline,
            "baseline_tag_object": self.tag_object,
        }
        self.write_contract()
        (self.repo / "VERSION").write_text("4.2.2\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fix: readable reporting and root release")
        self.prepared = self.git("rev-parse", "HEAD").stdout.strip()
        self.tree = self.git("rev-parse", "HEAD^{tree}").stdout.strip()
        self.origin = self.work / "origin.git"
        self.run_command("git", "init", "-q", "--bare", str(self.origin))
        self.git("remote", "add", "origin", str(self.origin))
        self.git("push", "-q", "origin", "HEAD:main", "v4.2.1")
        self.run_command("git", "--git-dir", str(self.origin), "symbolic-ref", "HEAD", "refs/heads/main")

    def run_command(self, *args, cwd=None, check=True, env=None, input=None):
        result = subprocess.run(args, cwd=cwd or self.repo, env=env or self.env,
                                capture_output=True, text=True, input=input)
        if check and result.returncode:
            self.fail(f"{args[:3]} exited {result.returncode}: {result.stderr}")
        return result

    def git(self, *args, **kwargs):
        return self.run_command("git", *args, **kwargs)

    def write_contract(self):
        (self.repo / ".datarim/history-bootstrap.json").write_text(json.dumps(self.contract, indent=2) + "\n")

    def helper(self, mode="preparation", **kwargs):
        args = ["python3", str(HELPER), "--repo", str(self.repo), "--mode", mode]
        for key, value in kwargs.items():
            args += ["--" + key.replace("_", "-"), value]
        return self.run_command(*args, check=False)

    def parity(self):
        return self.run_command("bash", str(PARITY), "--check", "--repo", str(self.repo), check=False)

    def cutover(self, stamp_source=None):
        self.root = self.git("commit-tree", self.tree, input="chore: clean root\n").stdout.strip()
        self.git("tag", "-s", "v4.2.2", self.root, "-m", "\n".join([
            "release 4.2.2", "bump_level=patch",
            "history_bootstrap_source=" + (stamp_source or self.prepared),
            "history_bootstrap_tree=" + self.tree,
        ]))
        # Preserve the already-reviewed source as a provider-managed PR ref;
        # main and all advertised ordinary release tags alone omit this object.
        self.git("push", "-q", "origin", self.prepared + ":refs/pull/9/head")
        self.git("push", "-q", "--atomic", "--force", "origin", self.root + ":main", "v4.2.2")
        self.git("checkout", "-q", "--detach", self.root)

    def workflow(self, tag="v4.2.2", consumer="consumer"):
        clone = self.work / consumer
        self.run_command("git", "clone", "-q", "--no-local", str(self.origin), str(clone))
        # Execute the actual workflow's authentication and classification shell,
        # including the exact-SHA network fetch through the local real origin.
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        shell = workflow.split("- name: Authenticate signed tag on protected main and classify bump", 1)[1]
        shell = shell.split("run: |\n", 1)[1].split("\n      # Advisory drift check", 1)[0]
        shell = textwrap.dedent(shell)
        env = dict(self.env, RELEASE_TAG=tag, EXPECTED_REF="refs/heads/main",
                   GITHUB_OUTPUT=str(self.work / "workflow-output"))
        return self.run_command("bash", "-c", shell, cwd=clone, env=env, check=False)

    def test_preparation_is_deferred_and_never_reported_shipped(self):
        self.assertEqual(self.helper().returncode, 0)
        result = self.parity()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DEFERRED", result.stdout)
        self.assertIn("is not shipped", result.stdout)
        self.assertNotIn("PASS", result.stdout)

    def test_wrong_baseline_pin_refuses_preparation(self):
        self.contract["baseline_commit"] = "0" * 40
        self.write_contract()
        self.assertNotEqual(self.helper().returncode, 0)
        self.assertEqual(self.parity().returncode, 1)

    def test_unsigned_baseline_refuses_preparation(self):
        self.git("tag", "-d", "v4.2.1")
        self.git("tag", "-a", "v4.2.1", self.baseline, "-m", "unsigned")
        self.contract["baseline_tag_object"] = self.git("rev-parse", "v4.2.1").stdout.strip()
        self.write_contract()
        self.assertNotEqual(self.helper().returncode, 0)

    def test_root_cannot_defer_even_with_marker(self):
        self.cutover()
        self.assertNotEqual(self.helper().returncode, 0)
        self.git("push", "-q", "origin", ":refs/tags/v4.2.2")
        self.assertEqual(self.parity().returncode, 1)

    def test_child_of_root_cannot_defer_either(self):
        self.cutover()
        self.git("commit", "-q", "--allow-empty", "-m", "fix: successor")
        self.git("push", "-q", "origin", ":refs/tags/v4.2.2")
        self.assertNotEqual(self.helper().returncode, 0)
        self.assertEqual(self.parity().returncode, 1)

    def test_tree_equivalent_root_release_and_exact_sha_fetch(self):
        self.cutover()
        result = self.helper("release", source_sha=self.prepared, release_sha=self.root, tree_sha=self.tree)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.workflow()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = (self.work / "workflow-output").read_text()
        self.assertIn("bump_level=patch", output)
        self.assertIn("release_sha=" + self.root, output)

    def test_rewritten_root_cannot_hide_major_in_prepared_commit_range(self):
        self.git("commit", "-q", "--allow-empty", "-m", "feat!: original source breaking")
        source = self.git("rev-parse", "HEAD").stdout.strip()
        self.cutover(stamp_source=source)
        # Same tree still cannot conceal a major change declared in its original
        # commit range. The rewritten root subject itself says only chore.
        result = self.workflow()
        self.assertNotEqual(result.returncode, 0)

    def test_source_with_actual_tree_difference_refuses(self):
        (self.repo / "changed").write_text("different tree\n")
        self.git("add", "changed")
        self.git("commit", "-qm", "fix: unrelated tree")
        wrong_source = self.git("rev-parse", "HEAD").stdout.strip()
        self.cutover(stamp_source=wrong_source)
        result = self.helper("release", source_sha=wrong_source, release_sha=self.root, tree_sha=self.tree)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source tree differs", result.stderr)
        self.assertNotEqual(self.workflow().returncode, 0)

    def test_unknown_contract_fields_refuse(self):
        self.contract["skip_checks"] = "true"
        self.write_contract()
        self.assertNotEqual(self.helper().returncode, 0)

    def test_duplicate_contract_fields_refuse(self):
        path = self.repo / ".datarim/history-bootstrap.json"
        text = path.read_text().rstrip().removesuffix("}") + ', "version": "4.2.2"}\n'
        path.write_text(text)
        self.assertNotEqual(self.helper().returncode, 0)

    def test_declared_minor_version_cannot_use_patch_bootstrap(self):
        self.contract["version"] = "4.3.0"
        self.write_contract()
        (self.repo / "VERSION").write_text("4.3.0\n")
        self.assertNotEqual(self.helper().returncode, 0)

    def test_missing_remote_baseline_cannot_defer(self):
        self.git("push", "-q", "origin", ":refs/tags/v4.2.1")
        self.assertEqual(self.parity().returncode, 1)

    def test_lightweight_target_tag_does_not_pass_parity(self):
        self.git("tag", "v4.2.2")
        self.git("push", "-q", "origin", "v4.2.2")
        self.assertEqual(self.parity().returncode, 1)

    def test_future_ordinary_release_works_after_baseline_retirement(self):
        self.cutover()
        (self.repo / "VERSION").write_text("4.2.3\n")
        self.git("commit", "-qam", "fix: ordinary successor")
        successor = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("tag", "-s", "v4.2.3", "-m", "release 4.2.3\nbump_level=patch")
        self.git("push", "-q", "origin", successor + ":main", "v4.2.3", ":refs/tags/v4.2.1")
        result = self.workflow(tag="v4.2.3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("release_sha=" + successor, (self.work / "workflow-output").read_text())

    def test_root_retry_refuses_missing_retired_baseline(self):
        self.cutover()
        self.git("push", "-q", "origin", ":refs/tags/v4.2.1")
        result = self.workflow()
        self.assertNotEqual(result.returncode, 0)

    def test_nonroot_cannot_select_bootstrap_release_mode(self):
        result = self.helper("release", source_sha=self.prepared, release_sha=self.prepared, tree_sha=self.tree)
        self.assertNotEqual(result.returncode, 0)

    def test_release_tag_cannot_point_away_from_main(self):
        self.cutover()
        self.git("commit", "-q", "--allow-empty", "-m", "fix: newer main")
        self.git("push", "-q", "origin", "HEAD:main")
        result = self.workflow()
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()

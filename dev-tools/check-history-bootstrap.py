#!/usr/bin/env python3
"""Validate the narrowly scoped preparation and signed-root release contract."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


SHA = re.compile(r"[0-9a-f]{40}")
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=False
    )
    if result.returncode:
        raise ValueError("Git validation failed: " + " ".join(args[:2]))
    return result.stdout.strip()


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate history-bootstrap field")
        result[key] = value
    return result


def contract(repo):
    data = json.loads((repo / ".datarim/history-bootstrap.json").read_text(), object_pairs_hook=unique_fields)
    expected = {"schema", "version", "baseline_tag", "baseline_commit", "baseline_tag_object"}
    if not isinstance(data, dict) or set(data) != expected:
        raise ValueError("history-bootstrap contract has unexpected fields")
    if data["schema"] != "DatarimHistoryBootstrap/v1":
        raise ValueError("unsupported history-bootstrap schema")
    if not all(isinstance(value, str) for value in data.values()):
        raise ValueError("history-bootstrap fields must be strings")
    target = SEMVER.fullmatch(data["version"])
    baseline = SEMVER.fullmatch(data["baseline_tag"].removeprefix("v"))
    if not target or not baseline or not data["baseline_tag"].startswith("v"):
        raise ValueError("history-bootstrap requires stable semantic versions")
    old = tuple(map(int, baseline.groups()))
    if tuple(map(int, target.groups())) != (old[0], old[1], old[2] + 1):
        raise ValueError("history-bootstrap permits only the declared next patch")
    if (repo / "VERSION").read_text().strip() != data["version"]:
        raise ValueError("history-bootstrap version differs from VERSION")
    for key in ("baseline_commit", "baseline_tag_object"):
        if not SHA.fullmatch(data[key]):
            raise ValueError("invalid pinned history-bootstrap object")
    tag = data["baseline_tag"]
    if git(repo, "rev-parse", "refs/tags/" + tag) != data["baseline_tag_object"]:
        raise ValueError("history-bootstrap baseline tag object differs from pin")
    if git(repo, "cat-file", "-t", "refs/tags/" + tag) != "tag":
        raise ValueError("history-bootstrap baseline must be annotated")
    if git(repo, "rev-parse", tag + "^{commit}") != data["baseline_commit"]:
        raise ValueError("history-bootstrap baseline commit differs from pin")
    if git(repo, "show", tag + ":VERSION").strip() != baseline.group(0):
        raise ValueError("history-bootstrap baseline version differs from tag")
    git(repo, "-c", "gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers", "verify-tag", tag)
    return data


def validate(repo, mode, source_sha=None, release_sha=None, tree_sha=None):
    data = contract(repo)
    if mode == "preparation":
        head = git(repo, "rev-parse", "HEAD")
        if len(git(repo, "rev-list", "--parents", "-n", "1", head).split()) < 2:
            raise ValueError("a parentless root cannot defer release-tag parity")
        git(repo, "merge-base", "--is-ancestor", data["baseline_commit"], head)
        if head == data["baseline_commit"]:
            raise ValueError("preparation must follow the baseline")
    else:
        if not all(value and SHA.fullmatch(value) for value in (source_sha, release_sha, tree_sha)):
            raise ValueError("root release requires pinned source, release and tree SHA")
        if len(git(repo, "rev-list", "--parents", "-n", "1", release_sha).split()) != 1:
            raise ValueError("bootstrap release must be a parentless root")
        git(repo, "merge-base", "--is-ancestor", data["baseline_commit"], source_sha)
        if source_sha == data["baseline_commit"]:
            raise ValueError("bootstrap source must follow the baseline")
        if git(repo, "rev-parse", source_sha + "^{tree}") != tree_sha:
            raise ValueError("bootstrap prepared source tree differs from signed tree")
        if git(repo, "rev-parse", release_sha + "^{tree}") != tree_sha:
            raise ValueError("bootstrap root tree differs from signed tree")
        # The helper and contract used for admission must themselves be in the
        # exact prepared source/root tree, not supplied from another checkout.
        for path in (".datarim/history-bootstrap.json", "dev-tools/check-history-bootstrap.py", "VERSION"):
            if git(repo, "show", release_sha + ":" + path) != (repo / path).read_text().rstrip("\n"):
                raise ValueError("bootstrap validation checkout differs from release tree")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--mode", choices=("preparation", "release"), required=True)
    parser.add_argument("--source-sha")
    parser.add_argument("--release-sha")
    parser.add_argument("--tree-sha")
    args = parser.parse_args()
    try:
        data = validate(args.repo, args.mode, args.source_sha, args.release_sha, args.tree_sha)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 1
    print("baseline_tag=" + data["baseline_tag"])
    print("baseline_commit=" + data["baseline_commit"])
    print("version=" + data["version"])
    return 0


if __name__ == "__main__":
    sys.exit(main())

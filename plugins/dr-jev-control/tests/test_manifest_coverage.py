#!/usr/bin/env python3
"""The Jev integrity manifest must cover every Jev source file.

`sha256sum -c JEV-MANIFEST.sha256` answers "does each listed file still hash to
its recorded value". It cannot answer "is every file listed", so a new source
file is simply absent from the integrity control and nothing says so. That is
how scripts/project_hook.py ended up unlisted, and how four test files added in
this branch did.

Enumeration fails open; this test makes it fail closed.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[3]
MANIFEST = REPO/'JEV-MANIFEST.sha256'

#: Globs describing what the manifest is responsible for. Kept here rather than
#: derived from the manifest itself -- deriving the expectation from the thing
#: under test would make the check vacuous.
COVERED = (
    'scripts/*.py',
    'plugins/dr-jev-control/scripts/*.py',
    'plugins/dr-jev-control/tests/*.py',
    'plugins/dr-jev-control/bin/*',
)


def _entries():
    out = {}
    for line in MANIFEST.read_text().splitlines():
        if line.startswith('#') or not line.strip():
            continue
        digest, path = line.split('  ', 1)
        out[path] = digest
    return out


def _sources():
    found = set()
    for pattern in COVERED:
        found |= {str(p.relative_to(REPO)) for p in REPO.glob(pattern) if p.is_file()}
    return found


class ManifestCoverage(unittest.TestCase):
    def test_every_jev_source_file_is_listed(self):
        missing = sorted(_sources() - set(_entries()))
        self.assertEqual(missing, [], f'not covered by JEV-MANIFEST.sha256: {missing}')

    def test_every_listed_file_still_exists(self):
        """A stale entry is the other direction of the same failure: the manifest
        keeps vouching for a path nothing ships any more."""
        gone = sorted(p for p in _entries() if not (REPO/p).is_file())
        self.assertEqual(gone, [], f'listed but absent from the tree: {gone}')

    def test_recorded_digests_match_the_files(self):
        """Duplicates what CI's `sha256sum -c` does, so a mismatch is caught in
        the same run as the coverage gap rather than one CI round later."""
        wrong = []
        for path, digest in _entries().items():
            target = REPO/path
            if not target.is_file():
                continue
            if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                wrong.append(path)
        self.assertEqual(sorted(wrong), [], f'digest mismatch: {sorted(wrong)}')


if __name__ == '__main__':
    unittest.main()

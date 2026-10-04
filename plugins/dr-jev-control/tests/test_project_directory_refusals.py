#!/usr/bin/env python3
"""Where an installation is refused, and where it must still be allowed.

`project_directory` is the only thing standing between `install.sh <path>` and
an installation that writes into a system directory. It had no test, so the
refusal list could be shortened with the suite still green.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
import project_install  # noqa: E402


class ProjectDirectoryRefusals(unittest.TestCase):
    def _refused(self, path):
        with self.assertRaises(ValueError, msg=f'{path} was accepted'):
            project_install.project_directory(path)

    def test_the_temp_root_itself_is_refused(self):
        """Both spellings: the literal /tmp and whatever this platform uses.

        macOS resolves gettempdir() under /var/folders, so a list naming only
        /tmp leaves the real temp root open; Linux resolves it to /tmp, so a
        list naming only gettempdir() leaves nothing extra. Both are asserted
        because the list has to cover the platform it is not running on.
        """
        self._refused(tempfile.gettempdir())
        slash_tmp = os.path.join(os.sep, 'tmp')
        if Path(slash_tmp).exists():
            self._refused(slash_tmp)

    def test_system_directories_are_refused(self):
        for path in ('/', '/etc', '/usr', '/var'):
            if Path(path).exists():
                self._refused(path)

    def test_home_is_refused_by_the_home_check_itself(self):
        """Asserting only that $HOME is refused proves nothing about the home
        branch: on this machine home sits under /Users, which the directory
        list already covers, so deleting the home check left this green.
        Pointing HOME at a directory no other rule covers isolates it.
        """
        elsewhere = Path(tempfile.mkdtemp())/'home'
        elsewhere.mkdir()
        original = os.environ.get('HOME')
        os.environ['HOME'] = str(elsewhere)
        try:
            Path.home.cache_clear() if hasattr(Path.home, 'cache_clear') else None
            self._refused(str(elsewhere))
        finally:
            if original is None:
                os.environ.pop('HOME', None)
            else:
                os.environ['HOME'] = original

    def test_an_ancestor_of_home_is_refused(self):
        parent = Path.home().resolve().parent
        if parent != Path.home().resolve():
            self._refused(str(parent))

    def test_the_product_source_tree_is_refused(self):
        """Installing the product into itself would make the source the runtime."""
        self._refused(str(project_install.SOURCE))

    def test_an_ordinary_project_directory_is_accepted(self):
        """The refusals must not swallow the normal case: a directory inside
        the temp root is where every test installation lives."""
        target = Path(tempfile.mkdtemp())/'project'
        target.mkdir()
        self.assertEqual(project_install.project_directory(str(target)), target.resolve())

    def test_a_missing_directory_is_rejected_rather_than_created(self):
        missing = Path(tempfile.mkdtemp())/'not-there'
        with self.assertRaises((FileNotFoundError, OSError, ValueError)):
            project_install.project_directory(str(missing))
        self.assertFalse(missing.exists(), 'the probe created the directory')

    def test_a_nonexistent_name_in_the_list_does_not_break_resolution(self):
        """The list names directories from several platforms; one absent on this
        host must not turn every installation into an error."""
        target = Path(tempfile.mkdtemp())/'p'
        target.mkdir()
        self.assertTrue(project_install.project_directory(str(target)).is_dir())


if __name__ == '__main__':
    unittest.main()

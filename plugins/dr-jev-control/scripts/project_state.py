"""Project-local state; independent plugin callers cannot fall back to home."""
import os
from pathlib import Path


def state_dir():
    root = Path(os.environ.get('DATARIM_PROJECT_ROOT', Path.cwd())).resolve()
    return root / '.datarim-runtime/state/jev'


def read_key():
    path = os.environ.get('TYPESAFE_API_KEY_FILE')
    if not path:
        return os.environ.get('TYPESAFE_API_KEY', '').strip()
    target = Path(path)
    if target.is_symlink() or target.stat().st_mode & 0o077:
        raise ValueError('Jev key must be a private regular file')
    return target.read_text().strip()

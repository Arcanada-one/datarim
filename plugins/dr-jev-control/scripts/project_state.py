"""Project-local state; independent plugin callers cannot fall back to home."""
import os
from pathlib import Path


def state_dir():
    explicit = os.environ.get('JEV_STATE_DIR')
    if explicit:
        return Path(explicit)
    root = Path(os.environ.get('DATARIM_PROJECT_ROOT', Path.cwd())).resolve()
    return root / '.datarim-runtime/state/jev'


def disabled_reason():
    for name in ('JEV_DISABLE', 'DATARIM_JEV_DISABLE'):
        if os.environ.get(name, '').strip().lower() not in ('', '0', 'false', 'no'):
            return 'env ' + name
    roots = [state_dir()]
    for name in ('JEV_HOST_STATE', 'JEV_PROJECT_STATE'):
        if os.environ.get(name):
            roots.append(Path(os.environ[name]))
    return next(('Jev disable flag' for root in roots if (root/'DISABLED').exists()), None)


def read_key():
    path = os.environ.get('TYPESAFE_API_KEY_FILE')
    if not path:
        return os.environ.get('TYPESAFE_API_KEY', '').strip()
    target = Path(path)
    if target.is_symlink() or not target.is_file() or target.stat().st_mode & 0o077:
        raise ValueError('Jev key must be a private regular file')
    return target.read_text().strip()

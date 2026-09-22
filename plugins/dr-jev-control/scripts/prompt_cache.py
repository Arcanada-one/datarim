"""One-use transfer of a wrapper decision to a native prompt hook."""
import hashlib
import json
import os
from pathlib import Path
import time
import uuid

from project_state import state_dir


def save(prompt, decision):
    from ledger import _scrub
    root = state_dir()/'prompt-cache'
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if root.is_symlink():
        raise ValueError('Prompt cache cannot be a symlink')
    path = root/('decision-'+uuid.uuid4().hex+'.json')
    fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump({'created': time.time(), 'prompt_sha256': hashlib.sha256(prompt.encode()).hexdigest(),
                   'decision': _scrub(decision)}, stream)
    return path


def consume(prompt):
    value = os.environ.get('JEV_PROMPT_CACHE')
    if not value:
        return None
    path = Path(value)
    allowed = Path(os.environ['JEV_HOST_STATE']) if os.environ.get('JEV_HOST_STATE') else state_dir()
    try:
        if (not path.resolve().is_relative_to(allowed.resolve()) or path.is_symlink()
                or not path.name.startswith('decision-') or path.parent.name != 'prompt-cache'
                or not path.is_file() or path.stat().st_mode & 0o077):
            return None
        data = json.loads(path.read_text())
        if data.get('prompt_sha256') != hashlib.sha256(prompt.encode()).hexdigest():
            return None
        claimed = path.with_name(path.name+'.claimed-'+uuid.uuid4().hex)
        path.rename(claimed)  # One process wins; a repeated prompt routes anew.
        claimed.unlink()
        if 0 <= time.time()-data.get('created', 0) <= 120:
            decision = data.get('decision')
            return decision if isinstance(decision, dict) else None
    except (OSError, ValueError, TypeError):
        return None
    return None

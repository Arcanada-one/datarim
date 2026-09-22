"""Explicit project scope shared by installation and entrypoints; no home fallback."""
from __future__ import annotations

import json
import os
from pathlib import Path


class ScopeError(ValueError):
    pass


def project_root(start=None):
    current = Path(start or Path.cwd()).resolve(strict=True)
    for candidate in (current, *current.parents):
        manifest = candidate / '.datarim-runtime' / 'installation.json'
        if manifest.is_file() and not manifest.is_symlink():
            data = json.loads(manifest.read_text())
            if data.get('schema') != 1 or data.get('project') != str(candidate):
                raise ScopeError('Installation belongs to another project; reinstall explicitly')
            runtime = candidate / '.datarim-runtime'
            if runtime.is_symlink():
                raise ScopeError('Runtime must be a project-local directory')
            # Nested repositories are opt-in, so a checkout cannot inherit
            # another project's authority accidentally.
            for ancestor in (current, *current.parents):
                if ancestor == candidate:
                    break
                if (ancestor / '.git').exists():
                    rel = str(ancestor.relative_to(candidate))
                    if rel not in data.get('contexts', []):
                        raise ScopeError('Nested repository is not an approved project context')
            return candidate
        if candidate == Path.home().resolve():
            break
    raise ScopeError('No project-local Datarim installation in this directory')


def activate(root):
    runtime = root / '.datarim-runtime'
    os.environ['DATARIM_PROJECT_ROOT'] = str(root)
    os.environ['DATARIM_RUNTIME'] = str(runtime)
    os.environ['DATARIM_ROOT'] = str(runtime)
    os.environ['DATARIM_JEV_HOME'] = str(runtime / 'plugins/dr-jev-control')
    os.environ['DATARIM_JEV_CONFIG'] = str(runtime / 'jev-config.json')
    os.environ['DATARIM_JEV_STATE'] = str(runtime / 'state/jev')
    os.environ['TYPESAFE_API_KEY_FILE'] = str(root / 'config/credentials/jev/api-key')
    return runtime

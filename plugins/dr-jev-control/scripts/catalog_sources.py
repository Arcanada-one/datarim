"""Explicit independent catalog providers; metadata only, never executable code."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat

KINDS = ('skills', 'agents', 'commands', 'templates')
MAX_ROOTS = 8
MAX_FILES = 128
MAX_ENTRIES = 512
MAX_BYTES = 65536
NAME = re.compile(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}\Z')


def _unsafe(info):
    """Group/world-writable, or owned by someone other than this user or root."""
    return bool(info.st_mode & 0o022) or info.st_uid not in (os.geteuid(), 0)


def validate_roots(roots):
    """Validate trusted configuration, not an event/cwd supplied search path."""
    if not isinstance(roots, list) or len(roots) > MAX_ROOTS:
        raise ValueError('catalog_roots must be a list of at most eight providers')
    result = []
    ids = set()
    for row in roots:
        if not isinstance(row, dict) or set(row) != {'id', 'path'}:
            raise ValueError('catalog provider requires exactly id and path')
        ident, value = row['id'], row['path']
        if not isinstance(ident, str) or not NAME.fullmatch(ident) or ident in ids:
            raise ValueError('invalid or duplicate catalog provider id')
        if not isinstance(value, str) or any(ord(c) < 32 for c in value):
            raise ValueError('invalid catalog provider path')
        root = Path(value)
        if not root.is_absolute() or root.is_symlink() or not root.is_dir():
            raise ValueError('catalog provider must be an absolute regular directory')
        if root.resolve() != root or _unsafe(os.stat(root)):
            raise ValueError('catalog provider must be canonical, owned by this user or root, '
                             'and not externally writable')
        ids.add(ident)
        result.append({'id': ident, 'path': str(root)})
    return result


def _open_root(root):
    """Anchor every path component without following a replaced symlink."""
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in root.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        if _unsafe(os.fstat(fd)):
            raise ValueError('unsafe catalog root')
        return fd
    except BaseException:
        os.close(fd)
        raise


def _read_files(fd, kind, remaining, prefix=()):
    # scandir is consumed incrementally and bounded BEFORE sorting/filtering.
    with os.scandir(fd) as entries:
        names = []
        for entry in entries:
            remaining[0] -= 1
            if remaining[0] < 0:
                raise ValueError('catalog traversal limit exceeded')
            names.append(entry.name)
    for name in sorted(names):
        info = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISLNK(info.st_mode):
            raise ValueError('catalog symlink refused')
        if stat.S_ISDIR(info.st_mode) and kind == 'skills':
            if len(prefix) >= 16:
                raise ValueError('catalog depth limit exceeded')
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                if _unsafe(os.fstat(child)):
                    raise ValueError('unsafe catalog directory')
                yield from _read_files(child, kind, remaining, prefix + (name,))
            finally:
                os.close(child)
        elif (kind == 'skills' and name == 'SKILL.md') or (kind != 'skills' and name.endswith('.md')):
            # Refuse FIFOs/devices/sockets before open (no side effects); O_NONBLOCK
            # keeps a FIFO swapped in after this lstat from blocking the hook, and
            # the fstat below re-checks the object actually opened before any read.
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('non-regular catalog file refused')
            file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
            with os.fdopen(file_fd, 'rb') as stream:
                current = os.fstat(stream.fileno())
                if not stat.S_ISREG(current.st_mode) or _unsafe(current):
                    raise ValueError('unsafe catalog file')
                raw = stream.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise ValueError('catalog metadata file exceeds byte limit')
            yield prefix + (name,), raw


def inventory(roots):
    """A malformed provider refuses the whole independent catalog, not a prefix."""
    out = {k: [] for k in KINDS}
    for provider in validate_roots(roots):
        root = Path(provider['path'])
        root_fd = _open_root(root)
        try:
            for kind in KINDS:
                try:
                    base_fd = os.open(kind, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root_fd)
                except FileNotFoundError:
                    continue
                try:
                    if _unsafe(os.fstat(base_fd)):
                        raise ValueError('unsafe catalog kind directory')
                    for relative, raw in _read_files(base_fd, kind, [MAX_ENTRIES]):
                        if len(out[kind]) >= MAX_FILES:
                            raise ValueError('catalog candidate limit exceeded')
                        parts = relative[:-1] if kind == 'skills' else (Path(relative[-1]).stem,)
                        if not parts or any(not NAME.fullmatch(p) for p in parts):
                            raise ValueError('invalid catalog candidate name')
                        name = provider['id'] + '--' + '--'.join(parts)
                        if len(name) > 128 or any(x['name'] == name for x in out[kind]):
                            raise ValueError('ambiguous or oversized catalog candidate name')
                        text = raw.decode('utf-8')
                        match = re.search(r'(?mi)^description:[ \t]*([^\r\n]+)', text)
                        description = match.group(1).strip().strip(chr(34)+chr(39))[:280] if match else ''
                        out[kind].append({'name': name, 'description': description,
                                          'path': str(root/kind/Path(*relative)), 'source_id': provider['id'],
                                          'sha256': hashlib.sha256(raw).hexdigest()})
                finally:
                    os.close(base_fd)
        finally:
            os.close(root_fd)
    return out


def selected_references(picks, selections):
    """Bind only policy-selected names to source metadata, never model-supplied paths."""
    refs = {}
    for kind, candidates in picks.items():
        selected = selections.get(kind, {})
        names = {x['name'] for x in selected.get('apply', [])}
        if selected.get('applied'):
            names.add(selected.get('choice'))
        refs[kind] = [{k: c[k] for k in ('name', 'path', 'source_id', 'sha256')}
                      for c in candidates if c['name'] in names and 'source_id' in c]
    return refs


def fingerprint(roots, candidates, policy):
    return hashlib.sha256(json.dumps({'roots': roots, 'candidates': candidates, 'policy': policy},
                                    sort_keys=True, separators=(',', ':')).encode()).hexdigest()

#!/usr/bin/env python3
"""Resolve independent Datarim reply/artifact preferences without a runtime.

Configuration is JSON or a YAML mapping with a scalar-only ``language`` block.
No YAML tags, interpolation, executable configuration or external dependency.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys

MAX_CONFIG_BYTES = 65536
FIELDS = ('replies', 'artifacts')
TAG_RE = re.compile(r'(?:[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*|[ixIX](?:-[A-Za-z0-9]{1,8})+)\Z')
RTL_LANGUAGES = {'ar', 'arc', 'ckb', 'dv', 'fa', 'he', 'ku', 'ps', 'sd', 'ug', 'ur', 'yi'}


class PreferenceError(ValueError):
    """Invalid or conflicting language preference; never an inferred success."""


def language_tag(value):
    if not isinstance(value, str) or len(value) > 63 or not TAG_RE.fullmatch(value):
        raise PreferenceError('Expected a language tag such as en, fr-CA or zh-Hant; no shell syntax.')
    parts = value.split('-')
    normalized = [parts[0].lower()]
    extension = parts[0].lower() in ('i', 'x')
    for index, part in enumerate(parts[1:], 1):
        extension = extension or len(part) == 1
        if not extension and len(part) == 4 and part.isalpha():
            normalized.append(part.title())
        elif not extension and len(part) == 2 and part.isalpha():
            normalized.append(part.upper())
        else:
            normalized.append(part.lower())
    return '-'.join(normalized)


def text_direction(tag):
    parts = tag.split('-')
    if 'Latn' in parts:
        return 'ltr'
    if 'Arab' in parts or 'Hebr' in parts or parts[0] in RTL_LANGUAGES:
        return 'rtl'
    return 'ltr'


def _read(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_CONFIG_BYTES:
            raise PreferenceError('Language configuration must be a regular file no larger than 64 KiB.')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_CONFIG_BYTES + 1)
        if len(data) > MAX_CONFIG_BYTES:
            raise PreferenceError('Language configuration exceeds 64 KiB.')
        return data.decode('utf-8')
    finally:
        os.close(fd)


def _scalar(value):
    value = value.strip()
    # Only language tags are accepted: quotes/comments cannot contain instructions.
    match = re.fullmatch(r'''(?:"([A-Za-z0-9-]+)"|'([A-Za-z0-9-]+)'|([A-Za-z0-9-]+))(?:\s+#.*)?''', value)
    if not match:
        raise PreferenceError('Language values must be scalar language tags.')
    return language_tag(next(x for x in match.groups() if x is not None))


def parse_config(text):
    if text.lstrip().startswith(('{', '[')):
        depth, quoted, escaped = 0, False, False
        for char in text:
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char in '{[':
                depth += 1
                if depth > 32:
                    raise PreferenceError('Configuration nesting exceeds 32 levels.')
            elif char in '}]':
                depth -= 1
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise PreferenceError('Duplicate configuration key.')
                result[key] = value
            return result
        try:
            obj = json.loads(text, object_pairs_hook=unique)
        except RecursionError as error:
            raise PreferenceError('Configuration nesting is too deep.') from error
        if not isinstance(obj, dict):
            raise PreferenceError('Configuration must be an object with a language mapping.')
        lang = obj.get('language', {})
        if not isinstance(lang, dict) or set(lang) - set(FIELDS):
            raise PreferenceError('language must contain only replies and artifacts.')
        return {key: language_tag(value) for key, value in lang.items()}
    result = {}
    in_language = False
    seen = False
    field_indent = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or stripped in ('---', '...'):
            continue
        if re.match(r'^language(?:\s|:|$)', stripped) and line.startswith('\t'):
            raise PreferenceError('The language mapping must be top-level and use spaces.')
        if not line[0].isspace():
            in_language = False
            if re.match(r'^language\s*:', line):
                if seen:
                    raise PreferenceError('Duplicate language configuration block.')
                seen = True
                if not re.fullmatch(r'language:\s*(?:#.*)?', line):
                    raise PreferenceError('Use a language mapping with indented scalar replies/artifacts.')
                in_language = True
                field_indent = None
            elif re.match(r'^language(?:\s|$)', line):
                raise PreferenceError('The language mapping needs a colon and indented scalar fields.')
            # Unrelated configuration is owned by its existing reader.
            continue
        if in_language:
            match = re.fullmatch(r' +([A-Za-z_]+):\s*(.*)', line)
            if not match or match[1] not in FIELDS or match[1] in result:
                raise PreferenceError('Invalid, unknown or duplicate language field.')
            indent = len(line) - len(line.lstrip(' '))
            if field_indent is not None and indent != field_indent:
                raise PreferenceError('Language fields must use the same indentation.')
            field_indent = indent
            result[match[1]] = _scalar(match[2])
    return result


def _config(path):
    text = _read(path)
    return {} if text is None else parse_config(text)


def project_root(project=None):
    start = Path(project) if project is not None else Path.cwd()
    start = start.expanduser().absolute()
    if not start.is_dir():
        raise PreferenceError('Project must be an existing directory.')
    for parent in (start, *start.parents):
        if (parent / '.git').exists() or (parent / '.datarim-runtime').is_dir() or (parent / 'datarim/config.yaml').is_file():
            return parent
    return start


def user_config_path(environ=None):
    env = os.environ if environ is None else environ
    home = Path(env.get('HOME') or Path.home())
    base = env.get('XDG_CONFIG_HOME')
    if base and not Path(base).is_absolute():
        raise PreferenceError('XDG_CONFIG_HOME must be absolute.')
    return (Path(base) if base else home / '.config') / 'datarim/config.yaml'


def _legacy_artifact(project):
    text = _read(project / 'AGENTS.md')
    if text is None:
        return None
    values = []
    for line in text.splitlines():
        match = re.fullmatch(r'\s*Artifact language:\s*([^#]+?)(?:\s*#.*)?', line)
        if match:
            value = match[1].strip()
            if value != '<lang>':
                values.append(language_tag(value))
    if len(set(values)) > 1:
        raise PreferenceError('Conflicting Artifact language directives in project AGENTS.md.')
    return values[0] if values else None


def resolve_preferences(project=None, user_config=None, project_config=None,
                        replies=None, artifacts=None, environ=None):
    env = os.environ if environ is None else environ
    root = project_root(project)
    user = Path(user_config) if user_config is not None else user_config_path(env)
    shared = Path(project_config) if project_config is not None else root / 'datarim/config.yaml'
    local = root / 'datarim/config.local.yaml'
    configs = {'user': _config(user), 'project': _config(shared), 'project_local': _config(local)}
    legacy = _legacy_artifact(root)
    if legacy and configs['project'].get('artifacts', legacy) != legacy:
        raise PreferenceError('Project language.artifacts conflicts with legacy Artifact language; reconcile both sources.')
    if legacy:
        configs['project'].setdefault('artifacts', legacy)
    result = {'schema': 'datarim-language-preferences/1', 'sources': {}, 'warnings': []}
    for field, explicit in [('replies', replies), ('artifacts', artifacts)]:
        env_key = 'DATARIM_REPLY_LANG' if field == 'replies' else 'DATARIM_ARTIFACT_LANG'
        order = ('project_local', 'user', 'project') if field == 'replies' else ('project_local', 'project', 'user')
        if explicit is not None:
            value, source = language_tag(explicit), 'explicit'
        elif env.get(env_key):
            value, source = language_tag(env[env_key]), 'environment'
        else:
            value, source = 'en', 'default'
            for scope in order:
                if field in configs[scope]:
                    value, source = configs[scope][field], scope
                    if scope == 'project' and field == 'artifacts' and legacy:
                        source = 'project+legacy' if 'artifacts' in _config(shared) else 'legacy_instruction'
                    break
        result[field] = value
        result['sources'][field] = source
    result['direction'] = {field: text_direction(result[field]) for field in FIELDS}
    return result


def context(preferences):
    return ('Resolved reply language: ' + preferences['replies'] +
            '; resolved artifact language: ' + preferences['artifacts'] + '.\n'
            'Apply these independently to generated presentation and documents. '
            'Reusable notes, documents and excerpts authored inside replies use artifact language '
            'for their generated prose and examples; do not add an unrequested translated example. '
            'Human explanation outside the artifact uses reply language. '
            'Preserve verbatim input, code and machine identifiers. Explicit task language requests '
            '(including bilingual or translation requests) and native authority retain precedence. '
            'Reply direction: ' + preferences['direction']['replies'] + '.')


def _safe_destination(path):
    if '..' in path.parts:
        raise PreferenceError('Configuration destination cannot contain parent traversal.')
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise PreferenceError('Configuration writes never follow symlinks.')


def _parent_descriptor(path):
    """Walk directories without links and anchor every write to their descriptor."""
    if not hasattr(os, 'O_NOFOLLOW'):
        raise PreferenceError('Safe configuration writes require directory descriptor support.')
    current = os.open(path.anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parent.parts[1:]:
            try:
                following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            except FileNotFoundError:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=current)
                except FileExistsError:
                    pass
                following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            os.close(current)
            current = following
        return current
    except Exception:
        os.close(current)
        raise


def _read_at(directory, name):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    except FileNotFoundError:
        return '', 0o600
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_CONFIG_BYTES:
            raise PreferenceError('Configuration must be a regular file no larger than 64 KiB.')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_CONFIG_BYTES + 1)
        if len(data) > MAX_CONFIG_BYTES:
            raise PreferenceError('Configuration exceeds 64 KiB.')
        return data.decode('utf-8'), info.st_mode & 0o777
    finally:
        os.close(fd)


def configure(path, replies=None, artifacts=None):
    path = Path(path).expanduser().absolute()
    _safe_destination(path)
    updates = {key: language_tag(value) for key, value in [('replies', replies), ('artifacts', artifacts)] if value is not None}
    if not updates:
        raise PreferenceError('Specify --replies and/or --artifacts.')
    lock = _parent_descriptor(path)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        _safe_destination(path)
        text, mode = _read_at(lock, path.name)
        values = parse_config(text)
        values.update(updates)
        if text.lstrip().startswith('{'):
            obj = json.loads(text)
            obj['language'] = values
            data = json.dumps(obj, indent=2, ensure_ascii=False) + '\n'
        else:
            lines = text.splitlines(keepends=True)
            first = next((i for i, line in enumerate(lines) if re.match(r'^language\s*:', line)), None)
            replacement = 'language:\n' + ''.join('  ' + key + ': ' + values[key] + '\n' for key in FIELDS if key in values)
            if first is None:
                data = text + ('\n' if text and not text.endswith('\n') else '') + replacement
            else:
                end = first + 1
                while end < len(lines) and (not lines[end].strip() or lines[end][0].isspace() or lines[end].lstrip().startswith('#')):
                    end += 1
                data = ''.join(lines[:first]) + replacement + ''.join(lines[end:])
        assert parse_config(data) == values
        temp = '.language-' + secrets.token_hex(16)
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=lock)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temp, mode, dir_fd=lock, follow_symlinks=False)
            _safe_destination(path)
            os.replace(temp, path.name, src_dir_fd=lock, dst_dir_fd=lock)
            os.fsync(lock)
            _safe_destination(path)
            anchored, current = os.fstat(lock), path.parent.stat()
            if (anchored.st_dev, anchored.st_ino) != (current.st_dev, current.st_ino):
                raise PreferenceError('Configuration directory changed; preference delivery is not confirmed.')
        finally:
            try:
                os.unlink(temp, dir_fd=lock)
            except FileNotFoundError:
                pass
    finally:
        os.close(lock)
    return {'schema': 'datarim-language-configuration/1', 'path': str(path), 'language': values}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['resolve', 'configure'])
    parser.add_argument('--project', type=Path)
    parser.add_argument('--user-config', type=Path)
    parser.add_argument('--project-config', type=Path)
    parser.add_argument('--replies')
    parser.add_argument('--artifacts')
    parser.add_argument('--scope', choices=['user', 'project', 'local'], default='user')
    parser.add_argument('--format', choices=['json', 'context'], default='json')
    args = parser.parse_args(argv)
    try:
        if args.action == 'configure':
            path = (args.user_config or user_config_path()) if args.scope == 'user' else (args.project_config or project_root(args.project) / ('datarim/config.local.yaml' if args.scope == 'local' else 'datarim/config.yaml'))
            result = configure(path, args.replies, args.artifacts)
        else:
            result = resolve_preferences(args.project, args.user_config, args.project_config, args.replies, args.artifacts)
        print(context(result) if args.action == 'resolve' and args.format == 'context' else json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (ValueError, OSError, UnicodeError) as error:
        print(json.dumps({'schema': 'datarim-language-error/1', 'error': str(error)}), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

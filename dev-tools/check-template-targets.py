#!/usr/bin/env python3
"""Check literal shipped template targets, including qualified references."""
import argparse
from pathlib import Path
import re

import yaml


def template_target_exists(root, name):
    """Resolve core templates and manifest-declared plugin template namespaces."""
    core = root/'templates'/name
    if core.is_file() and core.resolve().is_relative_to(root.resolve()):
        return True
    plugin_id, separator, relative = name.partition('/')
    if not separator or not relative or Path(relative).is_absolute():
        return False
    plugin_root = root/'plugins'/plugin_id
    manifest = plugin_root/'plugin.yaml'
    if not manifest.is_file():
        return False
    try:
        metadata = yaml.safe_load(manifest.read_text()) or {}
    except (yaml.YAMLError, OSError):
        return False
    if 'templates' not in metadata.get('categories', []):
        return False
    target = plugin_root/'templates'/relative
    return target.is_file() and target.resolve().is_relative_to(plugin_root.resolve())


def check(root):
    failures = []
    checked = 0
    files = [root/'AGENTS.md', root/'README.md']
    for scope in ('agents', 'commands', 'skills'):
        files.extend(sorted((root/scope).rglob('*.md')))
    pattern = re.compile(r'(?<![\w-])templates/([\w./-]+)')
    for file in files:
        if not file.is_file():
            continue
        illustrative = False
        example_pending = False
        example_fence = None
        for number, line in enumerate(file.read_text().splitlines(), 1):
            if '<!-- gate:history-allowed -->' in line:
                illustrative = True
            if '<!-- gate:example-only -->' in line:
                example_pending = True
                continue
            fence = re.match(r'^\s*(`{3,}|~{3,})', line)
            if fence and example_pending:
                example_fence = fence[1]
                example_pending = False
                continue
            if example_fence:
                if fence and fence[1].startswith(example_fence):
                    example_fence = None
                continue
            if '<!-- /gate:' in line:
                illustrative = False
                continue
            if illustrative:
                continue
            for match in pattern.finditer(line):
                if line[:match.start()].endswith('datarim/'):
                    continue
                name = match[1].rstrip('.')
                # Directory placeholders and extensionless examples aren't assets.
                if not Path(name).suffix or name.endswith('/'):
                    continue
                checked += 1
                if not template_target_exists(root, name):
                    failures.append(f'{file.relative_to(root)}:{number}: missing templates/{name}')
    return checked, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if not args.root.is_dir():
        parser.error('root must be a directory')
    count, failures = check(args.root)
    for failure in failures:
        print(failure)
    print(f'template targets: checked={count} missing={len(failures)}')
    return 1 if failures else (0 if count else 2)


if __name__ == '__main__':
    raise SystemExit(main())

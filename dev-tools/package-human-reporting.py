#!/usr/bin/env python3
"""Build offline reporting archives from a fixed source-file allowlist.

No installation, network, subprocesses, credential discovery or source mutation.
An optional text transport exports only the newly built archive for download.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import lzma
from pathlib import Path
import re
import zipfile

SKILL_FILES = (
    'SKILL.md', 'references/profiles.md', 'references/domain-language.md',
    'references/re-explain.md', 'references/data-and-trust.md', 'references/datarim.md',
    'schemas/task-contract.schema.json', 'schemas/report.schema.json',
    'schemas/execution-receipt.schema.json', 'scripts/hr.py', 'scripts/native.py',
    'scripts/language.py', 'scripts/presentation.py',
    'references/language-preferences.md', 'references/presentation.md',
    'locales/en.json', 'locales/ru.json', 'locales/fr.json',
    'locales/ar.json', 'locales/ja.json',
    'tests/test_portable.py',
)
DOC_FILES = (
    'README.md', 'RESEARCH.md', 'TECHNICAL_SPEC.md', 'ACCEPTANCE_REPORT.md',
    'LICENSE', 'THIRD_PARTY_NOTICES.md', 'EVALUATION_PLAN.json',
    'examples/partial/contract.json', 'examples/partial/report.json',
    'examples/partial/evidence.txt', 'examples/partial/REPORT_RU.md',
)
INTEGRATION_FILES = (
    'AGENTS.md', 'commands/dr-help.md', 'commands/dr-explain.md',
    'commands/dr-qa.md', 'commands/dr-compliance.md', 'commands/dr-archive.md',
    'dev-tools/command-graph.yaml', 'dev-tools/framework-graph.yaml',
    'dev-tools/framework-graph.py', 'dev-tools/package-human-reporting.py',
    'skills/datarim-system/SKILL.md', 'skills/datarim-system/language-preferences.md',
    'skills/human-summary/SKILL.md',
    'skills/visual-maps/command-dependencies.md',
    'skills/visual-maps/framework-architecture.md',
    'tests/test_human_reporting.py', 'tests/test_human_reporting_release.py',
    'tests/test_human_reporting_completeness.py', 'tests/test-human-summary-contract.bats',
)
MAX_SOURCE_BYTES = 2 * 1024 * 1024


def read_source(root: Path, name: str) -> bytes:
    path = root
    for part in Path(name).parts:
        if part in ('..', ''):
            raise ValueError('Invalid release source path.')
        path /= part
        if path.is_symlink():
            raise ValueError('Release source may not be symlinked: ' + name)
    if not path.is_file() or path.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError('Missing or oversized release source: ' + name)
    data = path.read_bytes()
    if len(data) > MAX_SOURCE_BYTES:
        raise ValueError('Release source grew beyond the size limit: ' + name)
    return data


def payload(root: Path, kind: str = 'standalone') -> dict[str, bytes]:
    root = root.resolve(strict=True)
    if kind not in ('standalone', 'integration'):
        raise ValueError('Unknown archive kind.')
    mappings = [(f'skills/human-outcome-reporting/{n}', f'human-outcome-reporting/{n}') for n in SKILL_FILES]
    mappings += [(f'documentation/human-reporting/{n}', n) for n in DOC_FILES]
    mappings.append(('commands/dr-explain.md', 'datarim-command/dr-explain.md'))
    mappings.append(('scripts/human_reporting_install.py', 'install.py'))
    mappings.append(('documentation/how-to/install-human-outcome-reporting.md', 'INSTALL.md'))
    if kind == 'integration':
        sources = [s for s, _ in mappings] + list(INTEGRATION_FILES)
        mappings += [(s, 'repository-overlay/' + s) for s in sorted(set(sources))]
    files = {destination: read_source(root, source) for source, destination in mappings}
    # The portable guide is outside the repository hierarchy after extraction.
    # Keep its project documentation links useful instead of publishing broken paths.
    guide = files['INSTALL.md'].decode()
    guide = guide.replace('../../INSTALL.md', 'https://github.com/Arcanada-one/datarim/blob/main/INSTALL.md')
    guide = guide.replace('../../skills/human-outcome-reporting/SKILL.md', 'human-outcome-reporting/SKILL.md')
    files['INSTALL.md'] = guide.encode()
    return files


def require_new_output(path: Path, suffix: str) -> None:
    if path.suffix != suffix or path.exists() or path.is_symlink():
        raise ValueError('Output must be a new ' + suffix + ' file.')
    if not path.parent.is_dir():
        raise ValueError('Create the explicitly chosen output directory first.')
    for parent in path.absolute().parents:
        if parent.is_symlink():
            raise ValueError('Output parent may not be symlinked.')


def build(root: Path, output: Path, kind: str = 'standalone') -> dict:
    files = payload(root, kind)
    require_new_output(output, '.zip')
    match = re.search(r'^  version: "(\d+\.\d+\.\d+)"$', files['human-outcome-reporting/SKILL.md'].decode(), re.M)
    if not match:
        raise ValueError('The skill has no valid release version.')
    version = match[1]
    if ("VERSION = '" + version + "'") not in files['human-outcome-reporting/scripts/hr.py'].decode():
        raise ValueError('Skill and engine versions differ.')
    manifest = {
        'schema': 'hr-release/1', 'version': version, 'kind': kind,
        'format': 'standalone-skill-with-datarim-command' if kind == 'standalone' else 'skill-and-selected-datarim-source-overlay',
        'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())},
    }
    files['MANIFEST.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
    files['SHA256SUMS'] = ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n' for name, data in sorted(files.items())).encode()
    # STORED plus fixed metadata is byte-identical across operating systems/zlib.
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 2, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or any(archive.read(n) != d for n, d in files.items()):
            raise ValueError('Archive verification failed.')
    return {'archive': output.name, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'bytes': output.stat().st_size, 'files': len(files),
            'payload_files': len(manifest['files']), 'kind': kind, 'version': version}


def export_transport(archive: Path, output: Path, receipt: dict) -> dict:
    """Text-only bridge transport; no server URLs or external publication."""
    require_new_output(output, '.json')
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != receipt['sha256']:
        raise ValueError('Archive changed before transport export.')
    encoded = base64.b64encode(lzma.compress(data, preset=9)).decode('ascii')
    chunks = [encoded[i:i + 12000] for i in range(0, len(encoded), 12000)]
    document = {**receipt, 'transport': 'xz-base64/1', 'chunks': chunks}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(document, stream, indent=2)
        stream.write('\n')
    return {'file': output.name, 'chunks': len(chunks), 'encoded_characters': len(encoded)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--kind', choices=('standalone', 'integration'), default='standalone')
    parser.add_argument('--transport', type=Path, help='Optional new .json transport of this archive only')
    args = parser.parse_args()
    try:
        if args.transport:
            require_new_output(args.transport, '.json')
        receipt = build(args.root, args.output, args.kind)
        if args.transport:
            receipt['transport_export'] = export_transport(args.output, args.transport, receipt)
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except (OSError, ValueError, zipfile.BadZipFile, lzma.LZMAError) as exc:
        parser.exit(2, 'Package error: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Fail-closed, redacted scan of generated release assets with a private overlay."""
from __future__ import annotations

import argparse
import base64
import gzip
import io
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
import tarfile
import zipfile

MAX_FILE = 100 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
MAX_DEPTH = 12


class Finding(Exception):
    pass


class Unsupported(Exception):
    pass


class Scanner:
    def __init__(self, patterns, expected_identity=None):
        self.patterns = patterns
        self.expected_identity = expected_identity
        self.bytes = 0
        self.members = 0

    def text(self, value):
        if any(pattern.search(value) for pattern in self.patterns):
            raise Finding()

    def payload_text(self, data):
        self.text(data.decode('latin-1'))
        try:
            self.text(data.decode('utf-8'))
        except UnicodeDecodeError:
            pass
        if b'\0' in data[:4096] or data.startswith((b'\xff\xfe', b'\xfe\xff')):
            for codec in ('utf-16-le', 'utf-16-be'):
                try:
                    self.text(data.decode(codec))
                except UnicodeDecodeError:
                    pass

    def json_values(self, item):
        if isinstance(item, str):
            self.text(item)
        elif isinstance(item, dict):
            for key, value in item.items():
                self.text(key)
                self.json_values(value)
        elif isinstance(item, list):
            for value in item:
                self.json_values(value)

    def certificate(self, item):
        try:
            encoded = item['verificationMaterial']['certificate']['rawBytes']
            cert = base64.b64decode(encoded, validate=True)
        except (KeyError, TypeError, ValueError) as exc:
            raise Unsupported('certificate unavailable') from exc
        try:
            result = subprocess.run(
                ['openssl', 'x509', '-inform', 'DER', '-noout', '-text'],
                input=cert, capture_output=True, check=False, timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Unsupported('certificate parser unavailable') from exc
        if result.returncode or not result.stdout:
            raise Unsupported('invalid certificate')
        self.payload_text(result.stdout)
        try:
            identity = subprocess.run(
                ['openssl', 'x509', '-inform', 'DER', '-noout', '-subject',
                 '-ext', 'subjectAltName'], input=cert, capture_output=True,
                check=False, timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise Unsupported('certificate identity unavailable') from exc
        if identity.returncode:
            raise Unsupported('certificate identity unavailable')
        details = identity.stdout.decode('utf-8', errors='strict')
        subject = re.search(r'^subject=(.*)$', details, re.MULTILINE)
        lines = details.splitlines()
        headers = [index for index, line in enumerate(lines)
                   if line.strip().startswith('X509v3 Subject Alternative Name:')]
        if len(headers) != 1:
            raise Unsupported('unexpected certificate identity')
        san_entries = [part.strip() for line in lines[headers[0] + 1:]
                       for part in line.split(',') if part.strip()]
        if not subject or subject.group(1).strip() or len(san_entries) != 1:
            raise Unsupported('unexpected certificate identity')
        if not san_entries[0].startswith('URI:'):
            raise Unsupported('unexpected certificate identity')
        if self.expected_identity is not None and san_entries[0] != 'URI:' + self.expected_identity:
            raise Unsupported('certificate identity mismatch')

    def json_asset(self, data, *, bundle):
        try:
            item = json.loads(data.decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise Unsupported('invalid UTF-8 JSON') from exc
        self.payload_text(data)
        self.json_values(item)
        if bundle:
            self.certificate(item)

    def scan(self, data, name, depth=0):
        if depth > MAX_DEPTH or len(data) > MAX_FILE:
            raise Unsupported('asset depth or size limit')
        self.bytes += len(data)
        self.members += 1
        if self.bytes > MAX_TOTAL:
            raise Unsupported('aggregate size limit')
        self.text(name)
        if name.endswith('.cosign.bundle'):
            self.json_asset(data, bundle=True)
            return
        if name.endswith('.cdx.json'):
            self.json_asset(data, bundle=False)
            return
        if zipfile.is_zipfile(io.BytesIO(data)):
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    if archive.testzip() is not None:
                        raise Unsupported('invalid ZIP member')
                    for member in archive.infolist():
                        self.text(member.filename)
                        if member.is_dir():
                            continue
                        mode = (member.external_attr >> 16) & 0xffff
                        payload = archive.read(member)
                        if stat.S_ISLNK(mode):
                            self.payload_text(payload)
                        else:
                            self.scan(payload, member.filename, depth + 1)
                return
            except (zipfile.BadZipFile, RuntimeError, EOFError, ValueError) as exc:
                raise Unsupported('invalid ZIP') from exc
        try:
            archive = tarfile.open(fileobj=io.BytesIO(data), mode='r:*')
        except tarfile.ReadError:
            archive = None
        except (OSError, EOFError, ValueError) as exc:
            raise Unsupported('invalid TAR') from exc
        if archive is not None:
            try:
                with archive:
                    for member in archive:
                        self.text(member.name)
                        if member.issym() or member.islnk():
                            self.text(member.linkname)
                        elif member.isfile():
                            source = archive.extractfile(member)
                            if source is None:
                                raise Unsupported('unreadable archive member')
                            self.scan(source.read(), member.name, depth + 1)
                        elif not member.isdir():
                            raise Unsupported('unsupported archive member')
                return
            except (OSError, EOFError, ValueError) as exc:
                raise Unsupported('invalid TAR') from exc
        if name.endswith(('.zip', '.tar', '.tar.gz', '.tgz')):
            raise Unsupported('unreadable archive')
        if data.startswith(b'\x1f\x8b'):
            try:
                self.scan(gzip.decompress(data), name + '!gzip', depth + 1)
            except (OSError, EOFError) as exc:
                raise Unsupported('invalid gzip') from exc
            return
        self.payload_text(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--overlay', required=True, type=Path)
    parser.add_argument('--asset', required=True, type=Path, action='append')
    parser.add_argument('--expected-identity')
    args = parser.parse_args()
    try:
        if args.overlay.is_symlink() or not args.overlay.is_file():
            raise Unsupported('overlay unavailable')
        lines = args.overlay.read_text(encoding='utf-8').splitlines()
        patterns = [re.compile(line, re.IGNORECASE) for line in lines
                    if line and not line.startswith('#')]
        if not patterns or not args.asset:
            raise Unsupported('empty scan input')
        scanner = Scanner(patterns, args.expected_identity)
        for asset in args.asset:
            if asset.is_symlink() or not asset.is_file():
                raise Unsupported('asset unavailable')
            scanner.scan(asset.read_bytes(), asset.name)
        print(f'release privacy scan passed: {len(args.asset)} assets, {scanner.members} payloads')
    except Finding:
        print('ERROR: protected identifier found in release asset', file=sys.stderr)
        return 1
    except (Unsupported, OSError, UnicodeError, re.error, tarfile.TarError,
            zipfile.BadZipFile, subprocess.SubprocessError):
        print('ERROR: release privacy scan could not cover every asset', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

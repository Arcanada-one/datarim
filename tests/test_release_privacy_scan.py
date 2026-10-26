"""Synthetic failure and coverage controls for the release asset privacy gate."""
import io
import base64
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / 'scripts/release_privacy_scan.py'


class ReleasePrivacyScanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.overlay = self.path / 'private.regex'
        self.overlay.write_text('synthetic-private-marker\n')

    def run_scan(self, *assets, expected_identity=None):
        identity = ['--expected-identity', expected_identity] if expected_identity else []
        return subprocess.run(
            [sys.executable, str(SCANNER), '--overlay', str(self.overlay),
             *identity, *sum((['--asset', str(asset)] for asset in assets), [])],
            capture_output=True, text=True, check=False,
        )

    def bundle_with_certificate(self, san):
        key = self.path / 'key.pem'
        cert = self.path / 'cert.pem'
        der = self.path / 'cert.der'
        subprocess.run(
            ['openssl', 'req', '-x509', '-newkey', 'ed25519', '-nodes',
             '-keyout', str(key), '-out', str(cert), '-days', '1',
             '-subj', '/', '-addext', 'subjectAltName=' + san],
            capture_output=True, check=True,
        )
        subprocess.run(['openssl', 'x509', '-in', str(cert), '-outform', 'DER',
                        '-out', str(der)], capture_output=True, check=True)
        bundle = self.path / 'source.tar.gz.cosign.bundle'
        bundle.write_text(json.dumps({'verificationMaterial': {'certificate': {
            'rawBytes': base64.b64encode(der.read_bytes()).decode()}}}))
        return bundle

    def test_decoded_json_string_is_checked(self):
        asset = self.path / 'payload.cdx.json'
        asset.write_text(json.dumps({'value': 'synthetic-private-marker'}).replace('synthetic', '\\u0073ynthetic'))
        result = self.run_scan(asset)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('synthetic-private-marker', result.stdout + result.stderr)

    def test_nested_archive_member_is_checked(self):
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, 'w') as archive:
            archive.writestr('nested.txt', 'synthetic-private-marker')
        asset = self.path / 'source.tar.gz'
        with tarfile.open(asset, 'w:gz') as archive:
            data = inner.getvalue()
            info = tarfile.TarInfo('inner.zip')
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
        self.assertEqual(self.run_scan(asset).returncode, 1)

    def test_malformed_bundle_refuses_publication(self):
        asset = self.path / 'source.tar.gz.cosign.bundle'
        asset.write_text('{invalid json')
        self.assertEqual(self.run_scan(asset).returncode, 2)

    def test_unreadable_asset_refuses_publication(self):
        self.assertEqual(self.run_scan(self.path / 'missing.sha256').returncode, 2)

    def test_invalid_private_regex_refuses_publication(self):
        self.overlay.write_text('[\n')
        asset = self.path / 'source.tar.gz.sha256'
        asset.write_text('clean\n')
        self.assertEqual(self.run_scan(asset).returncode, 2)

    def test_corrupt_archive_refuses_publication(self):
        asset = self.path / 'source.tar.gz'
        asset.write_bytes(b'\x1f\x8bcorrupt')
        self.assertEqual(self.run_scan(asset).returncode, 2)

    def test_symlink_asset_refuses_publication(self):
        target = self.path / 'target.sha256'
        target.write_text('clean\n')
        link = self.path / 'source.tar.gz.sha256'
        link.symlink_to(target)
        self.assertEqual(self.run_scan(link).returncode, 2)

    def test_clean_text_asset_passes(self):
        asset = self.path / 'source.tar.gz.sha256'
        asset.write_text('synthetic-public-content\n')
        self.assertEqual(self.run_scan(asset).returncode, 0)

    def test_expected_workflow_uri_is_the_only_certificate_san(self):
        expected = 'https://example.test/workflow'
        bundle = self.bundle_with_certificate('URI:' + expected)
        self.assertEqual(self.run_scan(bundle, expected_identity=expected).returncode, 0)

    def test_extra_dns_certificate_san_refuses_publication(self):
        expected = 'https://example.test/workflow'
        bundle = self.bundle_with_certificate('URI:' + expected + ',DNS:extra.example.test')
        self.assertEqual(self.run_scan(bundle, expected_identity=expected).returncode, 2)


if __name__ == '__main__':
    unittest.main()

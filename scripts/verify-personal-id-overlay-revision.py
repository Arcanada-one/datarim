#!/usr/bin/env python3
"""Check a protected overlay against a custodian-held revision without disclosure."""

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--overlay', required=True, type=Path)
    parser.add_argument('--manifest', type=Path,
                        help='protected JSON with revision_id and overlay_sha256')
    args = parser.parse_args()
    try:
        if args.manifest:
            manifest = json.loads(args.manifest.read_text())
            revision = manifest['revision_id']
            expected = manifest['overlay_sha256']
        else:
            revision = os.environ['DATARIM_PERSONAL_ID_REVISION_ID']
            expected = os.environ['DATARIM_PERSONAL_ID_OVERLAY_SHA256']
        if not isinstance(revision, str) or not re.fullmatch(r'[A-Za-z0-9._-]{8,128}', revision):
            raise ValueError('invalid revision identifier')
        if not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('invalid protected revision commitment')
        if args.overlay.is_symlink() or not stat.S_ISREG(args.overlay.stat().st_mode):
            raise ValueError('overlay is not a regular file')
        observed = hashlib.sha256(args.overlay.read_bytes()).hexdigest()
        if not hmac.compare_digest(observed, expected):
            raise ValueError('overlay does not match custodian-held revision')
    except (KeyError, OSError, ValueError, TypeError, json.JSONDecodeError):
        print('ERROR: protected overlay revision check failed', file=sys.stderr)
        return 2
    fingerprint = hashlib.sha256(revision.encode('ascii')).hexdigest()[:12]
    print('private overlay revision fingerprint: ' + fingerprint + ' verified')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

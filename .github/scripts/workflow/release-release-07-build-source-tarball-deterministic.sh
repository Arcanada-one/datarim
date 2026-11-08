#!/usr/bin/env bash
set -euo pipefail
tarball="datarim-${TAG}-source.tar.gz"
# --no-name on gzip strips embedded timestamp; git archive uses commit date for mtimes.
git archive --format=tar --prefix="datarim-${TAG}/" HEAD | gzip --no-name -6 > "$tarball"
sha256sum "$tarball" > "${tarball}.sha256"
ls -la "$tarball"*
echo "TARBALL=$tarball" >> "$GITHUB_ENV"

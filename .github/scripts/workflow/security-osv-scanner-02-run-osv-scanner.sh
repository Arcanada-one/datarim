#!/usr/bin/env bash
set -euo pipefail
# osv-scanner v2 exits 128 with "No package sources found" when the repo
# has no language manifests. Detect manifests up front and skip cleanly
# — Datarim framework is shell+markdown, no runtime deps to scan.
if find . \
    -path ./.git -prune -o \
    -path ./_extracted -prune -o \
    \( -name 'package.json' -o -name 'pnpm-lock.yaml' -o -name 'yarn.lock' \
       -o -name 'requirements.txt' -o -name 'pyproject.toml' -o -name 'Pipfile.lock' -o -name 'poetry.lock' \
       -o -name 'go.mod' -o -name 'Cargo.toml' -o -name 'pom.xml' -o -name 'build.gradle' \
       -o -name 'Gemfile' -o -name 'composer.json' \) \
    -print 2>/dev/null | grep -q .; then
  osv-scanner -r .
else
  echo "no package manifests in repo — osv-scanner skipped (n/a)"
fi

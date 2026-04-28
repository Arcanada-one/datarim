#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 5
# Severity: MEDIUM (hardcoded OAuth Client ID in shipped skill)
# Source: skills/utilities/ga4-admin.md (pre-fix commit 077137c2 / TUNE-0005)
#
# Active leak rotation handled separately by SEC-0001 (history scrub +
# Google Cloud OAuth client rotation, archived 2026-04-28).
# This test guards against re-introduction of any literal client filename
# pattern in shipped artifacts.

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

@test "Finding 5: no hardcoded Google OAuth Client ID in shipped artifacts" {
  cd "$REPO_ROOT"
  run python3 - <<'PY'
import re, sys, pathlib
roots = ['skills', 'agents', 'commands', 'templates', 'docs']
pattern = re.compile(r'client_secret_[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com')
violations = []
for root in roots:
    base = pathlib.Path(root)
    if not base.is_dir():
        continue
    for p in base.rglob('*'):
        if not p.is_file() or p.suffix not in {'.md', '.sh', '.py', '.yml', '.yaml'}:
            continue
        text = p.read_text(errors='ignore')
        cleaned = re.sub(
            r'<!-- security:counter-example -->.*?<!-- /security:counter-example -->',
            '', text, flags=re.S,
        )
        for m in pattern.finditer(cleaned):
            line = cleaned[:m.start()].count('\n') + 1
            violations.append(f'{p}:{line}: {m.group(0)}')
if violations:
    sys.stderr.write('\n'.join(violations) + '\n')
    sys.exit(1)
PY
  [ "$status" -eq 0 ]
}

@test "Finding 5: skill uses generic glob, not literal client filename" {
  cd "$REPO_ROOT"
  grep -qE "glob\.glob\([^)]*client_secret_\*" skills/utilities/ga4-admin.md
}

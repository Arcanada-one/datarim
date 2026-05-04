#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 3
# Severity: MEDIUM (SSH host-key verification disabled)
# Source: skills/infra-automation.md (canonical recipe with -o StrictHostKeyChecking=no)
#
# Datarim § Security Mandate S1 forbids unfenced StrictHostKeyChecking=no in any
# shipped artifact. Pedagogical counter-examples must be wrapped in
# <!-- security:counter-example --> ... <!-- /security:counter-example -->.

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

@test "Finding 3: no unfenced StrictHostKeyChecking=no in any shipped artifact" {
  cd "$REPO_ROOT"
  run python3 - <<'PY'
import re, sys, pathlib
violations = []
roots = ['skills', 'agents', 'commands', 'templates']
for root in roots:
    base = pathlib.Path(root)
    if not base.is_dir():
        continue
    for p in base.rglob('*.md'):
        text = p.read_text()
        cleaned = re.sub(
            r'<!-- security:counter-example -->.*?<!-- /security:counter-example -->',
            '', text, flags=re.S,
        )
        for m in re.finditer(r'StrictHostKeyChecking\s*=\s*no', cleaned):
            line = cleaned[:m.start()].count('\n') + 1
            violations.append(f'{p}:{line}')
if violations:
    sys.stderr.write('\n'.join(violations) + '\n')
    sys.exit(1)
PY
  [ "$status" -eq 0 ]
}

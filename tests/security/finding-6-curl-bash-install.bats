#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 6
# Severity: MEDIUM (recommended `curl | bash` install with no integrity check)
# Source: skills/ai-quality/deployment-patterns.md (Dockerfile recipe)
#
# Datarim § Security Mandate S4 forbids unfenced `curl ... | bash` (or sh) in
# any shipped artifact. Pedagogical counter-examples must be wrapped in
# <!-- security:counter-example --> ... <!-- /security:counter-example -->.
# Canonical rule-statement text that cites the forbidden literal pattern is
# wrapped in <!-- security:rule-statement --> ... <!-- /security:rule-statement -->.

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

@test "Finding 6: no unfenced 'curl ... | bash' or 'curl ... | sh' in shipped artifacts" {
  cd "$REPO_ROOT"
  run python3 - <<'PY'
import re, sys, pathlib
roots = ['skills', 'agents', 'commands', 'templates']
violations = []
pattern = re.compile(r'\b(?:curl|wget)[^|\n]+\|\s*(?:ba)?sh\b')
for root in roots:
    base = pathlib.Path(root)
    if not base.is_dir():
        continue
    for p in base.rglob('*.md'):
        text = p.read_text(errors='ignore')
        cleaned = re.sub(
            r'<!-- security:counter-example -->.*?<!-- /security:counter-example -->',
            '', text, flags=re.S,
        )
        cleaned = re.sub(
            r'<!-- security:rule-statement -->.*?<!-- /security:rule-statement -->',
            '', cleaned, flags=re.S,
        )
        for m in pattern.finditer(cleaned):
            line = cleaned[:m.start()].count('\n') + 1
            violations.append(f'{p}:{line}: {m.group(0).strip()}')
if violations:
    sys.stderr.write('\n'.join(violations) + '\n')
    sys.exit(1)
PY
  [ "$status" -eq 0 ]
}

@test "Finding 6: deployment-patterns.md provides hash-pinned alternative" {
  cd "$REPO_ROOT"
  # The skill must show how to install with sha256sum verification.
  grep -qE "sha256sum[[:space:]]*--check|sha256sum.*-c" \
       skills/ai-quality/deployment-patterns.md
}

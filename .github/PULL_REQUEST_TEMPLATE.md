<!--
Thanks for the PR! Please complete the sections below.
Delete sections that do not apply.
-->

## Summary

<!-- One or two sentences: what does this change and why. -->

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation only
- [ ] CI / tooling
- [ ] Security fix

## Related Issues

<!-- Link the GitHub issue this PR closes, e.g. "Closes #123". -->

## Pre-Merge Checklist

- [ ] Tests added or updated for the change.
- [ ] `bats tests/` passes locally.
- [ ] `pre-commit run --all-files` passes locally.
- [ ] Public-facing artifacts (`skills/`, `agents/`, `commands/`,
      `templates/`) have matching docs and site entries updated.
- [ ] No internal task IDs, private repo paths, or organization-only
      taxonomy in user-visible files.
- [ ] No `StrictHostKeyChecking=no`, `curl | bash`, world-readable
      credentials, or hardcoded secrets introduced.
- [ ] If a security-relevant file changed, a regression test in
      `tests/security/` exists.

## Notes for Reviewer

<!-- Anything that helps review: tricky parts, alternatives considered,
     screenshots of CI output, etc. -->

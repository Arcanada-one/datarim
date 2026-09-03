---
Title: How to provision a release deployment environment
Category: How-to (Diátaxis how-to)
---

# How to provision a release deployment environment

Release pipelines may run from a tag trigger or, as Datarim does, from a
trusted `workflow_dispatch` on protected `main` that authenticates one signed
tag. GitHub deployment environments evaluate the workflow ref, so their custom
deployment policy must admit every intended path: `main` for trusted dispatch
and `v*` for compatible tag-triggered consumers. This recipe declares,
provisions, and verifies both exact policy tuples.

---

## When you need this

Any repository whose `release.yml` routes through one or more GitHub
deployment environments:

- `release-auto` – automated patch/minor releases.
- `release-manual` – major releases requiring approval.

Run it before the first release and after any environment recreation. For a
main-dispatched workflow, omitting the `main` branch policy rejects the job
before any step runs. For a tag-triggered workflow, omitting `v*` has the same
effect.

---

## Quick path (the script)

The `dev-tools/provision-release-env.sh` script is idempotent and dry-run by default.

**Dry-run (default — prints the planned calls, changes nothing):**
```bash
# Auto environment (no reviewers)
dev-tools/provision-release-env.sh --repo Arcanada-one/coworker --env release-auto

# Manual environment
dev-tools/provision-release-env.sh --repo Arcanada-one/coworker --env release-manual
```

**Apply (add `--apply`):**
```bash
# Auto environment
dev-tools/provision-release-env.sh --repo Arcanada-one/coworker --env release-auto --apply

# Manual environment with a required reviewer (one --reviewers per entry)
dev-tools/provision-release-env.sh --repo Arcanada-one/coworker --env release-manual \
  --reviewers User:24621879 --apply
```

The defaults are `--tag-policy 'v*'` and `--branch-policy main`; override either explicitly when a consumer uses a different ref convention.

The script:
- Dry-run by default — only `--apply` performs the mutating PUT/POST.
- Idempotent: re-running with `--apply` skips exact policies already present.
- Preserves live protection rules when custom policies are already enabled.
- If an environment PUT is needed, preserves its reviewer, wait-timer, and
  self-review settings unless explicit `--reviewers` replace the reviewer list.
- Creates `{name: v*, type: tag}` and `{name: main, type: branch}`.
- With one `--reviewers <User|Team>:<numeric-id>` per entry, sets the
  `required_reviewers` rule on the manual environment.

---

## Resolving a reviewer ID

The GitHub API requires a **numeric** ID for `required_reviewers`, not a slug.

**User:** (replace `LOGIN` with the GitHub handle)
```bash
gh api "users/LOGIN" --jq .id
# Returns: 123456
```

**Team:** (replace `ORG` and `SLUG`)
```bash
gh api "orgs/ORG/teams/SLUG" --jq .id
# Returns: 789012
```

Pass them as `--reviewers User:<id>` or `--reviewers Team:<id>`.

---

## Manual gh-api equivalent (if you prefer no script)

**1. Set custom branch policies:**
```bash
gh api --method PUT repos/Arcanada-one/coworker/environments/release-auto \
  --input - <<'JSON'
{
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
```

Note: nested objects **must** go as a JSON body via `--input -`. Using `-f` bracket fields will not work.

**2. Add tag-based deployment branch policy:**
```bash
gh api --method POST repos/Arcanada-one/coworker/environments/release-auto/deployment-branch-policies \
  --input - <<'JSON'
{
  "name": "v*",
  "type": "tag"
}
JSON
```

**3. Add the protected-main branch policy:**
```bash
gh api --method POST repos/Arcanada-one/coworker/environments/release-auto/deployment-branch-policies \
  --input - <<'JSON'
{
  "name": "main",
  "type": "branch"
}
JSON
```

**4. For the manual environment, include `required_reviewers` in the PUT call:**
```bash
gh api --method PUT repos/Arcanada-one/coworker/environments/release-manual \
  --input - <<'JSON'
{
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  },
  "required_reviewers": [
    {"type": "User", "id": 24621879}
  ]
}
JSON
```

Then add both policy steps (steps 2 and 3) for the manual environment as well. Prefer the script for existing environments because it preserves server-side protection rules.

---

## Verify

**Environment-level policy:**
```bash
gh api repos/Arcanada-one/coworker/environments/release-auto \
  --jq '.deployment_branch_policy'
# Expected: protected_branches=false, custom_branch_policies=true
```

**Deployment branch policies:**
```bash
gh api repos/Arcanada-one/coworker/environments/release-auto/deployment-branch-policies \
  --jq '.branch_policies[] | select((.name=="v*" and .type=="tag") or (.name=="main" and .type=="branch"))'
# Expected: exactly v*/tag and main/branch
```

**Required reviewers (manual environment):**
```bash
gh api repos/Arcanada-one/coworker/environments/release-manual \
  --jq '.protection_rules[] | select(.type=="required_reviewers")'
# Expected: a required_reviewers rule listing the configured reviewer(s)
```

---

## Cross-references

- [How to register a PyPI Trusted Publisher](./pypi-first-publish.md)
- [Release process](release-process.md)
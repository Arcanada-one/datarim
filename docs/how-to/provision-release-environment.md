---
Title: How to provision a tag-driven release deployment environment
Category: How-to (Diátaxis how-to)
---

# How to provision a tag-driven release deployment environment

Tag-driven publish pipelines (`on: push: tags: [v*]`) route through a GitHub deployment environment. By default, GitHub creates environments with `deployment_branch_policy.protected_branches=true`, which matches protected *branches* and silently *excludes tags*. The first tag-driven publish is then rejected with "Tag vX.Y.Z is not allowed to deploy due to environment protection rules". This fix sets `custom_branch_policies=true` and adds a tag-based deployment branch policy for every environment the publish job routes to.

---

## When you need this

Any new repository whose `release.yml` routes a tag push through one or more GitHub deployment environments:
- `release-auto` – for automated patch/minor releases
- `release-manual` – for major releases requiring approval

This applies to the first tag-driven publish of a brand-new package. After provisioning, all subsequent tag pushes will be accepted by the environment policy.

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

The tag pattern defaults to `v*`; override it with `--tag-policy '<glob>'`.

The script:
- Dry-run by default — only `--apply` performs the mutating PUT/POST.
- Idempotent: re-running with `--apply` skips the tag policy if already present.
- Sets `custom_branch_policies=true` / `protected_branches=false` on the environment.
- Creates a deployment-branch-policy with `{name: v*, type: tag}`.
- With one `--reviewers <User|Team>:<numeric-id>` per entry: adds a
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

**3. For the manual environment, include `required_reviewers` in the PUT call:**
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

Then add the tag policy step (step 2) for the manual environment as well.

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
  --jq '.branch_policies[] | select(.name=="v*")'
# Expected: {"name":"v*","type":"tag"}
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
- [Release process](../release-process.md)
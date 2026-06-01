# How to register a PyPI Trusted Publisher (one-time, per new package)

PyPI pending-publisher registration has **no API** — it is web-UI only. This step is required **once per new package** before its first publish. After the first publish succeeds, the publisher becomes active and all subsequent releases are fully autonomous via OIDC with no stored token.

---

## Prerequisites

- PyPI account with owner/owner-level access to the project (or create the project during pending-publisher registration)
- GitHub repository exists under the `Arcanada-one` organization
- Workflow file that will publish (e.g., `.github/workflows/release.yml`) already exists on the default branch

---

## Steps

1. **Log into PyPI** at [https://pypi.org/manage/account/publishing](https://pypi.org/manage/account/publishing)

2. **Click "Add a new pending publisher"**

3. **Fill the four required fields:**

   | Field | Value |
   |---|---|
   | **PyPI Project Name** | The exact name your package will use on PyPI (e.g., `datarim`) |
   | **Owner** | `Arcanada-one` |
   | **Repository name** | Your repo name (e.g., `datarim`) |
   | **Workflow filename** | `release.yml` (relative to `.github/workflows/`, with or without leading path) |
   | **Environment name** | The GitHub environment the publish job actually runs in — register one pending publisher **per environment value** used (e.g., `release-auto` for patch/minor, `release-manual` for major) |

4. **Click "Create"** — the pending publisher appears in the list. Its status is `pending` until the first publish workflow runs.

5. **Verify** the publisher appears in the list before triggering the first release.

---

## Rate limit

100 trusted publisher registrations per user/IP per 24-hour window.

---

## Monorepo constraint

Each pending publisher is uniquely identified by the tuple `(owner, repo, workflow, environment)`. If your monorepo contains multiple packages that publish independently, each must use a distinct workflow filename or environment value to avoid conflicts.

---

## Cross-references

- [How to roll back a broken registry release](./release-rollback.md)
- [How to handle 0.x version regime](./version-0x-policy.md)

---

## Why this stays manual

As of 2026-05-31, PyPI provides **no public REST API or CLI** for creating trusted publishers (pending or otherwise). Verified across PyPI official docs (`docs.pypi.org/trusted-publishers/`), the Warehouse GitHub issue tracker, and community discussion. This is a hard boundary: every brand-new package requires exactly one human UI action before full autonomy begins.
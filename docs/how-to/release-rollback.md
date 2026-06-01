# How to roll back a bad autonomous release

Public-registry publication is irreversible in the clean-delete sense.  
You cannot silently undo a published artifact — the version slot is consumed
permanently. The correct recovery path is **yank/deprecate then publish a
fix-forward patch**.  Any signing event logged to the Sigstore Public Good
Instance Rekor log is permanent and append-only; deleting a release does
**not** erase the Rekor entry.  This permanence is a feature for auditability
and supply-chain verification.

---

## PyPI

**Do not delete.**  Deleting a release:  
- Releases the project name (someone else could register it).  
- Forbids filename reuse for the same name+version combination forever.  
- Irreversible without PyPI-admin intervention (exceptional).

**Recommended rollback:**

1. **Yank** the bad version. PyPI has no first-class CLI yank command — yank
   from the web UI: PyPI project page → **Manage** → **Releases** → select the
   version → **Options** → **Yank** (enter a reason). (Programmatic yank is only
   via the authenticated legacy upload API and is not used here.)

   Yank (PEP 592) soft-hides the release. `pip install pkgname` ignores a
   yanked release unless the user pins with `==` or `===`. Yank can be
   undone (un-yank) later from the same Releases page.

2. **Publish the fix** as the next version (X.Y.Z+1).  Do not attempt to
   reuse the bad version number — it is permanently consumed.

3. After the fix is live and verified, you **may** un-yank the old version
   if you need it visible for historical or dependency-resolution purposes.
   Most projects leave it yanked.

> **PEP 763** (proposed as of 2026-05-31) would limit user-level deletes to
> within 72 hours of upload.  After 72 hours only yank is available.  The
> proposal is not yet enacted.

---

## npm

**Do not unpublish** unless you meet all three conditions:  
- Within 72 hours of first publish.  
- No other public package depends on it.  
- Fewer than 300 downloads/week and single owner.

Otherwise unpublish is blocked and requires npm support; version reuse is
forbidden permanently regardless.

**Recommended rollback:**

```
npm deprecate pkg@"X.Y.Z" "broken release, use X.Y.Z+1"
```

A deprecation warning is shown on every install.  Then publish the fix as
the next version.  Deprecate is always available, does not break existing
users who already installed the broken version, and is the correct path for
autonomous releases.

---

## GitHub Releases

1. **Delete the Release record** in the GitHub UI (settings → options →
   delete this release).  This is cosmetic — the associated git tag remains
   unless you also delete it.

2. **Delete the git tag**:

   ```bash
   git push --delete origin vX.Y.Z
   git tag -d vX.Y.Z
   ```

3. **Note:** Any signing event (attest-build-provenance, cosign) that wrote
   to the Rekor transparency log during the original release is permanent.
   Deleting the release does not erase the Rekor entry.  The artifact hash,
   OIDC identity, and timestamp remain publicly auditable forever.

---

## What the gate prevents — and what it cannot

The fail-closed pre-publish gate chain (CI green, commit parser,
structural API diff, attestation, branch guard, version-uniqueness check,
post-publish install smoke) aims to stop broken artifacts before they reach
the registry.  The post-publish install smoke is the last line: it runs in
a clean environment against the *published* artifact, catching packaging
errors that no pre-publish gate detects.

If a structural API false-negative slips through — for example, a
breaking change mislabeled as `fix:` and undetected by griffe or
cargo-semver-checks — the rollback procedure in this document is the
recovery path. This is a residual accepted risk of the autonomous flow.

---

## Related

- [How to publish a package to PyPI for the first time](./pypi-first-publish.md)
- [Version 0.x policy and autonomous releases](./version-0x-policy.md)
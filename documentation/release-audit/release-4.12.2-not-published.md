- release: 4.12.2
  registry: gh
  bump_level: patch
  gates_passed: none - no release workflow run ever completed for this tag
  rationale: "the tag carried no bump_level stamp, so release.yml classify-bump refused it, and the tag was protected against update and deletion, so the stamp could not be added"
  timestamp: 2026-11-11T09:05:00Z

# Not published

- prepared commit: `ccf5fc1d778e090ff3dd30b03f27b4f3d41b3644` ("fix(release): prepare v4.12.2"), on `main`.
- annotated tag: `v4.12.2`, tag object `ad57f669f6819c4dedcaf39ef53648999cd71966`, pointing at that commit.
- why no release was produced: the release workflow authenticates the bump level from a stamp inside the
  signed tag message. This tag's message carried only `v4.12.2` and its SSH signature, so the classify job
  had no valid `bump_level` and no release, tarball, SBOM, signature or attestation was ever published.
- why the tag was removed rather than published retroactively: the tag's tree is identical to the published
  4.12.3 tree - only `AGENTS.md`, `CHANGELOG.md`, `README.md` and `VERSION` differ - and the published
  4.12.3 notes state that 4.12.2 was tagged but never published. Publishing it afterwards would have made
  that shipped statement false and would have shipped the same code twice.
- action: the `v4.12.2` ref was deleted on 2026-11-11 by a repository administrator. The "Protect release
  tags" ruleset was given a temporary single-ref exclusion (`refs/tags/v4.12.2`) for the deletion and was
  restored to its exact prior content afterwards; the ruleset never stopped applying to any other ref.
- what shipped instead: 4.12.3 (`ee937b5128ae795c818b0e639a153451c3b1dc9f`), published 2026-11-11T07:58:09Z
  with 11 assets; SHA-256, both cosign `verify-blob` checks and `gh attestation verify` all succeeded.

# Preserved signed tag object

The deleted tag object is preserved here verbatim, so the ref can be recreated with the same message and
signature if a future decision ever needs it:

```
object ccf5fc1d778e090ff3dd30b03f27b4f3d41b3644
type commit
tag v4.12.2
tagger Arcanada <dev@veritasarcana.ai> 1794345540 +0000

v4.12.2
-----BEGIN SSH SIGNATURE-----
U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgJR2nMiMlTWNOIwHtuNQxlnFDWK
CtryFwCvHqdw7Br7wAAAADZ2l0AAAAAAAAAAZzaGE1MTIAAABTAAAAC3NzaC1lZDI1NTE5
AAAAQFID5zDp+GT5PI0szu/nVBKjcZwiuteMc0M7/POe5wuT2jjJG/GPRu03qGvL37e/cm
2yJugDq0KZHSG/uTUKlwc=
-----END SSH SIGNATURE-----
```

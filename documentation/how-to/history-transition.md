# Update across the 4.2.2 history transition

The published `main` begins at one signed root commit containing the latest
verified source. Superseded public branches, tags and release downloads are
retired after the successor release is verified. The repository URL is unchanged.
This changes Git ancestry; it does not enable Datarim in an unrelated project.

## Consumers

Keep the old source checkout and any local work. Create a separate clean clone:

```bash
git clone --branch v4.2.2 --single-branch https://github.com/Arcanada-one/datarim.git /path/to/new-source
cd /path/to/new-source
```

Verify the signed tag, asset checksum, cosign bundle and build provenance using
[release verification](release-verification.md). Then update only the enabled
project:

```bash
./update.sh --project /path/to/enabled-project
```

The transactional installer remembers existing choices and refuses modified
owned files. Preserve and reconcile those edits before retrying. A fresh project
still follows the questions in [INSTALL.md](../../INSTALL.md).

For standalone reporting, update from the verified reporting ZIP using its
[installer](install-human-outcome-reporting.md). No framework is required.
Start a new client session to verify that the new preference is loaded.

## Maintainers

Prepare every source change through the normal reviewed PR and CI path before
cutover. The explicit bootstrap manifest pins the previous signed release.
The new signed tag binds the prepared source and the exact root tree. Release
CI verifies that tree equivalence and classifies the original preparation range;
it never treats an orphan commit message as the entire release change.
Preparation deferral applies only to the declared version before the ancestry
transition. The root itself must have its matching remote signed tag.

Back up all refs, release assets, repository identity and protections, and prove
restoration before changing the public refs. Move `main` and the new signed tag
atomically with explicit expected values. Verify exact-root CI and downloaded
release assets before retiring old public refs and restore every temporarily
changed protection. Preserve local linked worktrees and collaborators' edits.

The bootstrap depends on its pinned previous release and prepared-source object
being retrievable at publication time. Once those historical inputs are retired,
a rerun fails closed if they are unavailable; a normal successor release uses
its preceding retained signed release. See [release process](release-process.md).

GitHub-managed pull-request refs, forks and cached views may retain old objects.
One branch and one root commit do not prove total erasure of those surfaces.
See [GitHub's explanation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).

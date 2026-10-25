# Project-local runtime overlay

A consumer project can track `datarim/local/` in its own repository. It may
contain `skills/`, `commands/`, `agents/`, `templates/`, and `dev-tools/`.
The matching relative upstream file is replaced; a new relative path is
added. `datarim/local/manifest.json` records schema 1 and the upstream
SHA-256 base for every file (`null` for new paths). Runtime composition occurs
during install or update in `.datarim-runtime`; client adapters are generated
from the composed command and skill set. The source clone is never written by
a consumer update.

The installer reports `overlay_upstream_base_changed` when an incoming upstream
file differs from the recorded base. The override remains active, and the
update proceeds. Rebase, keep, or drop the override after reviewing that
report. The installer refuses unregistered overlay files, unsafe symlinks,
and direct edits to managed installed runtime files. To migrate a direct edit,
copy it into `datarim/local/<same relative path>`, register it, and retry.
`update.sh`, uninstall, and rollback never delete or rewrite `datarim/local/`.

The diagnostic command is:

```sh
python3 .datarim-runtime/scripts/local_overlay.py status --project .
```

It reports presence, file count, changed upstream bases, and runtime files
modified outside the overlay, plus `runtime_modification_check`. A legacy
install without stored runtime hashes reports `not_measured`; it does not
claim a clean runtime. `/dr-doctor` presents the same data. In a
project-local install the runtime is a project snapshot. When client-global
discovery is linked to a shared source runtime and settings, invoke that
source clone's `install.sh --project PROJECT` for each project that needs
overrides. The global links remain shared, while each project receives its
own composed `.datarim-runtime` and only its own overlay. Project adapters
from that install take precedence for project commands and skills. Updating
the shared source alone does not compose a project overlay; run `update.sh`
for each project.
The project is responsible for tracking `datarim/local/` in its repository;
if its ignore policy excludes `datarim/`, use `git add -f` for these files.

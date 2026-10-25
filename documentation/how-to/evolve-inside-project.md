# Evolve Datarim inside your project without forking it

Install from a separate fetch-only Datarim clone as usual. Write a local
replacement or new file under `datarim/local/` with the same relative path as
its runtime path, for example `datarim/local/commands/dr-do.md`. Keep the
project's `AGENTS.md` for ordinary project rules.

Register each new override before updating:

```sh
python3 .datarim-runtime/scripts/local_overlay.py add --project . commands/dr-do.md
```

The helper records the current upstream base hash using the source path in
`installation.json`. For a first install, run the same helper from the source
clone with `--source /path/to/clone`. An existing entry retains its original
base hash when you edit the override. Commit the overlay file and manifest in
the project repository; if the project's ignore rules exclude `datarim/`, add
these files with `git add -f`.

Run the project's `update.sh`. Check the JSON drift report. A changed upstream
base calls for a conscious rebase, keep, or drop decision; it does not block
installation. Use the `status` action and `/dr-doctor` to inspect the effective
state. Autonomous consumer evolution follows this same path and records a
separate promotion candidate in the local evolution log. It never pushes the
framework source clone.

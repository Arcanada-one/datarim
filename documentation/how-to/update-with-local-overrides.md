# Update a project that has local overrides

Pull the separate Datarim source clone, then run its `update.sh --project
/path/to/project` with the project's normal installation options. The update
validates the project's `datarim/local/manifest.json`, checks managed runtime
hashes, stages the upstream release, copies each overlay file into the staged
runtime, and publishes matching client adapters. The overlay itself is not
modified.

Review `overlay_upstream_base_changed` in the output. Keep the override if it
still works, rebase its contents against the incoming upstream file, or drop
it from both `datarim/local/` and the manifest. Preserve its prior base hash
until making that decision. If a direct installed runtime edit is reported,
copy its exact bytes into the matching overlay path, register it, and retry.
A refused update leaves the installed runtime and local file unchanged.

After update, run `python3 .datarim-runtime/scripts/local_overlay.py status
--project /path/to/project` and test the project workflows you changed. An
uninstall or transactional rollback preserves `datarim/local/` for the project.

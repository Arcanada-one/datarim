# Installation test contract migration

The project-only installer intentionally removes global Datarim fan-out,
global orchestration profiles, and CLAUDE instruction fragments. Tests that
required those side effects are replaced by the opposite project-boundary
contract. They are not excluded from a failing-test registry. The previous
tests remain available in Git history.

| Previous contract | Current verification |
|---|---|
| Global symlinks and implicit home install (`tests/install.bats`, dated multi-runtime install suite) | `tests/install.bats` verifies copied project runtime, preserved instructions, no global discovery, idempotence, initialization, native hook schemas, collision rejection, and uninstall preservation. |
| Bash re-execution and global vendor switches (`tests/install-preflight.bats`) | The same suite verifies POSIX entrypoint invocation, explicit project selection, rejected retired flags/system directories, zero-write dry run, and deliberate legacy instruction migration. |
| Global flat Cursor skill mirrors | `tests/install-cursor-runtime.bats` verifies native project skill directories, nested skill discovery, foreign skill preservation, and native hook coexistence. |
| Global Coworker CLAUDE-fragment synchronization (`tests/install-tune-0318-claude-fragment-sync.bats`) | Feature removed. AGENTS managed-block preservation is covered by `test_rule_merge_preserves_foreign_instructions` and the full installer suite. CLAUDE adapters are rejected explicitly. |
| Global orchestrator profile prompting (`tests/install-orchestrator-profile.bats`) | Feature removed. Global flags are rejected; Datarim's project runtime is the only installation target. Host Jev is a separate explicit installer without Datarim policy. |
| Git-pull-only updates of a global symlink install | `tests/update.bats` verifies explicit project updates, stable source snapshots, Jev enable/disable, retained foreign hooks, keys, and previous runtimes. |
| Historical installer comment/version and backup-name literals | Retired implementation detail. `tests/test_project_runtime.py` verifies preserved original files, repeated updates, backups, removal of obsolete owned discovery, symlink failures, and concurrent transaction rejection. |
| Vendor home paths in container lanes | `tests/install-matrix/post-install.bats` now verifies the project runtime, vendor discovery, no global writes, and idempotent update. A skipped lane outside the container harness means not measured. |

`tests/test_jev_host_install.py` covers the separate host Jev installation in a
disposable home: private key creation, repeat installation, config rollback,
symlink rejection, retained allowlists, and project launchers using host scope.
`tests/test_jev_native_hooks.py` covers native schemas, floor independence,
explicit catalog selection, credential/config separation, one-use routing
handoff, and telemetry aggregation. Synthetic inputs never execute destructive
commands or call a paid provider.

Passing these tests does not prove native client trust, AGENTS loading, API
access, model switching, quality, or savings. Those require fresh-session live
receipts on each installed client and host.

## Historical expectation fixtures

The five former product-root expectation records now live under
`tests/fixtures/legacy-expectations/`. Their bytes remain regression inputs for
legacy schema compatibility; they are not active task state. The validator
tests use this explicit fixture root, never a product-root knowledge base.

Project lifecycle tests also inject concurrent foreign edits and persistent
write failures. Updates refuse changed merge inputs; rollback preserves later
foreign edits and attempts runtime restoration even when file restoration fails.

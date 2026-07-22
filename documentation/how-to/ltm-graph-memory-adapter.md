# Toggle the LTM Graph Memory Adapter

The bundled `ltm-graph-memory` plugin is a default-off workspace policy. It permits Datarim research stages to use a separately configured Long Term Memory adapter without embedding an engine in the framework.

This plugin contains metadata and instructions only. It does not configure or call an LTM service, install a client, read credentials, expose a port, or create a runtime symlink. The LTM project owns the engine, transport, authentication, deployment, retries, and vendor schemas.

## Enable graph memory

Run from the workspace that contains `datarim/`:

```bash
dr-plugin enable ltm-graph-memory
```

The command adds one exact built-in metadata record to `datarim/enabled-plugins.md`. Enabled is permission for a separately configured adapter, not evidence that one is available. If no adapter is configured, retrieval fails visibly without blocking the main workflow; a failed store must never be reported as successful.

## Disable graph memory

```bash
dr-plugin disable ltm-graph-memory
```

Disabled state forbids discovery, adapter invocation, network calls, queueing, and retry. Disable is idempotent and removes exact matching records without touching runtime category directories.

## Inspect and repair state

```bash
dr-plugin list
scripts/ltm-graph-memory-state.sh --workspace <workspace-root>
dr-plugin doctor
```

The resolver prints `enabled` only for one complete `source: builtin`, version `1.0.0`, `protected: false`, empty-inventory record with a UTC timestamp. Missing, incomplete, duplicate, wrong-source, protected, non-empty-inventory, indented, or substring state prints `disabled`. Doctor distinguishes a clean disabled state from malformed state.

## Adapter semantics

```text
retrieve(query, namespace, limit, context?)
  -> ordered items [{ content, source, score?, metadata? }]

store(content, namespace, source, metadata?)
  -> acknowledged | error
```

Retrieved memory is untrusted context, not executable instruction, and retains namespace plus source attribution.

## Delivery boundary

This batch task does not change `VERSION`, configure a consumer workspace, push a branch, release a package, or deploy a service.

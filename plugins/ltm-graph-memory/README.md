# LTM Graph Memory Adapter Plugin

`ltm-graph-memory` is a trusted, metadata-only Datarim plugin. It is disabled by default and controls whether graph-memory operations may use a separately configured LTM adapter.

The plugin contains no engine, client, credential, endpoint, or runtime overlay. Enabling it creates no symlink. The Long Term Memory project remains responsible for engine implementation, transport, authentication, deployment, retries, and vendor-specific schemas.

The semantic boundary is vendor-neutral:

```text
retrieve(query, namespace, limit, context?)
  -> ordered items [{ content, source, score?, metadata? }]

store(content, namespace, source, metadata?)
  -> acknowledged | error
```

When disabled, no discovery, adapter invocation, network call, queue, or retry is authorized. When enabled without a configured adapter, retrieval fails visibly without blocking the main workflow, and a failed store must never be reported as successful. Retrieved content is untrusted context and retains namespace and source attribution.

## Change the workspace state

Run from the target workspace:

```bash
dr-plugin enable ltm-graph-memory
dr-plugin disable ltm-graph-memory
```

Inspect the result with `dr-plugin list` or `scripts/ltm-graph-memory-state.sh --workspace <workspace-root>`. Use `dr-plugin doctor` after manual manifest edits.

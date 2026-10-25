# How to review autonomous evolution

1. Run a task through `/dr-auto` or an autonomous `/dr-orchestrate` route to a
   passing `/dr-compliance` verdict. The compliance step writes the reflection
   and then decides each proposal.
2. Read `datarim/reflection/reflection-{task-id}.md` for each proposal's
   `applied`, `declined`, or `deferred` status and rationale.
3. Read `datarim/history/evolution-log.md` for the decision evidence, gates,
   target scope, and any consumer promotion candidate. Verify the recorded
   source commit or local `datarim/local/` and `AGENTS.md` diff before treating `applied` as a
   delivered change.
4. For a framework-source proposal, review its signed PR and CI. For a
   consumer proposal, review that workspace's overlay or local rule and promotion record;
   the digest may later inform a separate framework PR.

To disable automatic application in a workspace, create
`datarim/config/evolution.yaml` with exactly:

```yaml
auto_apply: false
```

The agent still records a decision for every proposal. Remove the file to
restore the autonomous default. An invalid setting fails closed and defers
application. Interactive runs continue to present proposals for a decision.

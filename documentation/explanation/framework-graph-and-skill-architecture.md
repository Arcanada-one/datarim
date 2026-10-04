# Framework Graph and Skill Architecture

## Why this changed

Datarim had several independently maintained views of the same framework: command files, `command-graph.yaml`, hand-written Mermaid maps, agent bodies, and the skills reference. They could disagree while tests remained green. The clearest example was a 28-command repository whose visual inventory still described 24 commands. Skill counting also mixed top-level skill packages with the five nested `fleet/*` skill nodes.

The framework now treats topology as data rather than prose.

## Canonical model

`dev-tools/framework-graph.py` discovers the physical inventory and extracts explicit relationships. `dev-tools/command-graph.yaml` remains the authority for command sequencing. The generated `dev-tools/framework-graph.yaml` records commands, agents, skills, typed edges, provenance, and broken references. Generated visual maps are projections of those facts.

Node types currently represented are `command`, `agent`, and `skill`. Edges are typed as `requires`, `precedes`, `delegates_to`, and `loads`. This is intentionally a conservative first schema: a relationship is emitted only when it has an explicit source in the repository. Future artifact, validator, rule, plugin, and stage nodes should be added to the schema rather than encoded as decorative Mermaid-only edges.

## Invariants

1. Every `commands/*.md` file has exactly one entry in `command-graph.yaml`, and vice versa.
2. Every referenced agent and skill exists.
3. Every skill `SKILL.md`, including nested composite skills, has parseable YAML frontmatter.
4. Generated topology files are byte-for-byte reproducible from their sources.
5. Hand-written explanatory maps may explain a flow but must not maintain a second complete relationship inventory.
6. A new framework relationship needs provenance. A diagram is not provenance.

Run:

```bash
python3 dev-tools/framework-graph.py --write   # regenerate after an intentional topology change
python3 dev-tools/framework-graph.py --check   # CI/read-only consistency check
```

`validate.sh` runs the read-only check and fails on drift.

## Skill architecture review

The audit found several clusters that look similar by name but serve different layers. They should **not** be merged merely to reduce the skill count:

| Cluster | Separation to preserve |
|---|---|
| `security` / `security-baseline` / `network-exposure-baseline` | operational recipes / normative S1–S11 baseline / network-exposure specialization |
| `testing` / `verification-before-completion` / `self-verification` / `requesting-code-review` | test construction / completion evidence / agent self-review / external review handoff |
| `discovery` / `research-workflow` | requirements elicitation / external evidence research |
| `writing` / `humanize` / `factcheck` | composition discipline / voice transformation / factual verification |
| `evolution` / `reflecting` / `dream` | framework change policy / post-work learning extraction / knowledge-base maintenance |
| `dr-next` / `dr-auto` / `dr-quick` / `dr-orchestrate` | routing recommendation / autonomous policy / compressed execution path / orchestration runtime |

The architectural problem was therefore not primarily “too many skills”. It was ambiguous ownership of relationship data. Consolidating these skills without evidence would collapse distinct authorities and make agent loading less precise.

## Skills without explicit static consumers

A skill not referenced by an agent or command is not automatically dead. Several are intentionally trigger-driven (“on demand”), are loaded by plugin/runtime mechanisms, or are operator-invoked. The graph therefore exposes explicit reachability but does not delete or fail on an unreferenced skill. If Datarim later requires every skill to have a consumer, add a machine-readable `activation:` field rather than guessing from prose.

## Frontmatter defects fixed by this pass

Five shipped skills contained unquoted `description:` values with YAML-significant `: ` sequences. Lenient consumers could accept them as text while strict YAML parsers rejected them. The affected skills were `init-task-persistence`, `immutability`, `test-env-verification`, `prod-readiness-probe`, and `tech-stack`. Their descriptions are now quoted and a regression test parses every skill frontmatter block as strict YAML.

## Next schema evolution

The next useful graph expansion is not more decorative diagrams. Add typed nodes for `validator`, `artifact`, `rule/contract`, `plugin`, and `pipeline-stage`, with provenance. That will make questions such as “which validator enforces this rule?” and “what artifacts can block archive?” answerable mechanically. Do this only when those relationships have stable machine-readable sources.

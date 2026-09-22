# Datarim Framework Graph Integration — 2026-09-20

This build includes the prior Code Contracts reliability pass plus a framework-topology consistency pass.

## Added
- `dev-tools/framework-graph.py`: deterministic graph builder/checker.
- `dev-tools/framework-graph.yaml`: generated canonical inventory and typed/provenanced edges.
- `skills/visual-maps/framework-architecture.md`: generated command→agent and agent→skill map plus complete inventory.
- `tests/framework-graph-consistency.bats`: graph/file parity and strict skill-frontmatter regression checks.
- `documentation/explanation/framework-graph-and-skill-architecture.md`: architecture rationale, overlap review, and evolution rules.
- Two architecture Code Contracts protecting graph single-source-of-truth and reference integrity.

## Corrected
- Command visual inventory now derives all 28 commands from `command-graph.yaml`; the stale 24-command representation is gone.
- Command graph tests now require exact equality with `commands/*.md`, not merely “at least 24”.
- Skill inventory counts nested composite skill nodes. Current inventory is 79 skills (including `fleet` and its five nested tier skills, plus `code-contracts`).
- Five invalid strict-YAML skill frontmatter descriptions were quoted: `init-task-persistence`, `immutability`, `test-env-verification`, `prod-readiness-probe`, `tech-stack`.
- The hand-maintained duplicate command→agent / agent→skill graph was removed from `utility-and-dependencies.md`; generated topology is authoritative.
- `validate.sh` now blocks on graph drift and reports the nested-skill inventory correctly.
- `visual-maps/SKILL.md` routes topology questions to generated maps.

## Skill review conclusion
No mass merge was performed. Similar-looking skill families were found to encode distinct authorities (e.g. normative security baseline vs operational security recipes; testing vs completion evidence vs review handoff). Removing them based on naming similarity would reduce precision. The architecture document records the boundaries and recommends machine-readable activation metadata as a future evolution.

## Verification performed here
- `python3 dev-tools/framework-graph.py --check` — PASS (28 commands, 19 agents, 79 skills, 259 edges).
- `dev-tools/check-code-contracts.sh` — PASS (8 contracts).
- `validate.sh` with an isolated `CLAUDE_DIR` — ALL CHECKS PASSED.
- `python3 -m py_compile dev-tools/framework-graph.py` — PASS.
- `bash -n validate.sh` — PASS.

Bats is not installed in this execution environment, so the complete Bats suite was not executed here. Run it locally/CI before merging.

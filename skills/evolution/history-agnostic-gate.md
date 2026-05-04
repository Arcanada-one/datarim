---
name: evolution/history-agnostic-gate
description: Pre-apply gate rejecting task-ID inlining in Datarim runtime. Load before any Class A apply step in reflecting/evolution/optimize/addskill workflows.
---

# History-Agnostic Gate — Runtime Contract

The Datarim framework is **history-agnostic by contract**. Skills, agents,
commands, and templates installed under
`$HOME/.claude/{skills,agents,commands,templates}/` must not embed task-ID
provenance — otherwise rules become coupled to ephemeral identifiers
(archived/renamed/cancelled tasks), the reading agent is distracted by
references it cannot resolve, and historical IDs risk leaking into AI outputs
addressed to end users.

History belongs to: `docs/evolution-log.md`, `documentation/archive/`,
`datarim/reflection/`, git commit messages, and task description files. Not to
runtime instructions.

This gate runs **before any Class A apply step** writes to the framework
runtime. It is the executable enforcement of the rule documented in
`code/datarim/CLAUDE.md` § Critical Rules. Sibling pattern:
`skills/evolution/stack-agnostic-gate.md` (stack-agnostic policy).

## Trigger

Load and run this gate at the apply step of:

- `skills/reflecting.md` — Class A apply (post-archive evolution proposals)
- `commands/dr-archive.md` Step 0.5(e) — runtime apply of approved Class A
- `commands/dr-optimize.md` — apply of approved optimization proposals
- `commands/dr-addskill.md` — write of newly created skill/agent/command/template
- `commands/dr-do.md` — **after every phase commit** that touched files under
  `skills/`, `agents/`, `commands/`, `templates/`, or `dev-tools/` in the
  framework repo. Run as a fast pre-flight (`scripts/task-id-gate.sh <touched-paths>`);
  treat a hit as a phase-fail, not a downstream compliance-stage finding.
  Earlier detection avoids a compliance-stage round-trip and keeps task-ID
  leakage out of intermediate commits on the feature branch.

## Scope

Any text about to be written to:

- `$HOME/.claude/skills/*.md` and `$HOME/.claude/skills/*/*.md`
- `$HOME/.claude/agents/*.md`
- `$HOME/.claude/commands/*.md`
- `$HOME/.claude/templates/*.md`

…with the exceptions listed in Whitelist below.

**Out of scope** (history surfaces by definition — gate must NOT scan them):

- `scripts/` (source code with conventional in-comment provenance)
- `tests/`, `tests/security/` (regression tests reference findings by ID)
- `docs/`, `docs/evolution-log.md` (the canonical evolution surface)
- `datarim/`, `datarim/reflection/` (workflow state)
- `documentation/archive/` (long-term task archives)
- Top-level `CLAUDE.md` (project-wide rules; cite gate but are not in gate scope)

## Denylist (single regex)

<!-- gate:history-allowed -->
The match pattern is the literal regex `\b[A-Z]{2,10}-[0-9]{4}\b` —
two-to-ten upper-case letters, hyphen, exactly four digits, with word boundaries
on both sides. Examples that match: ``, ``, ``,
``. Examples that do NOT match: `AB-1` (too few digits), `FOO-12345`
(too many digits), `tune-0042` (lowercase), `1.21.0` (no letters), bare numeric
tokens like `25055434967` (no hyphenated letter prefix).
<!-- /gate:history-allowed -->

The single-regex shape is by design. Task IDs across the ecosystem share one
canonical syntax (Unified Task Numbering) — there is no per-prefix denylist to
maintain. Compare with the sibling stack-agnostic gate, which carries an
extensible keyword array because frameworks/runtimes do not share a syntax.

## Whitelist

- **`skills/evolution/history-agnostic-gate.md`** (this file) — the gate's own
 contract document MUST enumerate the regex and example IDs verbatim, so it
 cannot be subject to the rule it defines. Wrapped in a single
 `<!-- gate:history-allowed -->` block per scope.

The whitelist is intentionally minimal. New entries weaken the gate's
discriminative power. Add a file ONLY if:

1. The file is **by-design** history-aware — its core value depends on naming
 concrete historical incidents (e.g. an evolution-log skill if ever loaded).
2. Generalization would gut applicability — replacing concrete IDs with
 abstract roles makes the content useless to readers.
3. The exemption is reviewed by maintainer at PR time, not self-applied.

For one-off legitimate placeholders (template example slots, illustrative
backlog entries), prefer the per-block escape hatch over whitelisting the whole
file.

## Escape Hatch — `<!-- gate:history-allowed -->` … `<!-- /gate:history-allowed -->`

Per-block escape hatch for legitimate placeholders. Lines between an opening
and closing marker are ignored by the gate. Use only when:

- The task-ID is a genuine illustrative slot (e.g. backlog template showing
 `` as an example entry shape).
- The surrounding prose remains history-neutral (no inline reference smuggled
 in adjacent paragraphs under the marker).
- The escape block is small (rule of thumb: >3 escape blocks in one file →
 consider whether the file should be re-scoped to docs/ or tests/ instead).

Reviewers should challenge any usage that smuggles prescriptive guidance
under the marker.

### Markers must be on separate lines (pitfall)

The escape-hatch markers are **block-style only**. The gate's awk strip
matches `<!-- gate:history-allowed -->` line-by-line and uses `next` after
the opening marker matches, so the closing marker on the **same input line**
is never processed and `skip=1` persists for the rest of the file (every
subsequent line is silently dropped from the scan, masking real violations).

Correct (separate lines, the only working form):

```
<!-- gate:history-allowed -->
example task-ID slot
<!-- /gate:history-allowed -->
```

Wrong (same line — opening matches, closing is never seen, scan halts):

```
<!-- gate:history-allowed -->example here<!-- /gate:history-allowed -->
```

The sibling stack-agnostic-gate carries the identical pitfall and the lesson
applies to both: assume same-line markers are malformed and rewrite to the
block form.

## Invocation

Direct CLI (CI helper):

```
scripts/task-id-gate.sh <file-or-dir> [--whitelist <path>] [--diff-only [<base>]]
```

Agent flow (markdown checklist agents must follow when the script is not
reachable from the current working directory):

1. Read the target file's content (the proposal text about to be written).
2. Run `grep -nE -o -- '\b[A-Z]{2,10}-[0-9]{4}\b'` over the content.
3. Skip lines between `<!-- gate:history-allowed -->` markers (block-style only).
4. If the file path ends with `skills/evolution/history-agnostic-gate.md`,
 skip entirely (PASS).
5. **Decision:**
 - 0 hits → PASS. Proceed with the write.
 - 1+ hits → FAIL. **Do not write the file.** Two outcomes:
 - (a) Reword the proposal in history-neutral terms (delete pure provenance,
 migrate load-bearing rationale to `docs/evolution-log.md`, aggregate
 counter-example incidents under a topic heading). Re-run the gate.
 - (b) Wrap a legitimate illustrative slot in the per-block escape hatch
 (separate-line form only).

## `--diff-only` mode

For repos where the runtime files have legitimate baseline matches that cannot
yet be cleaned up (transitional period before the cleanup pass lands), the
`--diff-only` flag scans only added lines from `git diff <base> -- <file>`
(default base `HEAD`). Pre-existing matches in the baseline are ignored —
only fresh leakage in the current diff triggers FAIL.

Single-file target outside a git repo or untracked → exit 2 (refuse to silently
PASS). Directory scan silently skips untracked files.

Use `--diff-only` in CI on push to feature branches (catch new leakage), and
the full scan in main-branch CI (enforce the cleaned baseline).

## Exit Codes (script form)

- `0` — clean (no matches)
- `1` — matches found (FAIL — do not write)
- `2` — invocation error (path missing, bad flag, --diff-only on non-git)

## Why This Exists

Runtime rules are read by AI agents that have no access to the historical
context behind each task-ID reference. A rule that says «Per …»
forces the agent to either (a) treat the citation as opaque noise that
distracts from the actual instruction, or (b) attempt to locate in
archive — wasted tokens for a reference that the rule itself does not depend
on.

Worse, when an AI agent is asked to summarise or explain a rule to an
end-user, embedded task-IDs leak into the output. Users see «follow the
 pattern» without context. The rule should be self-contained.

The sibling stack-agnostic-gate established this enforcement pattern
(detection → escape-hatch → CI integration) for stack-specific terms after
multiple post-hoc revert episodes. The history-agnostic case is structurally
identical: a known-leak class with a clean separation between the rule
(stays in runtime) and the rationale (moves to evolution-log).

## Out of Scope

- **Historical content cleanup** — the gate is forward-looking. Pre-existing
 task-ID references in framework files are tracked as a one-pass cleanup; the
 gate surfaces them but does not auto-fix.
- **Whitespace / Unicode bypass** — accepted residual risk. Bypass requires
 intentional malice; reflection follow-up + maintainer review provide
 redundancy.
- **Source-code provenance** (`scripts/*.sh` headers) — conventional and not
 user-facing rule. Out of gate scope by directory exclusion.

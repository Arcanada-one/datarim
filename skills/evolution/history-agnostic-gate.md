---
name: evolution/history-agnostic-gate
description: Gate rejecting task-ID inlining across governed Datarim public surfaces. Load before any Class A apply step in reflecting/evolution/optimize/addskill workflows.
---

# History-Agnostic Gate — Runtime Contract

The Datarim framework is **history-agnostic by contract**. Runtime instructions,
public explanatory documentation, and root entry documents must not embed task-ID
provenance — otherwise rules become coupled to ephemeral identifiers
(archived/renamed/cancelled tasks), the reading agent is distracted by
references it cannot resolve, and historical IDs risk leaking into AI outputs
addressed to end users.

History belongs to: `documentation/how-to/evolution-log.md`, `documentation/archive/`,
`datarim/reflection/`, git commit messages, and task description files. Not to
runtime instructions.

This gate runs **before any Class A apply step** writes to the framework
runtime. It is the executable enforcement of the rule documented in
`code/datarim/CLAUDE.md` § Critical Rules. Sibling pattern:
`skills/evolution/stack-agnostic-gate.md` (stack-agnostic policy).

## Trigger

Load and run this gate at the apply step of:

- `skills/reflecting/SKILL.md` — Class A apply (post-archive evolution proposals)
- `commands/dr-archive.md` Step 0.5(e) — runtime apply of approved Class A
- `commands/dr-optimize.md` — apply of approved optimization proposals
- `commands/dr-addskill.md` — write of newly created skill/agent/command/template
- `commands/dr-plan.md` § 6.5 History-agnostic runtime-body probe — **plan-time, before approve.** When Implementation Steps name a shipped runtime body (`skills/`/`agents/`/`commands/`/`templates/`) as an edit target, the planner dry-runs this gate against the plan's cited paths + any example text the plan will ship, so a prescribed provenance leak or phantom path is caught at plan review rather than at the downstream `/dr-do`/`/dr-qa` triggers below.
- `commands/dr-do.md` — **after every phase commit** that touched files under
  `skills/`, `agents/`, `commands/`, `templates/`, or `dev-tools/` in the
  framework repo. Run as a fast pre-flight (`scripts/task-id-gate.sh <touched-paths>`);
  treat a hit as a phase-fail, not a downstream compliance-stage finding.
  Earlier detection avoids a compliance-stage round-trip and keeps task-ID
  leakage out of intermediate commits on the feature branch.

## Scope

CI invokes the one-target gate separately for these exact roots:

- `skills/`
- `agents/`
- `commands/`
- `templates/`
- `documentation/how-to/`
- `documentation/reference/`
- `documentation/explanation/`
- `documentation/tutorials/`
- root `CLAUDE.md`
- root `README.md`

Directory targets recursively scan regular text files ending in `.md`, `.sh`,
`.template`, `.yaml`, or `.yml`. Symlinks, special files, unreadable inputs,
binary inputs, traversal failures, and Git diff failures fail closed.

**Out of scope** (history surfaces by definition — gate must NOT scan them):

- `scripts/` (source code with conventional in-comment provenance)
- `tests/`, `tests/security/`, `tests/*.bats` (regression tests reference findings by ID — `.bats` test data and fixture body may contain TASK-ID literals by design)
- documentation outside the four governed public categories
- `datarim/`, `datarim/reflection/` (workflow state)
- `documentation/archive/` (long-term task archives)
- `CHANGELOG.md` (release history)

## Denylist (single regex)

<!-- gate:history-allowed -->
The semantic match shape is `[A-Z]{2,10}-[0-9]{4}` — two-to-ten upper-case
letters, hyphen, exactly four digits — bounded on both sides by non-word
characters. The implementation uses POSIX-awk character checks rather than
`\b`, whose meaning is not portable across GNU and BSD grep. Examples that
match are kept in this exempt contract. Examples that do NOT match: `AB-1`
(too few digits), `FOO-12345`
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
 cannot be subject to the rule it defines.
- **`documentation/how-to/evolution-log.md`** — the canonical public provenance
  ledger.

Both comparisons are exact canonical repository-relative equality. A different
path that merely ends with either exempt name is not trusted.

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

Per-block escape hatch for legitimate placeholders. Lines between a valid
opening and closing marker are ignored only after structural and provenance
checks. Use only when:

- The task-ID is a genuine illustrative slot (e.g. backlog template showing
 `` as an example entry shape).
- The surrounding prose remains history-neutral (no inline reference smuggled
 in adjacent paragraphs under the marker).
- The escape block is small (rule of thumb: >3 escape blocks in one file →
 consider whether the file should be re-scoped to documentation/ or tests/ instead).

Reviewers should challenge any usage that smuggles prescriptive guidance
under the marker.

The parser rejects provenance labels inside a hatch. After Markdown decoration
and case are normalized, `Source`, `Source task`, `Reference`, `Created`, and
`Parent epic` followed by a task ID on the same or next nonblank line are
findings. This is defense in depth: reviewers still decide whether every
unlabelled survivor is genuinely illustrative.

### Marker grammar is fail closed

The escape-hatch markers are **block-style only**. Each exact marker must be the
only non-whitespace content on its line. Same-line open/close, marker payload,
nested open, stray close, and an unclosed block at EOF are independent findings;
none can suppress later content.

Correct (separate lines, the only working form):

```
<!-- gate:history-allowed -->
example task-ID slot
<!-- /gate:history-allowed -->
```

Wrong (same-line markers are malformed):

```
<!-- gate:history-allowed -->example here<!-- /gate:history-allowed -->
```

Malformed syntax exits 1 even when its line contains no task ID.

## Invocation

Direct CLI (CI helper):

```
scripts/task-id-gate.sh <file-or-dir> [--whitelist <path>] [--diff-only [<base>]]
```

Agent flow:

1. Resolve and invoke the shipped script against one intended target.
2. Do not reproduce the boundary or hatch logic with an ad hoc grep.
3. **Decision:**
 - 0 hits → PASS. Proceed with the write.
 - 1+ hits → FAIL. **Do not write the file.** Two outcomes:
 - (a) Reword the proposal in history-neutral terms (delete pure provenance,
 migrate load-bearing rationale to `documentation/how-to/evolution-log.md`, aggregate
 counter-example incidents under a topic heading). Re-run the gate.
 - (b) Wrap a legitimate illustrative slot in the per-block escape hatch
 (separate-line form only).

## `--diff-only` mode

For repos where the runtime files have legitimate baseline matches that cannot
yet be cleaned up (transitional period before the cleanup pass lands), the
`--diff-only` flag scans only added lines from `git diff <base> -- <file>`
(default base `HEAD`). Pre-existing matches in the baseline are ignored —
only fresh leakage in the current diff triggers FAIL.

Single-file target outside a git repo or untracked exits 2. In directory mode,
an untracked governed text file is scanned in full so a new file cannot bypass
the gate. Invalid bases and Git errors exit 2.

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

- **Whitespace / Unicode bypass** — accepted residual risk. Bypass requires
 intentional malice; reflection follow-up + maintainer review provide
 redundancy.
- **Source-code provenance** (`scripts/*.sh` headers) — conventional and not
 user-facing rule unless the script is beneath a governed caller root.

## Anti-patterns

**Forward-reference to follow-up task ID before assignment.** When a skill
paragraph references a future task whose ID has not yet been issued (e.g.
«programmatic enforcement is queued as the next hook task»), the author
MUST NOT bake a guessed placeholder numeric into the runtime text. The
guessed ID decays into a stale reference the moment the actual follow-up
receives a different number; the drift then surfaces only at that
follow-up's `/dr-do`, after the text contract is already frozen and
mirrored downstream.

Two safer authoring forms:

1. **Defer the reference.** Add the paragraph only when the follow-up ID
   is bound — the prose lands together with the work it describes.
2. **Use an unassigned-marker.** When the paragraph must ship now, write
   <!-- gate:history-allowed -->
   `<TASK-PREFIX>-XXXX (fill in at assignment)`
   <!-- /gate:history-allowed -->
   inside the per-block escape hatch above. The marker is grep-detectable
   at the follow-up's `/dr-do` and signals "replace me" rather than
   masquerading as a real reference.

Detection: at `/dr-archive` Step 0.5 run `grep -rn "XXXX (fill in"` over
the touched skills/agents/commands/templates; any non-zero count is a
pending follow-up obligation, not a drift.

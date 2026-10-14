# Product-Discovery Pack: Boundaries and Integration Contract (ADR)

**Status:** Accepted (architecture decision; no code in this change).
**Source pin:** Datarim `4846e68c953af9c05c1a1717a1a3c61aa32a9d53`. Every line reference below is at this pin.
**Scope:** how an opt-in product-discovery plugin installs, is discovered by the canonical graph, is activated
for a task, records its strategist fields, and stays inside the existing lifecycle. Implementation belongs to
later changes; this record fixes the contracts they must meet.

## 1. Context

The product-discovery pack ships six research artifact templates (opportunity brief, source-evidence ledger,
hypothesis card, experiment protocol, decision record, product brief), a structural checker, and skill bundles
that guide framing and research. Three accepted design inputs define their content:

| Input | SHA-256 | Role here |
|---|---|---|
| Product artifact contracts r2 | `e73d0bb678857c9e932f8dd977adae49fe4c9ae5f8068a72d4010f994051fa09` | Artifact shapes, lifecycle, checker rules |
| Research-only completion and resume contract r2 | `1899dffc757eb3a9e981e6dabd370a07af3c379b44eeb23ccf34f86d4d5f02f8` | Route, stop/continue/pivot/more-evidence, handoff to `/dr-prd` |
| Evidence assurance capability mapping r2 | `453685d1317c50a9b2f9afdc0fd6e01f985ca5bfcd1d8253886f9f91cc51bcd3` | What existing evidence primitives prove and do not prove |

Five facts at the pin make "install it as an ordinary plugin" insufficient. Each was re-measured for this record.

1. **The installer drops nested bundles silently.** `_collect_inventory_for` (`scripts/dr-plugin.sh:328-340`)
   echoes only immediate regular files of `<src>/<cat>/`. Measured on a synthetic plugin with
   `skills/product-framing/{SKILL.md,frag.md}`, `skills/flat.md` and `templates/opportunity-brief.md`: the result
   was `skills: [flat.md]`, `templates: [opportunity-brief.md]`, exit 0. The bundle was absent and nothing failed.
   The apply loop (`scripts/dr-plugin.sh:556-571`) symlinks only collected entries with `ln -sfn` into
   `<runtime>/<cat>/<plugin-id>/<basename>`. `cmd_sync` (phase 1b, lines 804-828) and
   `_doctor_check_orphan_files` (lines 977-1013) inspect only one level below `<runtime>/<cat>/<id>/`.
2. **The canonical graph sees only core assets.** `framework-graph.py` `names()`/`skill_names()` (lines 18-19)
   and `load()` (lines 24-91, fragment and template scans at 47-76) walk `commands/`, `agents/`, `skills/` and
   `templates/` at the repository root. `plugins/` is never inventoried, so a reference to a plugin skill is a
   broken reference.
3. **The strategist record is closed at 18 keys and version 1.** `dev-tools/check-strategist-gate-record.sh`
   parses `key=value` lines and refuses a 19th line before it reads `schema_version` (line 200), refuses unknown
   keys (line 228), and checks `schema_version = 1` only after the loop (line 253). Measured with synthetic
   records: a valid v1 record exits 0; an 18-key record with `schema_version=2` or `3` exits 2 with
   `schema version mismatch`; a 21-key record with the three new fields exits 2 with
   `unexpected or duplicate key`, whatever its version. Today the reader fails closed, but the diagnostic for a
   newer record is misleading.
4. **Research has no stage of its own.** The acceptance-contract route grammar
   (`dev-tools/lib/live-evidence.sh:79-89`) admits only `do`, `write`, `edit`, `publish`, `qa`, `compliance`,
   `archive` and `quick`; a non-content route starts with `do`. A route containing `research` is an invalid
   contract (an independent run of `check-live-evidence.sh --stage preflight` returned exit 1 `BLOCKED`).
   Research therefore occupies the existing `do` stage.
5. **The task-description frontmatter is a closed 12-key schema** (`templates/task-template.md`,
   `skills/datarim-system/SKILL.md` § Description File Contract). A new frontmatter key cannot be the profile
   selector without reopening that schema.

## 2. Decision

One default-disabled plugin, `product-discovery`, with zero new slash commands, zero new route stages, zero new
task statuses and zero new acceptance lifecycles. The installer and the canonical graph are **extended**, not
replaced. The contracts below are normative for the implementing changes.

### 2.1 Source → installed path contract (installer extension)

| Source (in the plugin) | Installed path | Mechanism |
|---|---|---|
| `plugins/<id>/skills/<name>/SKILL.md` | `<runtime>/skills/<id>/<name>/SKILL.md` | real directory `<runtime>/skills/<id>/<name>/` created; one symlink per file |
| `plugins/<id>/skills/<name>/<fragment>.md` | `<runtime>/skills/<id>/<name>/<fragment>.md` | same directory; one symlink per file |
| `plugins/<id>/skills/<file>.md` (flat, legacy) | `<runtime>/skills/<id>/<file>.md` | unchanged |
| `plugins/<id>/templates/<basename>` | `<runtime>/templates/<id>/<basename>` | unchanged |
| `plugins/<id>/{agents,commands}/<file>` | unchanged legacy behaviour | the product-discovery plugin ships neither |

Rules:

- **Bundle shape.** A bundle is a directory directly under `skills/` whose name matches `^[a-z0-9][a-z0-9-]*$`
  and which contains a regular file `SKILL.md`. It contains regular files only; a subdirectory, a symlink (the
  bundle directory or any file in it), a non-regular file, or a missing `SKILL.md` refuses `enable` with a
  one-line typed diagnostic and no runtime or manifest change. Dotfiles are skipped, as for flat files.
  Bundles exist only under `skills/`.
- **Path safety.** The existing source checks (absolute path, no `..`, `plugin.yaml` schema 1, id validation)
  stay. No inventory entry may contain `..`, a leading `/`, or more than one `/`.
- **Overrides.** A bundle cannot be an override; an `overrides` stem that names a bundle refuses `enable`.
  Root-position overrides remain flat files only.
- **Ownership of the namespace.** `enable` refuses when `<runtime>/<cat>/<id>/` already holds any entry that is
  not a symlink into this plugin's source (today only a non-directory at that path is refused). One owner per
  id: a plugin id equal to a top-level core skill directory name is refused by `enable` and by the graph check.
- **Inventory.** `file_inventory.skills` lists every installed file: flat entries as `<file>.md`, bundle entries
  as `<name>/<file>.md` (sorted, every file, including fragments). `manifest_inventory_of` already splits these
  correctly; `cmd_sync` and doctor keys become `<id>/<name>/<file>.md`.
- **Lock, snapshot, rollback.** Unchanged and reused: the plugin lock, `snapshot_create` (copies the runtime
  tree with `cp -RP`, so nested directories are included) and `restore_from_snapshot`. A failure after the first
  symlink restores the snapshot, exactly as the existing fault-injection points do.
- **Disable.** `cmd_disable` already removes `<runtime>/<cat>/<id>/` recursively; it must not touch workspace
  artifacts (`datarim/`), research records or task history.

Functions to extend, by name: `_collect_inventory_for` (emit bundle entries), the `cmd_enable` pre-scan and
apply loop (`mkdir -p` of the bundle directory, conflict and ownership checks per nested target),
`_validate_overrides_shipped` (refuse bundle overrides), `cmd_sync` phase 1b and `_doctor_check_orphan_files`
(descend into bundle directories instead of treating them as orphan entries), and `_doctor_build_inventory`
(no shape change; covered by tests). `manifest_validate_entry` gains the inventory-entry path rule.

**Proof is installed bytes, not link counts.** Every existing plugin test at the pin asserts symlink presence,
manifest text or counts; none dereferences an installed file or compares its digest, and none has a nested
bundle fixture (developer-drafted inventory, verified by the author of this record, SHA-256
`086a4ac1f2df9caa4869b5e6c6ab049f4938453a8e9845adaa2899012c629999`). The installer change must add a suite in
which, for every entry of `file_inventory`, the SHA-256 of the bytes read **through the installed runtime path**
equals the SHA-256 of the source file, and the set of installed files equals the set of source files.

### 2.2 Canonical graph discovery (graph extension)

- `load()` gains a plugin inventory from `plugins/*/plugin.yaml` and each declared category, using the **same
  collection rule as the installer** (one rule, two callers; a test asserts the graph's plugin inventory equals
  the installer's collected inventory for each plugin source). No hand-maintained second inventory.
- Plugin nodes use the installed spelling, so existing reference extraction resolves them: `skill:<id>/<name>`
  for a bundle, `fragment:plugins/<id>/skills/<name>/<file>.md` for a fragment, `template:<id>/<basename>`.
  Every plugin node carries `provenance: plugin:<id>`; core nodes keep their implicit core provenance.
- Reachability is conditional, not evaluated at build time: every edge with a plugin endpoint carries
  `condition: plugin:<id> enabled`. The graph is a repository fact; whether a workspace has the plugin enabled
  is read from that workspace's `datarim/enabled-plugins.md` at run time.
- `validate()` errors on a plugin id that collides with a core top-level skill directory, on a node id owned by
  two sources, on a plugin-shipped command for this plugin, and on any unresolved plugin reference.
- The output `schema_version` moves from 2 to 3 because the inventory shape changes. Compatibility is judged on
  the legacy edge set: the edges whose both endpoints are core nodes must be identical before and after the
  change. Equality of the checker's summary line is not routing proof.

### 2.3 Profile gate: enabled AND selected

The product profile is **active** for a task if and only if both hold:

- **enabled:** the workspace `datarim/enabled-plugins.md` `## Active` section has an entry `- id: product-discovery`
  (the plugin is not default-enabled), and the profile entry skill is readable at
  `<runtime>/skills/product-discovery/<entry>/SKILL.md`;
- **selected:** the task description `datarim/tasks/{TASK-ID}-task-description.md` has exactly one body line
  `profile: product-discovery` under a `## Profile` heading.

Why this selector: a frontmatter key would reopen the closed 12-key schema; the init-task file is the operator's
verbatim, append-only brief and must not be edited by agents; a command flag is not persisted, so `/dr-auto`
and `/dr-next` replay could not see it. A body line persists, replays, and leaves the frontmatter schema,
`frontmatter-key-registry.yaml` and doctor schema unchanged (the selector is not a frontmatter key). The mirror
principle is met by documenting the selector next to both readers and by a test that the documented string and
the reader agree. `datarim-doctor` `write_description` returns early when a description exists, so it preserves
the line.

Readers: `/dr-prd` at its Discovery Interview step and `/dr-plan` at its strategist step. Typed outcomes:

| Outcome | Condition | Behaviour |
|---|---|---|
| `profile_not_selected` | no `## Profile` selector | default route, byte-identical to today, no notice |
| `profile_active` | enabled and selected | product-discovery guidance and artifacts apply |
| `profile_unavailable` | selected, plugin not enabled or entry skill unreadable | one-line visible notice; default route |
| `profile_unknown` | selector names another value | one-line visible notice; default route |
| `profile_ambiguous` | more than one selector line | one-line visible notice; default route |

Task text alone never activates an uninstalled pack. No new slash command is introduced; plugin-shipped
commands are not discoverable by the Claude Code slash picker, so the pack's entry points are the existing
`/dr-prd` and `/dr-plan`.

### 2.4 Strategist record version policy (v2)

- **v1 stays exactly as today:** the 18 keys, `schema_version=1`. The producer (`/dr-plan` strategist step)
  keeps writing v1, byte-identical, whenever the profile is not active.
- **v2 = v1 + three keys,** written only when the profile is active: `scope_mode`
  (`expand` | `selective_expand` | `hold` | `reduce`), `scope_delta` (ASCII text or `none`), and
  `do_nothing_cost` (ASCII text or `unknown`; never inferred as zero). Text values use the existing 500-byte cap
  and unsafe-text filters. v2 has exactly 21 keys.
- **Reader dispatch:** the reader reads up to 21 lines, then dispatches on `schema_version` before applying the
  key set. `1`: exactly the 18 v1 keys; any v2 key in a v1 record is malformed. `2`: exactly 21 keys. Missing
  version: malformed. Any other value: exit 2 with the explicit message `unsupported schema version: <value>`.
- **No silent drop:** a v2 record is either fully validated (all three new fields checked and echoed in the
  reader's result output) or refused. Exit codes keep their meanings (0 advance or normal route, 1 valid
  non-advancing, 2 malformed, 64 usage). The new fields are recorded, not routing inputs, in this slice; the
  advance/block truth table is unchanged.
- Producer and reader change in one pull request.

### 2.5 Output ownership

| Output | Owner |
|---|---|
| `plugins/product-discovery/` (manifest, bundles, six templates) and `dev-tools/check-product-artifact.sh` | plugin and installer change |
| `scripts/dr-plugin.sh` and `scripts/lib/plugin-system.sh` extension (§2.1) | plugin and installer change |
| `dev-tools/framework-graph.py` extension and regenerated graph artefacts (§2.2) | graph change, run after all profile-related command and agent edits |
| Profile readers in `commands/dr-prd.md` and `commands/dr-plan.md`; strategist producer and reader (§2.3, §2.4) | profile-gate change |
| Product-brief handoff at `/dr-prd`, resume and stop behaviour | research-to-delivery handoff change |
| This record | architecture owner; amended only by a superseding record |

One owner per output; no change edits another change's output except through a reviewed pull request.

### 2.6 No-action boundary

Research artifacts, frozen protocols, decision records, product briefs, snapshots and derived labels grant no
authority to execute, spend, contact people, publish, deploy, merge or close a parent. `budget_cap`, `grant_ref`,
`approved_scope_delta` and `delivery_authorized` are descriptive. Delivery proceeds only through an explicit
scope advance in the existing authoritative task record identified by `authorization_ref`. Fixtures are
synthetic and labelled as such.

### 2.7 Deferred: grants and budgets

A grant/budget mechanism is **not** built in this slice. The finite resource caps for any baseline, pilot and
judging run are **not** deferred: they remain mandatory in the frozen pilot protocol (attempts, tokens, quota,
time, retries and judging included), and an absent cap refuses execution.

`reverse_if` (any one reopens the deferral):

1. a planned run needs spending, outreach or an action outside a sandbox that the frozen protocol's finite caps
   cannot bound;
2. any consumer is found to treat `grant_ref`, `budget_cap`, `approved_scope_delta` or a frozen protocol as
   authorization;
3. the research-to-delivery handoff needs an authorization source other than the existing task scope-advance
   record.

### 2.8 Carried contract clarifications

- **Minimum input states.** When an accepted artifact cites a product artifact as input, the cited artifact must
  be `acceptance_state: accepted` and at least: opportunity brief `ready_for_research`; source-evidence ledger
  `recorded`; hypothesis card `test_ready`; experiment protocol `protocol_frozen`; decision record `submitted`;
  product brief `ready_for_delivery`. Otherwise `E_INPUT_NOT_READY`.
- **Superseded revisions.** A revision for which a later revision of the same id is present in the bundle may
  not be cited as input: `E_INPUT_SUPERSEDED`. The `supersedes` lineage reference is exempt. Without the later
  revision in the bundle the checker cannot know; currentness is then the handoff guard's job.
- **Namespaces.** `source_refs`, `evidence_refs` and `counterevidence_refs` accept both `artifact:` and `raw:`
  references; each resolves only in the namespace its prefix names, with no cross-namespace fallback. Input-state
  guards apply to `artifact:` references only.
- **Draft with observed claim** has the stable code `E_DRAFT_OBSERVED_CLAIM`.
- **PRD headings.** The handoff writes into the PRD template's real headings at the pin: citations of the
  product brief, the decision record and `authorization_ref` under `## Discovery Summary`; the accepted intent
  under `## Problem Statement`. Tests assert those exact headings.
- **Research stage.** Research work runs in the existing `do` stage; the profile adds no route stage
  (`dev-tools/lib/live-evidence.sh:79-89`).
- **Assurance levels.** Adopted unchanged from the mapping: a self-authored receipt is at most `declared` and,
  against a trusted comparison, `integrity_bound`. `captured` and `witnessed` remain **not measured**: no
  inspected primitive establishes them. Actor-string inequality and model-family difference are not witnessing.
  The optional `assurance` field is not adopted in this slice.

### 2.9 Status of every DTO and template

| Item | Marking |
|---|---|
| Six product artifact templates (`schema_version: product-artifact/1`) | bound to the plugin owner; proposal until merged |
| Structural checker diagnostics | bound to the plugin owner |
| Datarim5 JSON design envelopes | proposal only; not shipped |
| `research_result`, `scope_snapshot`, `delivery_authorized` | derived projections, never records |
| Strategist record v2 | bound to the profile-gate owner |
| `assurance` enum | proposal; not adopted |
| Crosswalk rows to Knowledge Contracts | candidates only; not shipped in the plugin |

**No product template, checker diagnostic or crosswalk row is a Knowledge Contract** or carries Knowledge
Contract wire authority, admission or promotion. A template or manifest that labels itself an official Knowledge
Contract (for example a `kc_contract` or `contract_authority` frontmatter key, or such a claim in its body) is
refused: unknown frontmatter keys are already invalid under the artifact contract, and the plugin suite must
include this negative fixture.

## 3. Compatibility tests (all required)

| # | Test | Proves |
|---|---|---|
| CT1 | Existing `tests/dr-plugin.bats`, `tests/dr-plugin-coverage.bats`, `tests/test-fb-rules-mirror.bats`, `tests/tdd-enforcement-toggle.bats` pass unchanged | legacy flat plugins and toggles |
| CT2 | Legacy flat fixture: installed tree listing and per-file installed-path SHA-256 identical before and after the change | flat install unchanged, by bytes |
| CT3 | Nested bundle fixture: every `file_inventory` entry read through the runtime path matches its source SHA-256; installed set equals source set | nested install, by bytes |
| CT4 | enable → disable → re-enable: bytes as CT3 after re-enable; workspace artifacts untouched by disable | idempotent lifecycle |
| CT5 | Fault injection `after_symlinks` and `after_manifest` with a bundle: runtime tree and manifest restored byte-for-byte | rollback |
| CT6 | Refusals: bundle without `SKILL.md`, subdirectory in bundle, symlinked bundle or file, `..` entry, bundle named as override, foreign entry in namespace | path safety, no partial install |
| CT7 | `cmd_sync` and doctor on a healthy bundle install: zero orphans, zero removals | sync/doctor descend correctly |
| CT8 | Graph: core-only edge set identical before and after; plugin inventory equals installer inventory; id collision and unresolved plugin reference fail `--check` | discovery without drift |
| CT9 | Profile: not selected → `/dr-prd` and `/dr-plan` route byte-identical; selected with plugin disabled → `profile_unavailable` and default route; unknown and ambiguous selectors typed | enabled AND selected |
| CT10 | Strategist: every existing v1 case in `tests/dr-plan-strategist-redundancy-gate.bats` passes; valid v2 passes and echoes the three fields; v2 keys under `schema_version=1` malformed; `schema_version=3` → `unsupported schema version: 3` | version policy, no silent drop |
| CT11 | Profile off: producer still writes v1, byte-identical | legacy records |
| CT12 | Product-artifact checker: accepts the contract's positive examples; each negative control yields exactly its code, including `E_INPUT_SUPERSEDED`, `E_DRAFT_OBSERVED_CLAIM` and the Knowledge-Contract self-label fixture | structural checker |
| CT13 | Handoff: citations under `## Discovery Summary`; stop, more-evidence and stale decision produce no delivery PRD | handoff on real headings |

## 4. Consequences and limits

The pack can ship as one opt-in plugin without a new command, stage or lifecycle, and both the installer and the
graph can prove what they install and discover. Cost: a graph schema version step, an installer extension with
new tests, and a strategist reader rewrite of its key-count logic.

This record proves only that the named contracts were checked against the named source lines at the pin. It does
not prove the implementations, runtime behaviour, installation on any host, research quality, market demand,
release readiness or any Knowledge Contract admission.

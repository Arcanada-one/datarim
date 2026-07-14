---
name: dr-archive
description: Archive completed task with comprehensive documentation and Datarim updates
---

# /dr-archive — Archive Task

> **Contract.** Archival performs irreversible workspace mutations — schema-gate validation of the thin-index files, staged-diff audit of foreign task-ID hunks, blob-swap recipe for non-interactive shells, prefix → archive-subdir routing, and the mandatory Operator Handoff section in the archive document. All of these protections are enforced in code (`pre-archive-check.sh`, `datarim-doctor.sh`, and the steps below), independent of how the command is invoked. Prefer the canonical slash form (`/dr-archive {TASK-ID}`) over manually staging archive files: the slash command threads through every guard described in this file; ad-hoc paths skip them.

Complete and archive current task.

## Path Resolution
**RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

### EXECUTION HOST

1. Source the resolver: `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"`.
2. Call `eh_decision <workspace-root> <execution-hosts-map-path>` (default map: `~/.claude/local/config/execution-hosts.yml`).
3. On **off-host** (exit code 10): emit a delegation directive (`dev-tools/datarim-dispatch.sh --workspace <root> --task <TASK-ID>`) and STOP.
4. On **unconfigured** (exit code 0, binding absent): proceed unchanged (fail-open).
5. On **on-host** (exit code 0, binding present): proceed normally.

Note: the machine-local PreToolUse guard remains the hard floor; this Step-0 check is the cooperative soft layer sharing the same resolver library.


## Steps


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
0. **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Resolve which task is being archived (from argument or disambiguation). Use the resolved task ID for all subsequent steps.

0.05. **READ INIT-TASK** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): Open `datarim/tasks/{TASK-ID}-init-task.md` if present. Read the full `## Operator brief (verbatim)` section AND every `## Append-log` entry. The archive document MUST render every brief bullet inside `## Как решили` (one bullet per brief item, original order; expectations folded as `(уточнение брифа)` markers — see Step 2 below). Missing init-task is non-blocking on archive — note its absence under `### Operator Handoff` and continue. <!-- allow-non-ascii: literal-russian-archive-section-names-from-template-contract -->

0.1. **PRE-ARCHIVE CLEAN-GIT CHECK** (MANDATORY):

   **Contract:** this gate runs `git status --porcelain` per every git repository touched by the task. On a dirty tree the operator picks one of three branches: **Commit now** (land the changes), **Accept pending state** (record in the archive doc's "Known Outstanding State" section), or **Abort** (return to /dr-do). Do not archive over a dirty working tree silently — STOP if no branch is chosen.

   **0.1.1 Repo classification.** Every git repository touched by this task is one of:
   - **Workspace repo** (shared, e.g. a workflow-state directory shared by multiple parallel agent sessions): foreign-task-ID hunks are NOT a blocker; only this task's own forgotten hunks (or unattributed hunks) block.
   - **Conditional-shared repo:** a repo containing a `.datarim-shared` marker file at its root. Treated as workspace-shared automatically when `pre-archive-check.sh` is invoked with `--task-id` (no explicit `--shared` flag needed). Used by framework repos that are touched by multiple parallel agent sessions but were historically classified as project repos.
   - **Project repo** (single-agent, e.g. a project's source tree): foreign-task-ID hunks are impossible by construction; treat any uncommitted change as a STOP.

   | Repo type | Marker / flag | Classification |
   |-----------|---------------|----------------|
   | Workspace | invoked with `--shared <path>` | shared |
   | Conditional-shared | `.datarim-shared` marker at repo root + `--task-id` | shared (auto-detect) |
   | Project | neither | single-agent (legacy) |

   Default the framework's own state directory and any cross-task workflow store to *workspace*. Default product source trees to *project*. Mark a repo as *conditional-shared* by committing `.datarim-shared` to its root with an explanatory comment. When in doubt, ask the user.

   **0.1.2 Workspace repo check** (per repo classified as shared OR conditional-shared):
   Run either invocation form:
   - Explicit shared: `scripts/pre-archive-check.sh --task-id <CURRENT-TASK-ID> --shared <repo-path>`.
   - Conditional-shared (auto-detect): `scripts/pre-archive-check.sh --task-id <CURRENT-TASK-ID> <repo-path>` — the script auto-routes to shared mode when `<repo-path>/.datarim-shared` exists. The script classifies each modified file's hunks by task ID:
   - `own` — only the current task's ID appears → MUST be committed before archive.
   - `foreign` — only other task IDs (parallel sessions) → leave untouched, NOT a blocker.
   - `mixed` — current + other IDs in the same diff → stage selectively (own only).
   - `unattributed` — no task ID present → require explicit user disposition (default-deny). **Expected for framework self-edits:** a task obeying the no-task-ids-in-shipped-surface rule ships ZERO task IDs in its own diff lines, so its OWN modified skills/agents/commands classify here. Confirm own-work by auditing the diff-LINES against the task scope (`git diff HEAD -- <file>`), not the file body; this is the active-edit sibling of the `mine-by-elimination` branch below, which only fires when the file body already carries foreign historical IDs.
   - `whitelisted` — basename is a known version-bump file (`VERSION`, `CHANGELOG.md`, `package.json`, `Cargo.toml`, `pyproject.toml`, `.gitignore`) AND `--task-id` is set → bypass default-deny (operator-supplied disposition is the attribution). Pass `--no-whitelist` to restore strict behaviour. **Project-specific extension:** set `DATARIM_PRE_ARCHIVE_WHITELIST=<basename>[:<basename>...]` (colon-separated, PATH-style) to extend the whitelist with project-specific version-bump basenames (e.g., `config.php` for a public-surface site) without modifying the framework. Path components are rejected (basename match only). `--no-whitelist` overrides both the hardcoded list and the env-var.
   - `foreign-untracked` — an untracked (`??`) working-tree file carrying ZERO task IDs (neither the current `--task-id` nor any other) AND `--allow-foreign-untracked` is set → bypass default-deny for that file (operator opt-in for shared multi-agent workspaces where parallel sessions leave scratch artefacts). Requires `--task-id`. Scoped to untracked files only — a tracked-but-modified file with no task ID still classifies `unattributed`. Off by default; without the flag such a file blocks as `unattributed` (default-deny preserved).
   - `mine-by-elimination` — file body carries foreign historical task IDs but the actual diff lines (additions/removals) added by this session contain ZERO task IDs AND `--task-id` is set → attribute to the current task (operator-supplied disposition; nothing else to attribute it to). Closes the false-`foreign` misclassification of doc edits like CLAUDE.md/README.md/architectural docs where the committed body references many historical tasks but the current edit (e.g., a version bump) introduces none. Untracked files (no diff at all) skip this branch and fall through to `foreign` per safety guard.

   Exit 0 means archive may proceed. Exit 1 means apply recipe 0.1.3 below; STOP if the user declines.

   **0.1.3 Apply recipe — patch staging.** Two equivalent paths:

   <!-- gate:example-only -->
   *Preferred (interactive shell with TTY):*
   ```
   git -C <repo> add -p <workflow-file>
   ```
   Accept only hunks containing the current task ID. Reject foreign hunks.

   *Fallback (non-interactive shell, e.g. AI agent without TTY):* blob-swap recipe.
   ```
   git -C <repo> show HEAD:<file> > /tmp/<file>-mine
   $EDITOR /tmp/<file>-mine                       # apply only your hunk on top of HEAD
   BLOB=$(git -C <repo> hash-object -w /tmp/<file>-mine)
   git -C <repo> update-index --cacheinfo 100644,$BLOB,<file>
   git -C <repo> diff --staged <file>             # verify only your edit staged
   ```

   *Also use blob-swap when:* the in-tree edit tool (mtime-checking `Edit`)
   refuses the change because a parallel session wrote to the same shared
   workflow file between your `Read` and `Edit`. Re-Read+retry is itself
   race-prone in shared workspaces; blob-swap operates on the HEAD blob (not
   the working tree) so the mtime check is bypassed entirely. Apply only when
   the desired change is mechanical (e.g. removing your own task-ID one-liner
   from an index file) so the target blob can be constructed deterministically
   from HEAD.

   *Pre-commit retry-tolerant re-verify* (mandatory before `git commit` in either path):
   ```
   git -C <repo> diff --staged --numstat          # verify file-set + line counts
   git -C <repo> log -1 --format=%H               # capture HEAD SHA
   ```
   If file-set / line counts differ from expected delta, or HEAD SHA shifted (parallel session committed in between), rebuild the blob from the new HEAD and re-stage. Do not commit partial state.
   <!-- /gate:example-only -->

   **0.1.4 Cross-task leakage staged-diff audit:**
   After `git add` and before `git commit`, run `git diff --staged --stat` and verify the file-list matches the commit-message scope. Reject the commit if files unrelated to the message scope appear in the staged set; restage selectively. Past incidents have shown unrelated files leak into a commit when the staged diff is not inspected before commit.

   **0.1.5 Project repo check** (per repo classified as single-agent — i.e., no `.datarim-shared` marker):
   Run `scripts/pre-archive-check.sh <project-repo-path>` (legacy mode). Exit 1 → STOP and present the 3-way prompt (Commit now / Accept pending / Abort). Applied ≠ committed ≠ canonical.

0.12. **PRE-ARCHIVE UNPUSHED-COMMITS GATE** (MANDATORY for every git repository touched by the task):

   After confirming the working tree is clean (Step 0.1), verify that all local commits are present
   on the remote. A task whose only copy is a local commit can be silently lost if the clone is
   overwritten or the branch is force-pushed — the archive then records a false "done".

   **0.12.1 Detection per repo.**
   For each git repository classified in Step 0.1.1, run:

   ```bash
   token=$("${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-unpushed-commits.sh" \
       --repo <repo-path> \
       --task-description "<path-to-TASK-ID-task-description.md>")
   ```

   The helper resolves the comparison base in order: configured `@{u}` upstream →
   `origin/<default-branch>` via `git symbolic-ref refs/remotes/origin/HEAD` → last-resort
   `origin/main`. On unresolvable base (detached HEAD, no `origin` remote, shallow clone) the
   helper emits `clean` with an advisory note and does NOT block — fail-open, never false-STOP.

   Token semantics:
   - `stop` — unpushed commits exist AND task `type:` ∈ {bugfix, feature, refactor}. **STOP the archive** and present the 3-way prompt below.
   - `advisory` — unpushed commits exist AND task type is NOT in the trigger set (docs, research, content, chore, etc.). Log the advisory and continue; do not block.
   - `clean` — no unpushed commits (or base unresolvable). Archive proceeds.

   **0.12.2 Three-way prompt (on STOP).**
   When any touched repo yields `stop`, halt archiving and present the operator with exactly these
   three branches. Silent continuation is forbidden — the archive MUST NOT proceed until one
   branch is chosen and its completion condition is satisfied:

   **(a) Push** — push the local commits to the remote branch. Feature-branch `git push` is a
   permitted reversible operation. After push, re-run the helper; `clean` confirms the gate is
   satisfied and the archive may proceed. Under `/dr-auto` autonomous mode, a feature-branch push
   MAY be performed without operator escalation; a force-push to `main`/`master` remains
   hard-gated per `autonomous-agents.md`.

   **(b) Verify cherry-picked or merged elsewhere** — attest that the commits have already landed
   on the remote default branch under a different SHA (squash-merge, cherry-pick, or equivalent).
   Record in the archive document the landing ref/SHA and the verification command used (for
   example `git cherry -v origin/main <sha>` or `git diff <sha> origin/main -- <files>`; see
   the squash-collision caveat in the framework’s `CLAUDE.md` for the full procedure). Archive
   proceeds once the attestation is recorded.

   **(c) Accept loss — record in § Known Outstanding State** — explicitly accept that the local
   commits will not be pushed. This branch MUST be recorded in the archive document’s
   **§ Known Outstanding State** section as a paragraph that lists: each unpushed commit SHA,
   the repository path, the commit count, and the operator’s stated reason for accepting the
   loss. The archive MUST NOT proceed until this paragraph is written. No silent "accept loss"
   is permitted.


0.15. **DRIFT SITE-UPDATE GATE** (MANDATORY when the task's commits touched a path under a registered product's `repo_local` in `documentation/ecosystem-sync/registry.yml`):

   When an archived task changed a registered product's repository, the deployed
   site may now lag the repo. This sub-step turns that drift into a tracked
   backlog task — **repo-first**: the repo change is already landing, so the
   spawned task tracks the *site catch-up*, never an autonomous site edit.

   **0.15.1 Applicability.** Skip silently if `dev-tools/check-repo-site-sync.sh`
   is absent (a Datarim consumer without the ecosystem-sync system). Otherwise,
   for each registered product whose `repo_local` path was touched by this
   task's commits:

   ```bash
   . "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/backlog-sink.sh"
   "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-repo-site-sync.sh" \
       --check --product <product-id> --root <kb-root>
   ```

   **0.15.2 On drift (detector exit 1).** Resolve the backlog sink, then append
   one deduped site-update task using the shared helper (same dedup/append logic
   the level-3 sweep uses — DRY):

   ```bash
   if backlog="$(resolve_backlog_sink --root <kb-root>)"; then
       append_site_update_task "$backlog" <product-id> <severity> "<one-line detail>"
   else
       echo "WARN: no file backlog sink (non-file backend or consumer machine); skipping append" >&2
   fi
   ```

   `append_site_update_task` is idempotent (anchored on `drift-site-update-<product>`),
   atomic (temp-then-rename), and injection-gated. Detector exit 0 (clean) or a
   SKIP finding (source unavailable) ⇒ no-op. Quote the detector command and the
   appended backlog anchor (if any) in the archive doc § Verification.

0.2. **VERSION CONSISTENCY CHECK** (framework repo only, MANDATORY when `VERSION` changed):

   When the framework repo's `VERSION` file changed in HEAD->working-tree, all consumer files (CLAUDE.md, README.md, documentation/) must reference the new version. Catches the recurring class «VERSION bumped but README/CLAUDE.md left stale».

   Run: `bash scripts/version-consistency-check.sh <framework-repo-path>`

   Exit codes:
   - **0** — `VERSION` unchanged, OR all consumers aligned. Proceed.
   - **1** — `VERSION` bumped + at least one consumer cites old version. STOP and either update the lagging files or re-run with `--allow-version-lag` if the lag is intentional (rare; most cases are unintentional drift).
   - **2** — usage error (path not a git repo). Investigate.

   Scope: only `CLAUDE.md` and `README.md` (current-state surfaces). `documentation/` is excluded by design — `evolution-log.md` / `release-notes.md` / `changelog.md` are append-only historical ledgers that reference past versions on purpose. This step is skipped automatically when `VERSION` is unchanged — most archives don't bump, so the check is a fast no-op outside framework releases.

0.2.5. **PRE-ARCHIVE RUNTIME PROBE** (MANDATORY when the task-description frontmatter carries `requires_runtime_probe: true`):

   Arm condition: read the `requires_runtime_probe:` field from
   `datarim/tasks/{TASK-ID}-task-description.md` frontmatter. Absent or `false`
   ⇒ SKIP this step silently. This gate is opt-in per task — it is NOT the
   default for every archive; a task declares it when its Definition of Done
   asserts «the change is live and running in production», not merely «the
   commit exists locally».

   **Why:** an archive doc that claims «PROD-deployed» while the change lives
   only in a local working tree (or on an un-pushed branch, or on origin but
   not yet on the running host) records a false «done». Three SHAs MUST agree
   for a «PROD-deployed» claim to be true: the local `HEAD`, `origin`'s
   default-branch tip, and the image/commit the production container is
   actually running. A green unit suite proves none of these — this probe
   closes the class «class exists ≠ wired into the production path».

   **0.2.5.1 Local == origin.** Confirm the archived commit is on the remote:

   <!-- gate:example-only -->
   ```bash
   LOCAL_HEAD=$(git -C <repo> rev-parse HEAD)
   ORIGIN_HEAD=$(git -C <repo> ls-remote origin <default-branch> | cut -f1)
   test "$LOCAL_HEAD" = "$ORIGIN_HEAD" \
       || echo "STOP — local ahead of origin; push before archiving"
   ```
   <!-- /gate:example-only -->

   A local commit ahead of `origin` ⇒ STOP: the work is one overwrite away from
   loss and is not yet a canonical artefact (this overlaps Step 0.12; the probe
   re-asserts it as the first link of the SHA chain).

   **0.2.5.2 origin == PROD running image (read-only).** Confirm the production
   host is running the code the archived commit describes:

   <!-- gate:example-only -->
   ```bash
   PROD_IMAGE=$(ssh <deploy-user>@<host> \
       'docker inspect <container> --format "{{.Config.Image}}"')
   # assert PROD_IMAGE resolves to an <ORIGIN_HEAD>-derived tag / digest
   ```
   <!-- /gate:example-only -->

   Match the production image tag/digest (or the running unit's reported
   version) against an `$ORIGIN_HEAD`-derived value. Any deployment shape works
   — the probe is stack-agnostic: `docker inspect`, `systemctl status <unit>`
   version output, a `/version` health field, or a build-SHA label. This step
   is **read-only research** (a sensor, never an actuator): it performs NO
   restart, NO deploy, NO mutation of the host. When it finds drift it predicts
   the impact and reports it; any remediation is an explicit operator step.

   **0.2.5.3 Verdict → action.**
   - `PASS` (local == origin == PROD) → the SHA chain is intact; archive MAY
     proceed. Quote the three SHAs (or SHA-derived tags) in the archive doc
     § Verification so a reviewer can replay the chain.
   - `FAIL` (any link mismatched — local ahead, origin ahead of PROD, PROD
     running a stale image) → archive **BLOCKED**. «DoD met» / «PROD-deployed»
     framing is forbidden while the chain is broken; push / deploy / return the
     task to `/dr-do`, or record the gap under § Known Outstanding State /
     Operator Handoff with the remediation owner + ETA if the operator chose
     «Accept pending state» at Step 0.1.
   - `BLOCKED` (production unreachable — SSH timeout, host down — so the
     origin==PROD link cannot be read) → archive **BLOCKED** until the operator
     explicitly confirms out-of-band verification. Never auto-archive on an
     unverifiable prod; silence is not a PASS.

   **prod is hard-gated:** every action in this step is read-only; prod
   mutation is an explicit operator step, never performed by the framework.
   Overlap note: for deploy-class tasks Step 0.4 (Prod-Merge Verification Gate)
   asserts the same live-on-prod contract from the deploy-surface classifier;
   this probe is the frontmatter-opt-in twin for runtime tasks that do not trip
   the deploy-class classifier but still assert a production-deployed DoD.

0.3. **NETWORK EXPOSURE VALIDATION GATE** (MANDATORY when the task touched any networking surface):

   Touched surfaces include: docker-compose `ports`/`expose`, `redis.conf`,
   `postgresql.conf`, systemd `.socket`, firewall/UFW rules, runtime bind
   arguments. If none of these were touched in the task's commits across all
   repos, skip this step.

   **0.3.1 Verifier replay.** Run the verifier against the final state of every
   touched config:
   ```bash
   "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-check.sh" \
       --compose <final-compose>... \
       --redis-conf <final-redis>... \
       --postgres-conf <final-postgres>... \
       --systemd-socket <final-socket>...
   ```
   Exit code `1` ⇒ STOP archive. Drive the verifier to exit 0 (fix bind, add
   justified Tier 3 with `x-exposure-justification` + `x-exposure-expires`
   ≤ 90 d, or open a follow-up task and return to `/dr-do`). Quote the verifier
   command and exit code in the archive doc § Verification.

   **0.3.2 Tiered-gate verdict in archive doc.** Capture the gate decision so
   reviewers can replay it later:
   ```bash
   decision=$("${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh" \
       --task-description datarim/tasks/{TASK-ID}-task-description.md \
       --network-diff --quiet)
   ```
   Record `decision` (one of `hard_block` / `advisory_warn` / `skip`) in the
   archive doc.

   **0.3.3 External proof for Tier 3 binds.** For every Tier 3 listener that
   ends up in production, the archive doc MUST include ONE of:
   -   external port-scan output (e.g. `nmap` run from outside the host)
       confirming the listener is reachable as designed and that no
       unintended ports are exposed on the same host;
   -   a reference to a separate INFRA-* / SEC-* audit task that owns the
       external verification and is itself archived;
   -   an explicit waiver paragraph stating who accepted the residual risk,
       its expiry date (≤ 90 days), and the follow-up task ID that will
       perform the post-hoc audit.

   **0.3.4 Failed gate ⇒ explicit operator handoff.** If the gate verdict was
   `hard_block` and the verifier still returns 1 at archive time (e.g. the
   operator chose «Accept pending state» at Step 0.1), the archive doc § Known
   Outstanding State / Operator Handoff MUST list each unjustified bind, the
   blast-radius, and the remediation owner + ETA. «DoD met» framing is
   forbidden when the network gate is red.


0.35. **DEAD-IP CONSUMER SWEEP GATE** (MANDATORY when the task is db-relocation-class):

   Arm condition: run the DB-relocation classifier. On exit 1 (not this class),
   skip this step silently.

   ```bash
   "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-db-relocation-class.sh" \
       --task-description datarim/tasks/{TASK-ID}-task-description.md
   ```

   On exit 0 (db-relocation-class):

   **0.35.1 Required input check.** Read the `decommissioned_ip:` field from the
   task-description frontmatter. If the field is absent or blank on a
   relocation-class task, the gate fails closed — archive BLOCKED.

   **0.35.2 Fleet sweep.** Run the verifier for each decommissioned IP:

   ```bash
   "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dead-ip-consumer-sweep.sh" \
       --dead-ip <each decommissioned_ip> \
       --workspace-root "${WORKSPACE_ROOT:-.}" \
       --audit datarim/tasks/{TASK-ID}-audit.md
   ```

   Exit code 1 ⇒ STOP archive. Quote the verifier command and exit code in
   the archive doc § Verification. Resolve all live consumers (update config,
   open a follow-up task) before re-running.

   **0.35.3 Audit document requirement.** The file
   `datarim/tasks/{TASK-ID}-audit.md` MUST exist, name the dead IP(s), and
   assert zero live consumers. Absent or non-asserting audit ⇒ BLOCK.

   **0.35.4 Failed gate ⇒ explicit operator handoff.** If the sweep is red at
   archive time (operator chose to accept pending state at Step 0.1), the
   archive doc § Known Outstanding State / Operator Handoff MUST list each
   live consumer, the file path and line, and the remediation owner + ETA.
   «DoD met» framing is forbidden while the sweep gate is red.

   **/dr-auto note:** this gate is read-only (no network, no side-effects) and
   runs without operator prompt. Only a genuine BLOCK surfaces to the operator.

0.4. **Prod-Merge Verification Gate** (MANDATORY when the task is deploy-class):
   - **Condition:** the task is deploy-class —
     `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deploy-class.sh" --task-description datarim/tasks/{TASK-ID}-task-description.md`
     exits 0 (touches a deploy surface: systemd units, sudoers, CI cutover,
     `.env-deploy`). On exit 1 → SKIP this step silently.
   - **Block:** archive MUST NOT proceed until the production merge is **both
     done AND verified**. A green test-runner pipeline and a passing `/dr-qa`
     Gate 4g (pre-merge readiness) are necessary but NOT sufficient — this step
     confirms the change is actually live and healthy on prod after merge.
   - **Verification (read-only):** confirm the merged artifact is live on prod —
     e.g. the running systemd unit reports the expected version, the
     local==origin==PROD image/SHA chain matches (see
     `feedback_archive_prod_deployed_runtime_probe`), and a post-deploy
     health/log probe shows the new code actually serving (not merely a green
     `/health` — re-load `$HOME/.claude/skills/prod-readiness-probe/SKILL.md`
     for the verdict vocabulary and the read-only allow-list).
   - **Verdict → action:**
     - `PASS` (prod-merge live + verified) → archive MAY proceed.
     - `FAIL` (deploy failed / drift / unhealthy) → archive **BLOCKED**; return
       the task to `/dr-do` (or surface the operator remediation). «DoD met»
       framing is forbidden while prod is unverified.
     - `BLOCKED` (prod unreachable, cannot verify) → archive **BLOCKED** until
       the operator explicitly confirms out-of-band verification. Never
       auto-archive on an unverifiable prod.
   - **prod is hard-gated:** this step researches read-only and predicts impact;
     it performs NO prod mutation. Any required prod action is an explicit
     operator step.
   - **Rationale:** a task cannot be archived/closed while its production
     rollout is incomplete or unverified. Archive closes the audit trail —
     closing it on an unverified prod records a false «done».

0.43. **Test-Environment Verification Gate** (MANDATORY when the task ships runtime behaviour AND the project space has a test environment):
   - **Condition:** the task ships code/config/migration behaviour (not docs-only /
     framework-only) AND a test environment is registered or discoverable per
     `$HOME/.claude/skills/test-env-verification/SKILL.md` § When this skill is active
     (resolution: `spaces/<space>/space.yml` → `test_environments[]` → CI `deploy:test`
     heuristic → else `NO-TEST-ENV`).
   - **Contract:** the change MUST have been verified on the test environment —
     **backend AND frontend** — before archive. Archive is a HARD BLOCK without a
     `PASS` / `PASS_WITH_NOTES` / `SKIP` / `NO-TEST-ENV` record for this gate (from
     `/dr-qa` Layer 4h or re-asserted here). `NO-TEST-ENV` and `SKIP` are recorded
     verbatim in the archive doc § Operator Handoff; they are not a verification pass.
   - **Re-assert, do not re-deploy blindly:** read the `/dr-qa` Layer 4h record. If
     present and `PASS`/`PASS_WITH_NOTES`, confirm the test-env deploy SHA still
     matches the archived commits and proceed. If absent (task reached archive without
     the gate), run the autonomous procedure now per the skill: ship to test via
     `deploy:test`, exercise backend + frontend, record the result.
   - **Order:** this gate runs alongside Step 0.4 (prod-merge readiness) — both must
     be satisfied before reflection (Step 0.5) and the final archive write. A
     production deploy MUST NOT precede a green test-env verification.
   - **Autonomous (`DATARIM_AUTO_MODE=1`):** the gate runs without asking; "test on
     the test env first" is pre-resolved to yes. Only a billable/destructive external
     action on test with no safe-mode equivalent escalates to the operator.

0.45. **EXPECTATIONS RE-VALIDATION + ANTI-DEFERRAL GATE** (MANDATORY):
   - This gate runs BEFORE Step 0.5 (reflection) on purpose: reflection's
     follow-up-suggestion heuristic would otherwise let a self-inflicted loose
     end be laundered into a backlog item before any gate inspected it. The
     gate inspects the closed state first.
   - **(a) Re-validate expectations.** Re-run the routing validator:
     ```bash
     "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --verify {TASK-ID}
     ```
     Exit 1 + `BLOCKED` ⇒ **STOP** the archive. A `partial`/`missed` wish lacks
     a valid override (operator-authored, or agent-authored with a verifiable
     follow-up/`blocked_by` artefact). Route back to
     `/dr-do {TASK-ID} --focus-items <...>` and finish the work in this cycle.
   - **(b) Anti-deferral prose scan.** Scan the QA and compliance reports for
     self-deferral language about touched files:
     ```bash
     "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
         --file datarim/qa/qa-report-{TASK-ID}.md --root <repo-root>
     "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
         --file datarim/reports/compliance-report-{TASK-ID}.md --root <repo-root>
     ```
     (Skip a report path that does not exist.) Exit 1 from either ⇒ **STOP**.
     Print the findings and: "Self-inflicted gap detected. Finish the work in
     this branch/cycle. Do NOT absorb it via a self-filed backlog item." Route
     back to `/dr-do {TASK-ID}`.
   - **Dual-repo tasks:** when the touched code lives in a repository nested
     under the workspace root (e.g. a framework task whose reports sit in the
     outer workspace repo while the code sits in a nested repo), add
     `--extra-repo <nested-repo-path>` to each scan so the touched-set covers
     the nested repo's `merge-base..HEAD`. Without it the scanner sees an empty
     touched-set from the outer root and fail-opens (advisory), making the gate
     a no-op for that class. `--extra-repo` is repeatable and additive; an
     unreadable path warns and is skipped (fail-open preserved).
   - A legitimate deferral (time-dependent or hard external blocker) clears the
     gate ONLY by citing a follow-up ID / `blocked_by` reference that exists in
     `backlog.md` / `tasks.md`. Both scanners are fail-open on their own
     git-probe failure (warn, do not block) — an infrastructure hiccup never
     hard-blocks an otherwise-clean archive. Archive is idempotent; a fixed gap
     re-enters cleanly on the next `/dr-archive` run.

0.48. **STALE-RUNTIME REMINDER** (advisory, non-blocking):
   - Invoke the shared detector (single source of truth for this advisory):

     ```bash
     bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-stale-runtime.sh" --repo <framework-repo> --range <task-merge-base>..HEAD
     ```

     Adapt the range to the task's actual merge-base if `HEAD~1..HEAD` (the script
     default) does not cover the full task diff. When the range touched a shipped
     script (`scripts/lib/*.sh`) or skill (`skills/*/SKILL.md`), the script prints the
     generic, infra-agnostic «update your Datarim install(s) per your topology»
     advisory; otherwise it is silent. Surface the script's output verbatim before
     proceeding to reflection.
   - This step does NOT block or gate any subsequent step. The script is fail-open
     (a git probe failure exits 3 without emitting the advisory) and the reminder is
     a human prompt only.

0.5. **REFLECT** (MANDATORY — runs at least once per task, via a conditional freshness gate):
   - **Freshness gate (decides whether to re-run reflection):** invoke
     `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reflection-freshness.sh --task {TASK-ID} --root "$DATARIM_ROOT"`.
     - **exit 0** (reflection present AND `reflection_basis` matches the current compliance report) → reflection is current; REUSE the existing `datarim/reflection/reflection-{task_id}.md`, SKIP the workflow below, and continue to Step 1. Reflection was already written by `/dr-compliance`.
     - **exit 1** (reflection file absent, OR `reflection_basis` field absent, OR compliance report absent, OR basis stale vs the current report) → run the reflect workflow below to (re)generate it. This is the path that preserves the mandatory-reflection guarantee: a task archived without a prior `/dr-compliance` has no reflection file, so the gate forces generation here.
     - The two "absent" cases (no file vs no field) are distinct exit-1 branches inside the helper — they MUST both force-generate; do NOT special-case one as "skip".
   - When the gate says regenerate, load `$HOME/.claude/skills/reflecting/SKILL.md`.
   - Execute the reflect workflow per that skill:
     a. Create `datarim/reflection/reflection-[task_id].md`.
     b. Generate evolution proposals (categories: skill-update, agent-update, claude-md-update, new-template, new-skill).
     c. Classify Class A / Class B per `skills/evolution/SKILL.md`.
     d. Present Class A for approval; hold Class B (require PRD update before apply).
<!-- gate:history-allowed -->
     e. Apply approved Class A to runtime (stack-agnostic gate MUST PASS per `$HOME/.claude/skills/evolution/stack-agnostic-gate.md`; gate FAIL → reject the proposal and ask user to either reword stack-neutral or relocate to project's `CLAUDE.md`); log applied changes in `datarim/history/evolution-log.md`. **Recommended invocation for shared-history files** (`documentation/how-to/evolution-log.md`, README, changelog and any file that already carries pre-existing baseline matches): `scripts/stack-agnostic-gate.sh --diff-only <path>` — scans only lines added by the current task (`git diff HEAD -- <path>`), ignoring legacy baseline content. Default full-file mode remains correct for newly-touched skills/agents/commands/templates. **Doc-reference advisory (non-blocking)**: when the task touched any markdown under `code/datarim/{CLAUDE.md,skills,agents,commands,templates,docs}/`, run `scripts/check-doc-refs.sh --root code/datarim/` to detect broken markdown links and bare-path mentions against the `.docrefignore` baseline (orphans → exit 1; clean → exit 0). Advisory-only at this step. **Template-path convention advisory (non-blocking)**: when the task touched any markdown under `code/datarim/{commands,skills,agents}/`, run `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-template-path-convention.sh --root code/datarim/` to detect bare relative `templates/<name>.<ext>` refs that resolve cwd-relative and break LLM-copied invocations (e.g. `coworker write --context`). Accepted prefixes: `$HOME/.claude/templates/`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/`, `datarim/templates/` (project-local overlay). Hits → emit warning with file:line list; advisory-only (do NOT block archive). Source: TUNE-0267 root case. **Dev-tools-path convention advisory (non-blocking)**: sister detector `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-dev-tools-path-convention.sh --root code/datarim/` catches bare relative `dev-tools/<script>.{sh,py}` invocations that break in any workspace whose cwd is not the framework repo. Accepted prefixes: `$HOME/.claude/dev-tools/`, `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/`, `$DATARIM_RUNTIME/dev-tools/`, `code/datarim/dev-tools/`. Source: TUNE-0313 root case (consumer agent in a sibling workspace could not find `dev-tools/check-expectations-checklist.sh` because shipped /dr-qa.md used the bare-relative form). **English-only body gate (MANDATORY, fail-hard)**: when the task touched any markdown under `code/datarim/{commands,skills,agents}/` or `code/datarim/plugins/*/`, run `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-body-english.sh --root code/datarim --scope commands,skills,agents,plugins` to detect Cyrillic body prose in the shipped instruction surface. Hits → block archive with non-zero exit; the operator must rewrite the offending lines to English or wrap them in an explicit allowlist marker (`<!-- allow-non-ascii: <reason >=10 chars> -->` per line, or block-scope `<!-- allow-non-ascii-block: <reason> --> ... <!-- /allow-non-ascii-block -->`) before re-running `/dr-archive`. Allowlist markers are reserved for cases where the skill's meaning literally requires the non-ASCII string — see CLAUDE.md "English-Only Shipped Instruction Surface".
<!-- /gate:history-allowed -->
     f. Run health-metrics check; suggest `/dr-optimize` if thresholds exceeded (no auto-run).
     g. Note follow-up tasks for Step 4 consumption.
   - Step CANNOT be skipped. No `--no-reflect` flag exists.
   - On failure (skill load error / user rejects Class A): STOP archive; do NOT proceed to Step 1. Archive is idempotent — re-running re-enters Step 0.5.
   - Historical: prior to Datarim v1.10.0, this ran as a separate `/dr-reflect` command; consolidated here because an "optional mandatory gate" is the defect.

0.95. **STAGE-SNAPSHOT MOVE-TO-ARCHIVE** (MANDATORY when `datarim/snapshots/{TASK-ID}.snapshot.md` exists):
   - Resolve archive subdir via `prefix_to_area()` from `scripts/datarim-doctor.sh` (same helper used by Step 1 below).
   - `mkdir -p documentation/archive/<subdir>/snapshots/` if absent.
   - `mv datarim/snapshots/{TASK-ID}.snapshot.md documentation/archive/<subdir>/snapshots/{TASK-ID}-final-stage.md` (move-not-delete — final snapshot is a compact task card, useful for grep-search through the archive).
   - If snapshot absent → skip without warning (V-AC-9 fallback branch).
   - Contract: `skills/stage-snapshot-writer/SKILL.md` § Outputs; producer side `skills/cta-format/SKILL.md` § Snapshot Emission.

1. **DETERMINE ARCHIVE AREA**:
   - Extract prefix from task ID (everything before the first `-`)
   - Map prefix to area subdirectory using `$HOME/.claude/skills/datarim-system/SKILL.md` § Archive Area Mapping
   - If prefix not in mapping → use `general/`
   - Create `documentation/archive/{area}/` directory if it doesn't exist
   - **Collision-detection branch (MANDATORY before Step 2 writes the archive doc):** check whether `documentation/archive/{area}/archive-{ID}.md` already exists. A pre-existing file at that exact path under a different task title means a parallel session reserved and archived the same `{TASK-ID}` first (the TOCTOU window between `/dr-init` reservation and this archive commit). Do NOT overwrite it silently. Run the detection probe and apply the retroactive-rename procedure from `$HOME/.claude/skills/dr-init-id-collision-window/SKILL.md` § Detection and § Resolution — retroactive rename before proceeding to Step 2.
2. Create archive document with:
   - **Frontmatter from canonical template** `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` — copy YAML schema (`id`, `title`, `status`, `completed_date`, `complexity`, `type`, `project`, `related`, `archive_doc`, `verification_outcome`). Schema is closed; do not add custom keys.
   - **`verification_outcome` block — MANDATORY at archive time.** Triage the audit log under `datarim/qa/verify-{TASK-ID}-*.md` (if `/dr-verify` ran) and fill the four counters + `dogfood_window` per template comment block:
     - `caught_by_verify` — high/medium gaps that `/dr-verify` surfaced and the operator fixed BEFORE this archive.
     - `missed_by_verify` — initially `0`; updated retroactively if a post-archive follow-up reveals a gap that should have been caught.
     - `false_positive` — `/dr-verify` findings the operator triaged as not real.
     - `n_a: true` — when `/dr-verify` was not invoked (L1 trivial fix or pre-tri-layer task).
     - `dogfood_window` — operator-supplied window-id grouping key consumed by `dev-tools/measure-prospective-rate.sh`.
   - **Top-layer business-facing sections — MANDATORY, exact order, exact headings** (see `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md`):
     1. `## Начальная задача` — one Russian sentence describing what the operator asked for. Source: `datarim/tasks/{TASK-ID}-init-task.md` § Operator brief (verbatim), compressed to a single phrase. <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
     2. `## Как решили` — single-level bullet list, one item per bullet in the operator brief (in original order). Each rendered bullet: bold operator-words quotation, followed by the final `/dr-qa` status word (one of «выполнено», «частично», «не выполнено», «неприменимо» — never the schema enum `met`/`partial`/`missed`/`n-a`) and one or two plain-language sentences sourced from the item's most recent `#### История статусов` line (`reason: …`). <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
        - **Fold expectations into the same list (MANDATORY when `datarim/tasks/{TASK-ID}-expectations.md` exists, per F6 of the init-task contract):** every item from `## Ожидания` is added to the same bullet list, in original order, with the marker `(уточнение брифа)` appended to the operator-words quotation. Do NOT render a separate `## Выполнение ожиданий оператора` section — that top-level heading was retired and its content folded into «Как решили». <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
        - Missing expectations file ⇒ render only brief items; no fallback line is needed (the «Как решили» section already exists because the brief itself does). <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
        - **One-off wish disclosure (R7, per `skills/human-summary/SKILL.md` § One-off wish disclosure):** for each folded expectations item that carries `verification_mode: one-off` (explicit) or that has no `verification_mode` on a world-state-class wish (heuristic: success criterion matches `https?://`, `curl`, `HTTP`, `deploy`, `prod`, `status` — same predicates as the validator), append a one-sentence disclosure in plain language after the status word: «проверено вручную, автоматической проверки нет» (one-off) or «проверялось однократно на живой системе» (heuristic). This surfaces regression risk to the operator explicitly; no follow-up task is required but the operator may choose to file one. Banlist applies.
        - **No tables in this section.** Bullet list only (single-level allowed; nested bullets forbidden).
        - **No anglicisms** — apply the banlist rules from `skills/human-summary/SKILL.md` to the comment text (Russian prose only; ASCII tokens of length ≥3 from `skills/human-summary/banlist.txt` MUST NOT appear unless wrapped in the per-paragraph escape-hatch fence). The two-paragraph fenced budget from `human-summary.md` § Per-paragraph escape hatch applies here as well.
     3. `## Артефакты задачи` — what was produced or changed. Free prose + bullets allowed. File references as relative paths. No verdict tables in this top section. <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
     4. `## Следующие шаги` — either «всё закрыто» or a bullet list of concrete `/dr-*` commands / operator actions. <!-- allow-non-ascii: literal-russian-archive-section-name-and-section-content-from-template -->
   - **Audit addendum under a `---` horizontal rule — MANDATORY, exact order:**
     - `## Дополнительно для аудита` (top-level heading after `---`). <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
     - `### verification_outcome` — human-readable mirror of the YAML frontmatter counters (`caught_by_verify`, `missed_by_verify`, `false_positive`, `n_a`, `dogfood_window`), one bullet per counter.
     - `### Acceptance Criteria` — verdict table (AC / Status / Evidence), one row per AC.
     - `### Lessons Learned` — short ≤3-bullet digest; the full text lives in `reflection-{ID}.md`.
     - `### Operator Handoff` — residual technical debt, deferred improvements, configuration steps for the next operator. «всё закрыто» if empty. <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
     - `### Related` — Parent PRD / Plan / Reflection / Follow-ups.
   - The audit addendum carries the technical surface; the top four sections carry the operator-facing answer to «что я просил и что вы сделали». Banlist applies to the prose in the top four sections; tables and YAML mirrors in the addendum MAY be wrapped in `<!-- gate:literal -->` fence when they include ASCII technical terms. <!-- allow-non-ascii: literal-russian-archive-section-name-from-template -->
   - **Known Loss Verification Gate (MANDATORY when archive will include any "Known Loss" / "Unrecoverable" / "Content lost" statement):**
     Before recording that any file, section, decision, or piece of work is permanently lost, run the Disaster Recovery Checklist from `$HOME/.claude/skills/evolution/SKILL.md` § Disaster Recovery for Lost Runtime Files. Record in the archive document which channels were checked (grep reflections by filename, compacted session context, cross-references, git history of consumer projects, external backups) and what each returned. If the checklist takes >30 minutes, defer the archive, open a follow-up recovery task, do not record the loss yet. Only after all 5 channels are exhausted may a loss claim enter the archive. Rationale: an archive that records files as "text reconstruction is not possible" after 0 minutes of discovery has historically been recovered 100% in <30 minutes using channels 1-3. Always run the checklist first.
3. **BACKLOG UPDATE** (if task existed in backlog):
   - Use the resolved task ID from Step 0
   - If the same ID exists in `datarim/backlog.md` (as `in_progress` or `pending`):
     a. **Remove** that entry from `datarim/backlog.md`
     b. Do **not** write `datarim/backlog-archive.md` — it was abolished in v1.19.1 (see Step 7). The completion record is the archive doc written above at `documentation/archive/{area}/archive-{ID}.md`; the `backlog.md` entry is simply removed (the single-file backlog holds only transient `pending` / `blocked-pending` / `cancelled` — per `skills/datarim-system/backlog-and-routing.md`). Removing the entry in (a) is the whole of the backlog update.
   - If the task ID does not appear in `backlog.md`: skip this step (task was ad hoc, not from backlog)
4. **FOLLOW-UP TASKS** (from reflection):
   - Read `datarim/reflection/reflection-[task_id].md` for "Next Steps" section
   - If follow-up items exist, ask user: "Add these as new backlog items?"
   - If yes: add each as new `{PREFIX}-XXXX` entry in `datarim/backlog.md` with status `pending`. Choose prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system/SKILL.md`) — project or area prefix relevant to the follow-up item
5. **REMOVE FROM tasks.md** (thin-index schema):
   - Delete the one-liner for `{TASK-ID}` from `## Active` in `datarim/tasks.md`. Match by exact `^- {TASK-ID} ·` prefix.
   - Keep all other active task one-liners intact.
   - If a plan file exists at `datarim/plans/{TASK-ID}-plan.md`, delete it. The archive doc is the permanent record.
   - Description file `datarim/tasks/{TASK-ID}-task-description.md` MAY be kept (frontmatter `status: completed`) or deleted at operator discretion — archive supersedes it.
6. **UPDATE activeContext.md** (thin-index schema, v1.19.1):
   - **Remove** the archived task's one-liner from `## Active Tasks` (keep all others).
   - The Active section is **strict mirror** of `tasks.md § Active` — after removal, both files share the same line set.
   - Do NOT write any `## Последние завершённые` / `## Last Completed` / <!-- allow-non-ascii: literal-russian-active-context-section-name-from-canonical-schema -->
     `## Last Updated` section: those were retired in v1.19.1.
     Recency is computed runtime by `/dr-status --recent N` from
     `documentation/archive/**/archive-*.md` mtime-sort.
7. **NO `progress.md` / `backlog-archive.md` UPDATE:**
   - `progress.md` is abolished (v1.19.0). `backlog-archive.md` is abolished
     (v1.19.1). Both are blocked by `pre-archive-check.sh`.
   - Cancelled tasks: write `documentation/archive/cancelled/archive-{ID}.md`
     directly; remove from `backlog.md`.
   - Legacy state (any of those files present): `/dr-doctor --fix` migrates and
     deletes; `/dr-init` Step 2.4 self-heal probe surfaces this on next session.
8. **HUMAN SUMMARY**:
   - Load `$HOME/.claude/skills/human-summary/SKILL.md`.
   - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the archive-mutation block and the CTA block ([definition](../skills/cta-format/SKILL.md)). Language follows the most recent operator message. <!-- allow-non-ascii: literal-russian-section-name-token-from-human-summary-skill -->
   - Source material: the just-written archive document (§ Начальная задача / § Как решили / § Артефакты задачи / § Следующие шаги, plus the audit addendum’s § Operator Handoff) and the reflection file from Step 0.5. <!-- allow-non-ascii: literal-russian-archive-section-names-from-template -->
   - Do NOT mutate the archive document or the reflection file — the summary is chat-only; the archive remains the permanent record.
   - The summary MUST honour the banlist + whitelist + per-paragraph escape-hatch contract from the skill (`<!-- gate:literal -->` … `<!-- /gate:literal -->` for verbatim quoted blocks only; max two fenced paragraphs per summary).
   - Length budget: 150–400 words **total across the four sub-sections** (not per sub-section). Hard upper bound. If sources are bigger, compress.

## Read
- `datarim/tasks.md` (thin index — one-liner for the archived task)
- `datarim/tasks/{TASK-ID}-task-description.md` (full task content, ACs, constraints)
- `datarim/reflection/reflection-[task_id].md` (written by Step 0.5)
- `datarim/creative/*.md` (Level 3-4)
- `datarim/plans/{TASK-ID}-plan.md` (L3-4)
- `datarim/backlog.md` (to find and remove completed/cancelled item)
- `datarim/activeContext.md` (Active Tasks list — strict mirror of tasks.md)
- `$HOME/.claude/skills/datarim-system/SKILL.md` (Operational File Schema, Archive Area Mapping)
- `$HOME/.claude/skills/reflecting/SKILL.md` (loaded by Step 0.5)
- `$HOME/.claude/skills/evolution/SKILL.md` (loaded by Step 0.5 for Class A/B gate)

## Write
- `documentation/archive/[area]/archive-[task_id].md` (NEW — permanent record)
- `datarim/backlog.md` (remove `in_progress`/`pending` entry if present)
- `documentation/archive/cancelled/archive-{ID}.md` (NEW — for cancellation flow)
- `datarim/tasks.md` (remove archived one-liner; preserve other active one-liners)
- `datarim/activeContext.md` (remove from Active Tasks — strict mirror of tasks.md)
- `datarim/plans/{TASK-ID}-plan.md` (DELETE if exists — archive supersedes)
- **Never write `datarim/progress.md`** (abolished as of v1.19.0).

## Cancellation Mode

If user says "cancel task" or "cancel {TASK-ID}":
1. Resolve task ID using Task Resolution Rule (argument or disambiguation).
2. **Remove** the entry from `datarim/backlog.md` (if present)
3. **Write** `documentation/archive/cancelled/archive-{ID}.md` recording status `cancelled`, date, and reason (per `skills/datarim-system/backlog-and-routing.md`). Do **not** write `datarim/backlog-archive.md` — abolished v1.19.1.
4. **Remove** the cancelled task from `## Active Tasks` in `activeContext.md` (keep other active tasks)
5. Clear task from `tasks.md`
6. The cancelled-archive stub from step 3 is the only record (no full completion archive — task shipped no deliverable)

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND the matching per-task marker — resolved via `dev-tools/auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`, per-task `datarim/.auto/<TASK-ID>.mode` with legacy `datarim/.auto-mode-active` fallback — containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Step 0.5 reflection apply gate — Class A L1 proposals applied in-cycle per L1 Inline Resolution Rule ([definition](../skills/autonomous-mode/SKILL.md)); Class B requires L5.
   - Consume `datarim/tasks/{TASK-ID}-auto-inline-log.md` (if present) into Reflection § «Inline-resolved gaps» section.
   - Operator handoff items list — auto-skip items resolved through Ladder during cycle; surface only true L5 escalations.
3. Discovered gaps → apply L1 Inline Resolution Rule per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After archive, the planner agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format/SKILL.md`. After archiving, the just-archived task is removed from `## Active Tasks`; CTA reflects the new state of activeContext.

**Routing logic for `/dr-archive`:**

- Archive completed, other active tasks remain → primary `/dr-next` (resume the next active task) + alternative `/dr-status`
- Archive completed, no other active tasks → primary `/dr-init` (start new work) + alternative "pick from backlog"
- Knowledge base grew >5 docs since last maintenance → alternative `/dr-dream` (housekeeping)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format. If multiple tasks remain active after this archive, render Variant B menu (`**Другие активные задачи:**`). <!-- allow-non-ascii: literal-russian-variant-b-menu-token-from-cta-format-skill -->

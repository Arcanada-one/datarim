# Codex CLI slash-command discoverability — upstream advocacy brief

**Status:** submission kit / draft. **Last verified:** 2026-07-22.
**Owner action required:** the actual GitHub submission is a public, outward-facing
action and is left to the operator. This document is the ready-to-post material and the
reasoning behind it.

Datarim installs its `/dr-*` command catalogue under `~/.codex/commands/` for Codex CLI,
but Codex does not surface those files in its `/`-prefix popup the way Claude Code does
(see `documentation/how-to/multi-runtime.md` § "Why no `/`-popup menu in Codex?"). This
brief is the outcome of investigating whether an upstream feature request could close
that discoverability gap.

## 1. Summary & recommendation

**Do not file a directory-mirror slash-command request.** That exact mechanism has
already been proposed upstream twice and closed as "not planned" (see §2). Instead, if we
pursue upstream advocacy at all, file **one narrow, direction-aligned ask**: let a
**Skill** optionally surface in the slash-command menu (an opt-in "expose me as a slash
command" flag). This respects OpenAI's stated Skills-first direction while closing the
*discoverability* gap, and is genuinely differentiated from the two rejected requests.

If even that is declined, the durable posture is already in place and costs nothing:
Datarim commands remain reachable by name/path, and the recommended pattern is to name
the command in the prompt. Active advocacy on this item is **low-expected-value** (the
originating reflection already rated it "may never close") — this brief exists so the
decision to spend or not spend that effort is made on evidence, not assumption.

## 2. Landscape & evidence (public, 2026-07-22)

- **The Codex slash menu is effectively hardcoded.** Built-ins (`/model`, `/status`,
  `/skills`, `/prompts:…`) are host-runtime features; there is no indexing layer that
  crawls user command markdown into the `/`-popup.

- **Custom prompts are officially deprecated.** `~/.codex/prompts/*.md → /prompts:<name>`
  still works, but the documentation states verbatim:

  > "Deprecated. Use skills for reusable prompts."

  Source: `learn.chatgpt.com/docs/custom-prompts` (formerly
  `developers.openai.com/codex/custom-prompts`).

- **The requested directory-mirror mechanism was already proposed — twice — and
  declined:**

  | Issue | Ask | Status |
  |-------|-----|--------|
  | `openai/codex#22674` | Zero-config slash commands from `.agents/commands/` and `~/.agents/commands/` — markdown + frontmatter, auto-discovery, project/user precedence (nearly identical to a `skills_commands/` mirror). | **Closed — not planned** |
  | `openai/codex#18857` | User-defined local slash commands in interactive sessions (`~/.codex/commands` or `config.toml`). | **Closed — not planned** |

  No written maintainer rationale was visible beyond the "not planned" status. Related,
  still in the space and worth reading before any post: `#4311` (SlashCommand tool-style
  auto invocation), `#3007` (slash commands in the extension), `#3641` (slash commands in
  `exec` mode), `#5392`, `#30027`.

- **OpenAI's forward direction is Skills.** Skills are invoked explicitly or implicitly
  by name and are repo-shareable — but they do **not** surface as a `/`-popup slash menu.
  So the discoverability gap persists even on the recommended path. That residual gap is
  the *only* still-unaddressed angle, and it is what the recommended ask below targets.

**Why this matters for the original brief.** The task was scoped to propose a
`skills_commands/` directory-mirror. That shape is functionally what `#22674` asked for
and was rejected. Re-filing it would be a near-duplicate and low-signal advocacy.

## 3. Recommended ask — ready-to-post GitHub issue draft (Option 2)

> **Operator note:** paste the block below into a new issue on `github.com/openai/codex`
> only after re-verifying the referenced issue statuses. The block is intentionally free
> of any Datarim-internal identifiers so it can be posted as-is.

---

**Title:** Feature request: let a Skill opt in to appearing in the `/` slash-command menu

**Body:**

Skills are now the recommended way to package reusable instructions for Codex CLI (custom
prompts being deprecated in their favour). Skills can be invoked explicitly or
implicitly by name — but they do not appear in the interactive `/`-popup, so a user who
has installed a set of skills has no in-REPL way to *discover* or quick-select them.

I want to raise a deliberately narrow request that is different from the
already-declined "user-defined slash commands" proposals (`#22674`, `#18857` — both
closed as not planned). I am **not** asking for a new arbitrary-command surface. I am
asking only that the mechanism Codex already supports and recommends — Skills — become
**discoverable** from the slash menu.

**Proposal:** an opt-in frontmatter flag on a skill, e.g.

```yaml
# ~/.codex/skills/deploy/SKILL.md
---
name: deploy
description: Ship the current branch to staging
slash: true        # opt-in: also surface as /deploy in the `/` popup
---
```

When `slash: true`, Codex lists the skill in the `/`-popup (e.g. `/deploy`) with its
`description`, and selecting it invokes the skill exactly as invoking it by name would.
No new execution path, no new file location, no local-only "run a shell command" surface
(the thing `#18857` was about) — purely a discoverability affordance over the existing,
recommended Skills mechanism. Default is `false`, so nothing changes for users who do not
opt in.

**Why this is worth doing even though the earlier requests were declined:**
- It does not reintroduce the rejected "register arbitrary user slash commands" surface;
  it is scoped strictly to Skills, which Codex already indexes.
- It aligns with the Skills-first direction rather than working against it.
- It gives tool authors who ship many skills (agent frameworks, internal tooling) an
  in-REPL discovery path, which is currently missing on both the deprecated
  (`/prompts:`) and the recommended (Skills) mechanisms.

Happy to prototype behind a config flag if there is maintainer appetite.

---

## 4. Appendix A — original directory-mirror design (Option 1, retained for reference)

> **Caveat:** this is the mechanism the task was originally scoped to propose. Upstream
> already declined an equivalent shape (`#22674`, closed not planned). It is kept here so
> the design is not lost and can be revived if maintainer direction reverses — but it is
> **not** the recommended thing to file today.

Minimal API sketch (design only, not a Rust patch):

- A discovery root `~/.codex/commands/` (user) and `<repo>/.codex/commands/` (project).
- Each command is a markdown file with optional YAML frontmatter:
  `name` (fallback: filename), `description`, `aliases`, `args`.
- Codex crawls both roots on REPL start, registers each as a `/<name>` entry with the
  `description` shown in the popup; project entries override user entries by name.
- Selecting `/<name>` loads the file's body as the turn instructions (same semantics as
  referencing the file by name today).
- Same sandbox/permission rules as normal instructions; no implicit shell execution.

This is essentially `#22674`'s proposal; its rejection is the reason Option 2 (Skills
discoverability) is preferred.

## 5. Fallback posture (Option 3) & Datarim-side follow-up

- **Durable posture (no upstream change).** Datarim command markdown stays reachable
  under `~/.codex/commands/`; the recommended Codex pattern is to name the command in the
  prompt (e.g. "follow `commands/dr-do.md`…"). This already works and requires nothing
  from upstream. Treat true `/`-popup parity as an upstream *nice-to-have*, not a Datarim
  runtime gap.

- **Deprecated bridge — follow-up.** Datarim's opt-in `/prompts:dr-*` bridge
  (`--enable-codex-prompts`) rides the officially deprecated custom-prompts mechanism.
  It still works, but a future Codex release may remove it; this is an accepted risk.
  The forward-compatible path is Skills, which Datarim already installs
  under `~/.codex/skills/`. **Suggested follow-up task:** evaluate migrating the
  `/prompts:dr-*` bridge posture to a Skills-based discovery story (and, if the Option 2
  ask above is ever accepted, adopt `slash: true` on the relevant skills). No action
  required now.

## 6. Operator submission checklist (hard-gated actions)

Posting to a public external repo is outward-facing and hard-gated — do this manually:

1. Re-verify current status of `#22674`, `#18857`, `#4311` and the custom-prompts
   deprecation notice (state may have drifted since 2026-07-22).
2. Search open issues for a Skills-discoverability duplicate before posting §3.
3. Post the §3 block as a new issue (or as a comment on the closest open issue if one
   now exists). Capture the issue URL + any maintainer reply back into this file's
   history.
4. If declined or ignored, adopt the §5 durable posture and close active advocacy.

## Sources

- Codex custom-prompts deprecation — `learn.chatgpt.com/docs/custom-prompts`
- `openai/codex#22674` — zero-config slash commands (closed, not planned)
- `openai/codex#18857` — user-defined local slash commands (closed, not planned)
- Related cluster — `openai/codex` `#4311`, `#3007`, `#3641`, `#5392`, `#30027`

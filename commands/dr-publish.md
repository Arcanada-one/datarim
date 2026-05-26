---
name: dr-publish
description: Format and publish approved content to target platforms. Loads publishing rules, adapts text per platform, runs pre-publish checks.
argument-hint: [file path to approved content]
---

# /dr-publish — Publish Content

**Role**: Writer Agent
**Source**: `$HOME/.claude/agents/writer.md`

## Instructions


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `$HOME/.claude/agents/writer.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system/SKILL.md` (Always)
    - `$HOME/.claude/skills/publishing/SKILL.md` (Platform rules, limits, formatting, workflow)
3.  **READ THE CONTENT**: Read the file at the path provided in `$ARGUMENTS`. If no path given, ask the user.
4.  **CONFIRM READINESS**:
    - Has the content been through `/dr-edit`? If not, warn: "This content hasn't been editorially reviewed. Proceed anyway or run `/dr-edit` first?"
    - Identify the content type and length.
5.  **DETERMINE TARGETS**: Ask the user which platforms to publish to:
    - Telegram channel
    - LinkedIn
    - Facebook
    - X / Twitter
    - VK
    - Instagram
    - Website / blog
    - Or: "all" / "social" / specific list
6.  **ADAPT PER PLATFORM**:
    For each target platform:
    - Check text length against platform limits. If over limit → trim or split.
    - Convert formatting (HTML for Telegram, plain text for LinkedIn/FB/X, etc.).
    - Prepare images/media in platform-optimal dimensions if applicable.
    - For websites: verify OG tags, meta description, canonical URL, heading hierarchy.
    - For Telegram: use UTF-16 unit counter from `publishing.md` § Character counting. For photo + text >1024 → photo+reply Pattern A (≤5096 total) or Pattern C (>5096 → photo + N text parts, each `[i/N]`-prefixed). For comments on channel posts → use `forward_origin.message_id` polling recipe.
    - Present each platform version to the user for approval.
7.  **PRE-PUBLISH CHECKLIST**:
    - [ ] Text within platform limits
    - [ ] Formatting renders correctly (no raw HTML/Markdown)
    - [ ] Links are valid and clickable
    - [ ] Images sized correctly for platform
    - [ ] OG tags present (for website/blog)
    - [ ] Test sent to private chat / staging (for Telegram, recommend testing first)
8.  **PUBLISH**: After user approves each version:
    - For Telegram Bot API: provide ready `sendMessage`/`sendPhoto` payloads
    - For websites: apply content to the target file, update sitemap/RSS if applicable
    - For other platforms: provide formatted text ready to paste, with platform-specific notes
9.  **POST-PUBLISH**:
    - Verify link previews render correctly (suggest debugger URLs per platform)
    - Note the publication date for the content record

## Output
- Per-platform formatted versions of the content
- Pre-publish checklist (passed/failed)
- Publication instructions or applied changes

## Next Steps (CTA)

After publish, the writer/editor agent MUST emit a CTA block ([definition](../skills/cta-format.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-publish`:**

- Content task in Datarim pipeline → primary `/dr-archive {TASK-ID}` (final archive)
- Need to write more content → primary `/dr-write {TASK-ID}`
- Need to edit before re-publishing → primary `/dr-edit {TASK-ID}`
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format defined in `skills/cta-format/SKILL.md` (numbered options, exactly one primary marker, `---` HR). Variant B menu when >1 active tasks.

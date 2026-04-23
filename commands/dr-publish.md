---
name: dr-publish
description: Format and publish approved content to target platforms — social media, blogs, websites. Loads publishing rules, adapts text per platform, runs pre-publish checks.
argument-hint: [file path to approved content]
---

# /dr-publish — Publish Content

**Role**: Writer Agent
**Source**: `$HOME/.claude/agents/writer.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/writer.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/publishing.md` (Platform rules, limits, formatting, workflow)
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
    - For Telegram: if text >1024 and needs photo → plan photo+reply pattern.
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

## Next Steps
- Content task in Datarim pipeline? → `/dr-archive`
- Need to write more content? → `/dr-write`
- Need to edit before publishing? → `/dr-edit`

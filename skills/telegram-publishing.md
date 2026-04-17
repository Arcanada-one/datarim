---
name: telegram-publishing
description: Telegram channel publishing via Bot API — caption limits, formatting, discussion group comments, and testing workflow.
model: haiku
---

# Telegram Publishing via Bot API

Rules for publishing content to Telegram channels and groups using the Bot API.

## API Limits

| Method | Max text length | Supports HTML/Markdown |
|--------|----------------|----------------------|
| sendPhoto caption | 1024 chars | Yes |
| sendMessage text | 4096 chars | Yes |
| sendVideo caption | 1024 chars | Yes |

## Publishing Patterns

### Photo + Long Text (>1024 chars)
Cannot fit in a single sendPhoto caption. Options:
1. **Photo with short caption + text as reply** — send photo first, then sendMessage with `reply_to_message_id` pointing to the photo message
2. **Text message only** — skip photo, use link preview for visual
3. **Trim to 1024** — compress text to fit caption limit

### Comments on Channel Posts
`reply_to_message_id` in a channel does NOT create a comment. It creates another channel post. To post a comment:
1. Get the channel's linked discussion group via `getChat` → `linked_chat_id`
2. After posting to channel, find the auto-forwarded message in the discussion group
3. Send reply to that auto-forwarded message in the discussion group

### HTML Formatting
Supported tags: `<b>`, `<i>`, `<u>`, `<s>`, `<a href="">`, `<code>`, `<pre>`, `<blockquote>`
Not supported: `<h1>-<h6>`, `<p>`, `<br>`, `<div>`, `<table>`
Use `parse_mode=HTML` in API calls.

## Workflow

1. **Always test in personal chat first** — send to the author's private chat with the bot
2. **Get approval** before publishing to channel
3. **Prepare comment text** with links separately
4. **Publish to channel** — photo, then text
5. **Post comment** via discussion group API (not reply_to in channel)

## Credentials
Bot token and chat IDs stored in `Areas/Credentials/Telegram.md`

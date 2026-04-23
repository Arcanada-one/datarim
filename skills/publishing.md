---
name: publishing
description: Technical rules for publishing content to social media and websites — platform limits, formatting, API patterns, OG tags, multi-platform workflow.
model: haiku
---

# Publishing — Technical Rules for Content Distribution

Rules for the **technical act** of publishing ready content to platforms. This skill does NOT cover writing (see `writing` skill) or quality review (see `humanize`, `factcheck` skills). It covers: how to format, what limits apply, how to post correctly.

Credentials, channel URLs, bot tokens, and site-specific config live outside this skill (typically in credentials files or project config).

---

## Platform Limits

### Telegram (Bot API)

| Method | Max text | Formatting |
|--------|----------|------------|
| `sendMessage` text | 4096 chars | HTML or MarkdownV2 |
| `sendPhoto` caption | 1024 chars | HTML or MarkdownV2 |
| `sendVideo` caption | 1024 chars | HTML or MarkdownV2 |
| `sendDocument` caption | 1024 chars | HTML or MarkdownV2 |
| `sendMediaGroup` caption | 1024 chars per item | HTML or MarkdownV2 |

**Supported HTML**: `<b>`, `<i>`, `<u>`, `<s>`, `<a href="">`, `<code>`, `<pre>`, `<blockquote>`, `<tg-spoiler>`, `<tg-emoji>`
**Not supported**: `<h1>`–`<h6>`, `<p>`, `<br>`, `<div>`, `<table>`, `<img>`
Use `parse_mode=HTML` (preferred) or `parse_mode=MarkdownV2`.

**Photo + long text (>1024 chars):**
1. `sendPhoto` with short caption → then `sendMessage` with full text as reply (`reply_to_message_id`)
2. Or: `sendMessage` only, link preview provides the visual

**Comments on channel posts:**
`reply_to_message_id` in a channel creates another channel post, NOT a comment. To post a comment:
1. `getChat` on the channel → `linked_chat_id` (the discussion group)
2. Post to channel → find the auto-forwarded message in the discussion group
3. Reply to that message in the discussion group

### LinkedIn

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 3000 chars | No HTML, no Markdown |
| Article title | 100 chars | Plain text |
| Article body | 110,000 chars | Rich text (via editor) |
| Comment | 1250 chars | Plain text |

**Formatting**: Line breaks preserved. No bold/italic/links in post text via API — use Unicode bold (𝗯𝗼𝗹𝗱) if needed, but sparingly. Hashtags at the end. Links in text trigger preview card.
**Images**: 1200×627 px optimal for link previews. Max 9 images per post.
**Video**: Max 10 min, 5 GB. Native upload gets better reach than YouTube links.

### Facebook

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 63,206 chars | No HTML, no Markdown |
| Comment | 8,000 chars | Plain text |
| Link description | 500 chars | Via OG tags |

**Formatting**: Line breaks and emoji supported. No rich text in posts via API. Links generate preview cards from OG tags.
**Images**: 1200×630 px for shared images. Max 10 per post.
**Video**: Max 240 min, 10 GB.

### X / Twitter

| Field | Max length | Formatting |
|-------|-----------|------------|
| Tweet | 280 chars (free) / 25,000 (Premium+) | No HTML, no Markdown |
| Thread | Unlimited tweets | Each ≤280/25,000 |
| DM | 10,000 chars | Plain text |

**Formatting**: No rich text. Links count as 23 chars (t.co wrapping). Up to 4 images, 1 video, or 1 GIF per tweet.
**Images**: 1600×900 px optimal. Max 5 MB (JPG/PNG), 15 MB (GIF).
**Video**: Max 2:20 (free) / 60 min (Premium), 512 MB.

### VK

| Field | Max length | Formatting |
|-------|-----------|------------|
| Post text | 15,895 chars | Limited HTML via API |
| Comment | 4,096 chars | Plain text |

**Formatting**: API supports `<b>`, `<i>`, `<a>`. Line breaks preserved. Hashtags work.
**Images**: Up to 10 per post. Optimal 1200×800 px.
**Video**: Upload or link from external services.

### Instagram

| Field | Max length | Formatting |
|-------|-----------|------------|
| Caption | 2,200 chars | No HTML, no Markdown |
| Comment | 2,200 chars | Plain text |
| Bio | 150 chars | Plain text |
| Story text | ~200 chars | Overlay |

**Formatting**: Line breaks via mobile only (or Unicode line break `\n` via API). No clickable links in captions (only in bio and stories with 10K+ followers or link sticker).
**Images**: 1080×1080 (square), 1080×1350 (portrait), 1080×566 (landscape). Max 10 per carousel.
**Video/Reels**: Max 90 sec (Reels), 60 sec (feed), 15 sec (stories). Max 650 MB.
**Hashtags**: Max 30 per post, 10–15 recommended.

---

## Website Publishing

### OG Tags (Open Graph)

Required for proper link previews on all social platforms:

```html
<meta property="og:title" content="Title — max 60 chars">
<meta property="og:description" content="Description — 120-160 chars">
<meta property="og:image" content="https://example.com/img/og.png">
<meta property="og:url" content="https://example.com/page">
<meta property="og:type" content="article">
<meta property="og:locale" content="ru_RU">
```

**OG image**: 1200×630 px, PNG or JPG, <5 MB. Text on image should be readable at thumbnail size.

### Twitter Card Tags

```html
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Title">
<meta name="twitter:description" content="Description">
<meta name="twitter:image" content="https://example.com/img/og.png">
```

### Blog Post Technical Checklist

- [ ] URL is slug-friendly (`/blog/my-post-title`, not `/blog/123`)
- [ ] `<title>` and `<meta description>` are unique and within limits
- [ ] OG tags and Twitter Card tags present
- [ ] `<link rel="canonical">` set
- [ ] Heading hierarchy correct (one `<h1>`, logical `<h2>`→`<h3>`)
- [ ] Images have `alt` text, are optimized (<200 KB), use modern formats (WebP)
- [ ] Internal links use relative paths or full URLs consistently
- [ ] Multi-language: `<link rel="alternate" hreflang="ru">` if applicable
- [ ] RSS feed updated (if exists)
- [ ] Sitemap regenerated (if static)

---

## Multi-Platform Workflow

### Adapting One Post for Multiple Platforms

1. **Start from the longest version** (Telegram/Facebook — most text capacity)
2. **Adapt down** for constrained platforms:
   - LinkedIn: trim to 3000, remove HTML formatting, add hashtags
   - X/Twitter: extract the hook + link, or create a thread
   - Instagram: rewrite as caption, prepare a visual
   - VK: similar to Facebook, adjust formatting

### Platform-Specific Patterns

| Pattern | Telegram | LinkedIn | Facebook | X | VK | Instagram |
|---------|----------|----------|----------|---|-----|-----------|
| Links clickable in text | Yes | Yes | Yes | Yes (shortened) | Yes | No (bio only) |
| Hashtags useful | Moderate | Yes | Low | Yes | Yes | Yes (max 30) |
| Line breaks preserved | Yes | Yes | Yes | Yes | Yes | Via API only |
| Rich text | HTML subset | No | No | No | HTML subset | No |
| Link preview card | Yes | Yes | Yes | Yes | Yes | No |
| Best post length | 500-2000 chars | 1000-2000 chars | 500-3000 chars | 100-280 chars | 500-2000 chars | 500-1500 chars |

### Publication Order

Recommended sequence for maximum reach:
1. **Website/blog** first (canonical URL, SEO indexing starts)
2. **Telegram** (instant delivery to subscribers)
3. **LinkedIn** (professional audience, slower feed)
4. **Facebook** (broad audience)
5. **X/Twitter** (hook + link to full post)
6. **VK** (if relevant audience)
7. **Instagram** (requires visual, last because most adaptation needed)

---

## Testing and Verification

1. **Always test before publishing** — send to a private chat/draft/staging first
2. **Check link previews** — after posting a URL, verify OG card renders correctly
3. **Verify formatting** — HTML tags rendered, not shown as raw text
4. **Check image display** — cropping, resolution, text readability at thumbnail size
5. **Test on mobile** — most social media consumption is mobile
6. **OG cache busting** — platforms cache previews; after updating OG tags:
   - Facebook: use Sharing Debugger (`developers.facebook.com/tools/debug/`)
   - LinkedIn: use Post Inspector (`linkedin.com/post-inspector/`)
   - Telegram: send link to @webpagebot or re-send with `?v=2` query param
   - X/Twitter: use Card Validator

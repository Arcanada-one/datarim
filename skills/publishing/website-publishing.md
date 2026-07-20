---
name: publishing-website
description: Website/blog publishing rules — OG tags, Twitter Card tags, blog post technical checklist. Fragment of `publishing`; load when publishing to a website/blog.
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
- [ ] Audio narration (if the blog has a player): RU+EN text run through the versioned lexicon-normalizer before TTS (acronyms→phonetic, numbers→words, stress via accentuator+override, dash→comma) — never ad-hoc per-article scripts; every heading AND paragraph ends a sentence (extractor adds the period; headings get a doubled pause) so blocks do not glue together; the author's cloned voice available as an option if the deployment provides one (see § Blog audio narration); MP3s uploaded to R2 AND Cloudflare cache purged for the audio URLs

---

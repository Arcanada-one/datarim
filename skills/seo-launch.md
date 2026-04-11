---
name: seo-launch
description: SEO audit, analytics setup, and website launch preparation. Technical SEO checklist, Core Web Vitals, GA4/GSC configuration, structured data, pre-launch verification, and App Store/Google Play submission guidelines. Use for any web property or app launch.
---

# SEO & Launch — Technical Optimization and Publication Readiness

Rules and checklists for search optimization, analytics, and launch preparation across web and mobile platforms.

---

## Technical SEO Checklist

### Crawlability & Indexing
- [ ] `robots.txt` allows indexing of all public pages
- [ ] XML sitemap exists, is valid, and submitted to Google Search Console
- [ ] No unintentional `noindex` or `nofollow` directives
- [ ] Canonical tags are correct on all pages (no self-referencing loops)
- [ ] No duplicate content across different URLs (www vs non-www, http vs https, trailing slash)
- [ ] 301 redirects for all changed URLs (no chains >2 hops)
- [ ] Hreflang tags correct for multilingual sites

### On-Page SEO
- [ ] Unique, descriptive `<title>` for every page (50-60 chars)
- [ ] Unique `<meta description>` for every page (120-160 chars)
- [ ] One `<h1>` per page, includes primary keyword
- [ ] Heading hierarchy logical (h1 → h2 → h3, no skips)
- [ ] Images have descriptive `alt` text
- [ ] Internal links use descriptive anchor text (not "click here")
- [ ] URL structure is clean, readable, includes keywords

### Structured Data
- [ ] JSON-LD schema markup for content type (Article, Product, FAQ, Organization, etc.)
- [ ] Schema validates at schema.org validator and Google Rich Results Test
- [ ] Breadcrumb schema on all interior pages
- [ ] FAQ schema where appropriate (drives featured snippets)

### Core Web Vitals (2026 targets)
- [ ] LCP (Largest Contentful Paint) < 2.5s
- [ ] INP (Interaction to Next Paint) < 200ms
- [ ] CLS (Cumulative Layout Shift) < 0.1
- [ ] Total page weight < 2MB (desktop), < 1MB (mobile)
- [ ] All images lazy-loaded below the fold
- [ ] Critical CSS inlined, non-critical deferred

---

## Analytics Setup Checklist

### Google Analytics 4
- [ ] GA4 property created with correct data stream
- [ ] Measurement ID installed on all pages
- [ ] Enhanced measurement enabled (scrolls, outbound clicks, site search, file downloads)
- [ ] Custom events configured for key actions (signup, purchase, form submit)
- [ ] Conversion events marked
- [ ] Data retention set to maximum (14 months)
- [ ] IP anonymization enabled (GDPR)
- [ ] Cross-domain tracking configured (if multiple domains)
- [ ] Debug mode tested, events verified in Realtime report

### Google Search Console
- [ ] Property verified (DNS or HTML tag)
- [ ] Sitemap submitted
- [ ] No critical errors in Coverage report
- [ ] Mobile Usability: no issues
- [ ] Core Web Vitals: no failing URLs

### Additional Tracking
- [ ] Facebook Pixel / Meta Conversions API (if using Meta Ads)
- [ ] Google Ads conversion tracking (if using Google Ads)
- [ ] UTM parameter convention documented for the team
- [ ] Cookie consent banner configured (GDPR/CCPA)

---

## Website Pre-Launch Checklist

### Domain & SSL
- [ ] Domain DNS configured correctly (A record, CNAME)
- [ ] SSL certificate installed and valid (HTTPS everywhere)
- [ ] HTTP → HTTPS redirect in place
- [ ] www ↔ non-www redirect configured (choose one canonical)
- [ ] HSTS header enabled

### Content & UX
- [ ] All placeholder content replaced
- [ ] 404 page customized and helpful
- [ ] Contact information correct and visible
- [ ] Forms tested (submission, validation, confirmation emails)
- [ ] Social media links correct

### Social Previews
- [ ] OpenGraph meta tags (og:title, og:description, og:image) on all pages
- [ ] Twitter Card meta tags
- [ ] OG image is 1200×630px, looks good when shared
- [ ] Preview tested on Facebook Debugger, Twitter Card Validator

### Legal & Compliance
- [ ] Privacy Policy page linked in footer
- [ ] Terms of Service page (if applicable)
- [ ] Cookie consent banner (EU/GDPR)
- [ ] Accessibility statement (if required)
- [ ] Copyright year current

### Performance & Quality
- [ ] All pages pass PageSpeed Insights (mobile score >80)
- [ ] No broken links (run full crawl)
- [ ] No mixed content warnings
- [ ] Favicon installed (multiple sizes: 16, 32, 180, 192, 512)
- [ ] manifest.json for PWA (if applicable)
- [ ] Cross-browser tested (Chrome, Firefox, Safari, Edge)
- [ ] Mobile responsive on 3+ screen sizes

---

## App Store Submission Checklist

### Apple App Store
- [ ] App Store Connect account active
- [ ] App name (30 chars max), subtitle (30 chars), keyword field (100 chars) optimized
- [ ] Description written for humans (not indexed by Apple)
- [ ] Screenshots: 6 sizes (6.9", 6.7", 6.5", 5.5" iPhones + iPad if universal)
- [ ] App Preview video (optional but improves conversion 20-35%)
- [ ] Privacy Nutrition Labels completed accurately
- [ ] App Privacy Policy URL valid
- [ ] EULA / License Agreement (custom or Apple standard)
- [ ] Age Rating questionnaire completed
- [ ] Export Compliance declared
- [ ] Categories selected (primary + secondary)
- [ ] TestFlight build tested by beta users
- [ ] Release notes written

### Google Play Store
- [ ] Google Play Console account active
- [ ] App title (30 chars), short description (80 chars), full description (4000 chars) optimized with keywords
- [ ] Feature graphic (1024×500px)
- [ ] Screenshots: phone (2-8), 7" tablet, 10" tablet
- [ ] Content rating questionnaire completed
- [ ] Data safety section completed
- [ ] Target audience and content declared
- [ ] App signing by Google Play configured
- [ ] Internal/closed testing track used before production release

### Common for Both Stores
- [ ] App icon follows platform guidelines (1024×1024 for Apple, 512×512 for Google)
- [ ] Descriptions localized for target markets
- [ ] Keywords researched per locale (not just translated)
- [ ] Support URL and contact email valid
- [ ] No policy violations in content or metadata

---

## GEO (Generative Engine Optimization) — 2026 Addition

Optimize for AI search engines (ChatGPT, Gemini, Perplexity) alongside traditional SEO:

- [ ] Content structured with clear claims, evidence, and citations
- [ ] Pages answer specific questions directly (featured snippet format)
- [ ] Brand mentioned consistently across authoritative sources
- [ ] Schema markup complete (helps AI parsers understand content)
- [ ] FAQ sections with concise, citable answers
- [ ] Content uses semantic structure (not just keywords)

---

## When to Use This Skill

- `/dr-do` or `/dr-qa` for any web project — load this skill for SEO verification
- `/dr-compliance` — integrates with the website and content checklists
- Before any website launch, app submission, or marketing campaign
- During `/dr-dream` — to verify SEO health of documented web properties

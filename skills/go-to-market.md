---
name: go-to-market
description: SEO, analytics, ad campaigns, landing pages, A/B testing, and launch checklists for web, mobile, and marketing campaigns.
model: sonnet
---

# Go-to-Market — SEO, Analytics, Campaigns & Launch

Rules and checklists for search optimization, analytics, digital marketing campaigns, and launch preparation.

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
- [ ] Heading hierarchy logical (h1 > h2 > h3, no skips)
- [ ] Images have descriptive `alt` text
- [ ] Internal links use descriptive anchor text (not "click here")
- [ ] URL structure is clean, readable, includes keywords

### Structured Data
- [ ] JSON-LD schema markup for content type (Article, Product, FAQ, Organization, etc.)
- [ ] Schema validates at schema.org validator and Google Rich Results Test
- [ ] Breadcrumb schema on all interior pages
- [ ] FAQ schema where appropriate (drives featured snippets)

### Core Web Vitals (2026 targets)
- [ ] LCP < 2.5s
- [ ] INP < 200ms
- [ ] CLS < 0.1
- [ ] Total page weight < 2MB (desktop), < 1MB (mobile)
- [ ] All images lazy-loaded below the fold
- [ ] Critical CSS inlined, non-critical deferred

---

## Analytics Setup

### Google Analytics 4
- [ ] GA4 property with correct data stream
- [ ] Enhanced measurement enabled (scrolls, outbound clicks, site search, file downloads)
- [ ] Custom events for key actions (signup, purchase, form submit)
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

### Ad Platform Tracking
- [ ] Google Ads conversion tag installed and verified
- [ ] Meta Pixel + Conversions API (server-side) configured
- [ ] Key events defined: purchase, lead, signup, add-to-cart
- [ ] Attribution window set (7-day click, 1-day view default)
- [ ] UTM parameters on all ad destination URLs
- [ ] Test conversion verified in platform dashboard

---

## Ad Campaign Structure

### Google Ads
1. **Hierarchy:** Account > Campaigns > Ad Groups > Ads > Keywords
2. **Campaign types:** Brand (exact match), Competitor (careful ad copy), Generic (highest volume)
3. **Ad group rules:** 10-20 themed keywords, 3-5 responsive headlines, negative keywords at campaign level

### Meta (Facebook/Instagram) Ads
1. **Hierarchy:** Campaign (objective) > Ad Set (audience + budget) > Ad (creative)
2. **Audience strategy:** Cold (lookalike), Warm (website/email), Hot (cart abandoners)
3. **Creative rules:** benefit in first 3s (video) or headline (static), test 3-5 variations, UGC > polished

---

## Landing Page Optimization

### Above the Fold
- [ ] Headline matching ad promise (message match)
- [ ] Value proposition subheadline
- [ ] One primary CTA (contrasting color, action verb)
- [ ] Social proof (logos, testimonials, customer count)
- [ ] No navigation menu (reduce escape routes)

### Below the Fold
- [ ] Feature/benefit blocks with specifics (numbers, not adjectives)
- [ ] FAQ addressing objections
- [ ] Secondary CTA repeating the offer
- [ ] Trust signals: security badges, guarantees, privacy note

### Technical
- [ ] Mobile-responsive (60%+ traffic is mobile)
- [ ] PageSpeed > 80 mobile
- [ ] Minimal form fields, inline validation

---

## A/B Testing Framework

### Priority Order
1. Headline  2. CTA button  3. Social proof  4. Hero image/video  5. Form length  6. Price presentation

### Rules
- One variable per test
- Min 200 conversions per variant before declaring winner
- Run for 2+ full business cycles (~2 weeks)
- Document: variant, metric, lift, confidence, date range

---

## Email Campaign Checklist

### Pre-Send
- [ ] Subject line A/B tested (10-15% of list)
- [ ] Preview text set explicitly
- [ ] Unsubscribe link visible and working
- [ ] Physical address included (CAN-SPAM)
- [ ] Links tested (UTM tagged, no broken URLs)
- [ ] Images have alt text
- [ ] Mobile preview checked
- [ ] Spam score checked

### Automation Sequences
- Welcome: 3-5 emails over 7-14 days
- Onboarding: feature education, time-to-value
- Cart abandonment: 3 emails (1h, 24h, 72h)
- Re-engagement: 30/60/90 day inactive triggers

---

## Campaign Budget Framework

- 70% proven channels/audiences
- 20% testing new audiences/creatives
- 10% experimental (new platforms, formats)

### Key Metrics
| Metric | Healthy Range |
|--------|--------------|
| CPA | < target CPA |
| ROAS | > 3x (e-commerce) |
| CTR | > 2% search, > 0.8% display |
| CVR | > 2% landing page |
| CAC Payback | < 12 months |

---

## Website Pre-Launch Checklist

### Domain & SSL
- [ ] DNS configured (A/CNAME)
- [ ] SSL valid (HTTPS everywhere)
- [ ] HTTP > HTTPS redirect
- [ ] www/non-www canonical redirect
- [ ] HSTS header enabled

### Content & UX
- [ ] All placeholder content replaced
- [ ] 404 page customized
- [ ] Contact info correct and visible
- [ ] Forms tested (submission, validation, confirmation)
- [ ] Social media links correct

### Social Previews
- [ ] OpenGraph tags (og:title, og:description, og:image 1200x630px)
- [ ] Twitter Card tags
- [ ] Preview tested on platform debuggers

### Legal & Compliance
- [ ] Privacy Policy linked in footer
- [ ] Terms of Service (if applicable)
- [ ] Cookie consent banner (GDPR)
- [ ] Copyright year current

### Performance
- [ ] PageSpeed mobile > 80
- [ ] No broken links (full crawl)
- [ ] No mixed content warnings
- [ ] Favicon installed (16, 32, 180, 192, 512)
- [ ] Cross-browser tested (Chrome, Firefox, Safari, Edge)
- [ ] Mobile responsive on 3+ screen sizes
- [ ] Static assets versioned for CDN cache busting

---

## App Store Submission

### Apple App Store
- [ ] App name (30 chars), subtitle (30 chars), keywords (100 chars) optimized
- [ ] Screenshots: 6 sizes (6.9", 6.7", 6.5", 5.5" iPhones + iPad)
- [ ] Privacy Nutrition Labels completed
- [ ] Privacy Policy URL valid
- [ ] Age Rating + Export Compliance declared
- [ ] TestFlight build tested

### Google Play
- [ ] Title (30 chars), short description (80 chars), full description (4000 chars) optimized
- [ ] Feature graphic (1024x500px)
- [ ] Content rating + Data safety completed
- [ ] App signing by Google Play configured
- [ ] Internal testing track used before production

---

## GEO (Generative Engine Optimization)

Optimize for AI search engines (ChatGPT, Gemini, Perplexity):
- [ ] Content structured with claims, evidence, citations
- [ ] Pages answer questions directly (featured snippet format)
- [ ] Brand mentioned consistently across authoritative sources
- [ ] Schema markup complete
- [ ] FAQ sections with concise, citable answers

---

## Growth Marketing Patterns

### Referral Program
- [ ] Two-sided incentive (referrer + referee)
- [ ] One-click sharing
- [ ] Attribution tracking
- [ ] Fraud prevention rules

### Product-Led Growth
- [ ] Free tier/trial clearly visible
- [ ] Value before payment
- [ ] Upgrade prompts at value moments (not friction)
- [ ] Usage limits communicated transparently

---

## When to Use This Skill

- `/dr-plan` — planning marketing campaigns or web launches
- `/dr-do` — building ads, landing pages, email sequences, SEO implementation
- `/dr-qa` — verifying tracking, ad compliance, launch readiness
- `/dr-compliance` — legal requirements, ad policy, content checklists
- `/dr-dream` — verifying SEO health of documented web properties

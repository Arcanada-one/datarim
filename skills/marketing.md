---
name: marketing
description: Digital marketing workflows — ad campaigns (Google Ads, Meta Ads), landing page optimization, conversion tracking, A/B testing, email sequences, and growth marketing checklists. Use when planning or executing marketing campaigns.
---

# Marketing — Digital Campaign and Growth Checklists

Rules and patterns for planning, executing, and measuring digital marketing campaigns.

---

## Ad Campaign Structure

### Google Ads Campaign Setup
1. **Campaign hierarchy:** Account → Campaigns → Ad Groups → Ads → Keywords
2. **Campaign types by goal:**
   - Brand: exact match brand keywords, highest priority
   - Competitor: competitor brand keywords, careful ad copy (no trademark use)
   - Generic: non-branded keywords, highest volume
3. **Ad group rules:**
   - 10-20 tightly themed keywords per ad group
   - 3-5 responsive search ad headlines per group
   - Negative keywords at campaign level (cross-group exclusions)

### Meta (Facebook/Instagram) Ads Setup
1. **Campaign structure:** Campaign (objective) → Ad Set (audience + budget) → Ad (creative)
2. **Audience strategy:**
   - Cold: Lookalike audiences based on best customers
   - Warm: Website visitors, email list, engagement audiences
   - Hot: Cart abandoners, past purchasers
3. **Creative rules:**
   - Lead with the benefit in first 3 seconds (video) or headline (static)
   - Test 3-5 creative variations per ad set
   - UGC-style outperforms polished brand content for acquisition

---

## Conversion Tracking Checklist

- [ ] Google Ads conversion tag installed and verified
- [ ] Meta Pixel installed, Conversions API configured (server-side)
- [ ] Key events defined: purchase, lead, signup, add-to-cart
- [ ] Attribution window set correctly (7-day click, 1-day view default)
- [ ] UTM parameters appended to all ad destination URLs
- [ ] Landing page loads < 3 seconds (slow pages waste ad spend)
- [ ] Thank-you/confirmation page fires conversion event
- [ ] Test conversion: complete a real conversion, verify in platform dashboard
- [ ] Cross-device tracking enabled where available

---

## Landing Page Optimization

### Above the Fold
- [ ] Clear headline matching ad promise (message match)
- [ ] Subheadline explaining the value proposition
- [ ] One primary CTA button (contrasting color, action verb)
- [ ] Social proof (logos, testimonials, number of customers)
- [ ] No navigation menu (reduce escape routes)

### Below the Fold
- [ ] Feature/benefit blocks with specifics (numbers, not adjectives)
- [ ] FAQ section addressing objections
- [ ] Secondary CTA repeating the offer
- [ ] Trust signals: security badges, guarantees, privacy note

### Technical
- [ ] Mobile-responsive (60%+ traffic is mobile)
- [ ] PageSpeed score > 80 mobile
- [ ] Forms pre-fill where possible, minimal required fields
- [ ] Form validation with inline error messages

---

## A/B Testing Framework

### What to Test (Priority Order)
1. **Headline** — highest impact, test first
2. **CTA button** — text, color, position
3. **Social proof** — type and placement
4. **Hero image/video** — visual impact
5. **Form length** — fields count and layout
6. **Price presentation** — monthly vs annual, anchoring

### Testing Rules
- One variable at a time per test
- Minimum 200 conversions per variant before declaring winner
- Run for at least 2 full business cycles (typically 2 weeks)
- Document results: variant, metric, lift, confidence, date range

---

## Email Campaign Checklist

### Pre-Send
- [ ] Subject line tested (A/B test with 10-15% of list)
- [ ] Preview text set (not defaulting to first line)
- [ ] From name is recognizable (person name + company or just company)
- [ ] Unsubscribe link visible and working
- [ ] Physical address included (CAN-SPAM)
- [ ] Links tested (all clickable, UTM tagged, no broken URLs)
- [ ] Images have alt text (many clients block images by default)
- [ ] Mobile preview checked (50%+ opens are mobile)
- [ ] Spam score checked (no spam trigger words in subject)

### Automation Sequences
- Welcome sequence: 3-5 emails over 7-14 days
- Onboarding sequence: feature education, time-to-value focus
- Cart abandonment: 3 emails (1h, 24h, 72h)
- Re-engagement: inactive users at 30/60/90 days

---

## Campaign Budget Framework

### Starting Budget Allocation (new campaigns)
- 70% proven channels/audiences
- 20% testing new audiences/creatives
- 10% experimental (new platforms, formats)

### Key Metrics to Track
| Metric | Formula | Healthy Range |
|--------|---------|--------------|
| CPA (Cost Per Acquisition) | Spend / Conversions | < target CPA |
| ROAS (Return on Ad Spend) | Revenue / Spend | > 3x for e-commerce |
| CTR (Click-Through Rate) | Clicks / Impressions | > 2% search, > 0.8% display |
| CVR (Conversion Rate) | Conversions / Clicks | > 2% landing page |
| CAC Payback | CAC / Monthly Revenue | < 12 months |

---

## Growth Marketing Patterns

### Referral Program Checklist
- [ ] Incentive for both referrer and referee (two-sided)
- [ ] One-click sharing mechanism
- [ ] Tracking attribution set up
- [ ] Fraud prevention rules defined
- [ ] Landing page for referred users with welcome message

### Product-Led Growth
- [ ] Free tier or trial clearly visible
- [ ] Value delivered before asking for payment
- [ ] In-app upgrade prompts at value moments (not friction moments)
- [ ] Usage-based limits communicated transparently

---

## When to Use This Skill

- `/dr-plan` — when planning a marketing campaign
- `/dr-do` — when building ad campaigns, landing pages, email sequences
- `/dr-qa` — to verify tracking, ad compliance, landing page quality
- `/dr-compliance` — content checklist: ad policy compliance, legal requirements

# Datarim Use Cases

Datarim is a universal iterative workflow framework. While it originated in software development, its pipeline — requirements, planning, design, execution, quality assurance, reflection — applies to any project that benefits from structured iteration.

Below are concrete examples of how the pipeline maps to different domains.

---

## Software Development

The original and most common use case. The pipeline maps directly to structured development practices.

**Example: Add JWT authentication to an API**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Assess complexity (L3), create task TASK-0012 |
| `/dr-prd` | Define auth requirements: token format, expiration, refresh flow, protected routes |
| `/dr-plan` | Break into phases: middleware, token service, login endpoint, tests |
| `/dr-design` | Consilium panel: Architect + Security evaluate JWT vs session tokens |
| `/dr-do` | TDD implementation: write tests first, then code, one method at a time |
| `/dr-qa` | Verify: PRD alignment, security review, test coverage, OWASP checks |
| `/dr-archive` (Step 0.5) | Note: refresh token rotation was underestimated in planning |
| `/dr-archive` | Archive task, update backlog |

---

## Research & Academic Writing

Research projects follow a natural pipeline: define scope, plan methodology, execute research, review quality.

**Example: Write a literature review chapter on quantum error correction**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Define scope: 15-page review covering 2020-2026 developments (L3) |
| `/dr-prd` | Requirements: target journals, required databases (arXiv, IEEE), citation format, minimum 40 sources |
| `/dr-plan` | Section outline: surface codes, topological codes, recent hardware results. Source allocation per section |
| `/dr-do` | Write each section. Use `/factcheck` to verify technical claims against papers |
| `/dr-qa` | Check: citation completeness, argument coherence, section balance, formatting compliance |
| `/dr-archive` (Step 0.5) | Lesson: starting with a source matrix (topic x paper) saved time vs linear reading |
| `/dr-archive` | Archive with source bibliography for future chapters |

---

## Technical Documentation

API docs, architecture decision records, user guides, runbooks — all benefit from structured creation and review.

**Example: Create API documentation for a payment service**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: 12 endpoints, request/response schemas, error codes, auth flow (L2) |
| `/dr-prd` | Audience: third-party integrators. Requirements: OpenAPI 3.1, code examples in 3 languages, sandbox URLs |
| `/dr-plan` | Priority: auth flow first, then payment lifecycle (create → capture → refund), then webhooks |
| `/dr-do` | Write docs. Cross-reference with actual API code for accuracy |
| `/dr-qa` | Verify: every endpoint documented, examples tested, error codes complete, links valid |
| `/dr-archive` (Step 0.5) | Note: generating examples from actual API responses was faster than writing them manually |

---

## Legal Document Preparation

Legal work is highly structured and benefits from phased review. The pipeline ensures nothing is missed.

**Example: Draft a SaaS terms of service agreement**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Jurisdiction: US/Delaware. Target: B2B SaaS product. Complexity: L3 |
| `/dr-prd` | Requirements: GDPR compliance, data processing addendum, SLA terms, limitation of liability, IP ownership |
| `/dr-plan` | Section structure: definitions, scope, payment, data handling, warranties, termination, dispute resolution |
| `/dr-design` | Key decisions: arbitration vs litigation, liability cap formula, data retention policy |
| `/dr-do` | Draft each section. Cross-reference with jurisdiction requirements |
| `/dr-qa` | Review: internal consistency, defined-term usage, clause numbering, regulatory compliance |
| `/dr-compliance` | Final hardening: check all cross-references, verify against compliance checklist |
| `/dr-archive` (Step 0.5) | Lesson: starting with a clause dependency map prevented circular references |

---

## Project Management

Manage a project backlog, plan iterations, track progress, and run retrospectives.

**Example: Plan and execute a product launch**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Create project backlog with all launch tasks. Complexity: L4 (multi-phase) |
| `/dr-prd` | Launch requirements: marketing materials, landing page, press kit, demo video, partner outreach |
| `/dr-plan` | Work breakdown: 4 phases over 6 weeks. Dependencies mapped. Critical path identified |
| `/dr-do` | Execute tasks from backlog one by one. Each task follows its own mini-pipeline |
| `/dr-qa` | Per-task quality check. Cross-task consistency review (branding, messaging, dates) |
| `/dr-archive` (Step 0.5) | Sprint retrospective: what slipped, what was overscoped, what to adjust for next iteration |
| `/dr-archive` | Archive phase, carry forward incomplete items to next phase backlog |

**Backlog management** is central here:
- `/dr-init` to pick the next task from backlog
- `/dr-status` to see pending items and priorities
- `/dr-archive` to complete tasks and update backlog automatically

---

## Content Creation & Publishing

Blog posts, social media, newsletters — content that needs editorial quality before publication.

**Example: Write and publish a technical blog post**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Topic: "Why we migrated from Redis to Valkey". Target: 2000 words (L2) |
| `/dr-plan` | Outline: motivation, evaluation criteria, migration process, benchmarks, lessons |
| `/dr-do` | Write the draft |
| `/factcheck` | Verify: benchmark numbers, version claims, feature comparisons, date accuracy |
| `/humanize` | Remove AI writing patterns: fix em-dash overuse, replace "leverage" with "use", vary paragraph lengths |
| `/dr-qa` | Editorial review: argument flow, headline accuracy, CTA placement |
| `/dr-archive` (Step 0.5) | Note: benchmarks were the most-shared section — lead with data next time |

The `/factcheck` and `/humanize` commands are standalone — use them at any point in any workflow, not just within the pipeline.

---

## UI/UX Design & Frontend Development

Design systems, component libraries, landing pages, and interactive interfaces — all benefit from structured iteration with visual and performance quality gates.

**Example: Design and build a responsive landing page for a SaaS product**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Define scope: landing page with hero, features, pricing, CTA. Complexity: L3 |
| `/dr-prd` | Requirements: target audience, brand guidelines, responsive breakpoints, accessibility (WCAG 2.1), performance budget (<3s LCP) |
| `/dr-plan` | Component breakdown: hero section, feature grid, pricing cards, testimonial carousel, footer. Mobile-first approach |
| `/dr-design` | Consilium panel: Architect + Developer + Writer evaluate component architecture, CSS strategy (Tailwind vs custom), animation approach |
| `/dr-do` | Build components one by one. HTML/CSS/JS with responsive testing at each step |
| `/dr-qa` | Cross-browser testing, accessibility audit, performance metrics, visual regression check |
| `/dr-archive` (Step 0.5) | Note: component library approach saved 40% time vs building from scratch |

---

## DevOps & Infrastructure

CI/CD pipelines, containerization, deployment automation — structured phases prevent configuration drift and production surprises.

**Example: Set up CI/CD pipeline with Docker and automated deployment**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: Dockerize the app + GitLab CI pipeline + staging/prod deployment. Complexity: L3 |
| `/dr-prd` | Requirements: multi-stage Docker build, CI stages (lint, test, build, deploy), environment separation, secret management, rollback capability |
| `/dr-plan` | Phases: 1) Dockerfile + compose, 2) CI pipeline, 3) staging deploy, 4) prod deploy with approval gate |
| `/dr-do` | Build each phase. Test locally before CI integration |
| `/dr-compliance` | CI/CD impact analysis, security scan (no hardcoded secrets), rollback plan documented, monitoring configured |
| `/dr-archive` (Step 0.5) | Lesson: testing the pipeline in a throwaway environment first prevented 2 production issues |

---

## SRE & Reliability Engineering

Observability, SLOs, incident response — reliability work demands rigorous planning and multi-perspective design review.

**Example: Design observability stack and SLO framework for a microservices platform**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: metrics, logging, tracing, alerting for 8 services. SLO definitions. Complexity: L4 |
| `/dr-prd` | Requirements: SLO targets (99.9% availability, p99 <500ms), alert channels, on-call rotation, incident runbooks |
| `/dr-plan` | Phases: 1) metrics instrumentation, 2) centralized logging, 3) distributed tracing, 4) alerting rules, 5) SLO dashboards |
| `/dr-design` | Consilium panel: SRE + Security + DevOps evaluate Prometheus vs Datadog, ELK vs Loki, Jaeger vs Tempo |
| `/dr-do` | Implement phase by phase. Each service instrumented independently |
| `/dr-qa` | Verify: all services emit metrics, logs searchable, traces connected across services, alerts fire correctly |
| `/dr-compliance` | Infrastructure checklist: monitoring configured, alert thresholds set, rollback plan, security (least-privilege) |
| `/dr-archive` (Step 0.5) | Lesson: starting with SLO definitions before instrumentation kept the team focused on what matters |

---

## SEO & Analytics Setup

Search engine optimization, analytics configuration, and advertising campaigns require methodical setup with verification at each step.

**Example: SEO audit and optimization for a SaaS website**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: technical SEO audit + on-page optimization + analytics setup. Complexity: L2 |
| `/dr-prd` | Requirements: target keywords, competitor analysis, Google Search Console access, GA4 property, Core Web Vitals targets |
| `/dr-plan` | Phases: 1) technical audit (crawlability, indexing, sitemap), 2) on-page SEO (meta, headings, structured data), 3) GA4 + GSC setup, 4) conversion tracking |
| `/dr-do` | Execute phase by phase. Validate each change with PageSpeed Insights and Search Console |
| `/dr-qa` | Verify: sitemap submitted, robots.txt correct, structured data validates, GA4 events firing, no broken canonical tags |
| `/dr-archive` (Step 0.5) | Note: fixing Core Web Vitals before content optimization improved crawl budget allocation |

---

## Ad Campaigns & Growth Marketing

Google Ads, Facebook Ads, and paid acquisition campaigns benefit from structured planning and compliance checks.

**Example: Launch Google Ads campaign for a B2B product**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: campaign structure, ad groups, landing pages, conversion tracking. Complexity: L2 |
| `/dr-prd` | Requirements: budget, target CPA, audience segments, keyword lists, ad copy variations, landing page URLs |
| `/dr-plan` | Structure: 3 campaigns (brand, competitor, generic) × 4 ad groups each. A/B test plan for headlines and descriptions |
| `/dr-do` | Build campaigns, write ad copy, configure audiences, set up conversion tracking pixels |
| `/dr-qa` | Verify: tracking pixels fire correctly, budget caps set, negative keywords added, landing pages load <3s, ad policy compliance |
| `/dr-compliance` | Content checklist: ad copy meets platform policies, no prohibited claims, disclaimers present, landing page matches ad promise |
| `/dr-archive` (Step 0.5) | Lesson: starting with conversion tracking verification before launching saved debugging time later |

---

## App Store & Marketplace Publishing

Preparing apps and products for Google Play, App Store, or other marketplaces — asset preparation, metadata, compliance, and submission.

**Example: Prepare and submit a macOS app to the App Store**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: App Store listing, screenshots, description, privacy policy, review preparation. Complexity: L3 |
| `/dr-prd` | Requirements: app metadata (all locales), 6 screenshot sizes, app preview video, privacy nutrition labels, EULA, support URL, category selection |
| `/dr-plan` | Phases: 1) metadata and descriptions (EN, RU), 2) screenshot generation, 3) privacy policy, 4) App Store Connect setup, 5) TestFlight → Review submission |
| `/dr-write` | Write app description, release notes, keyword list. Multi-language versions |
| `/dr-edit` | Fact-check feature claims, humanize descriptions, verify keyword density |
| `/dr-compliance` | Legal checklist: privacy policy covers all data usage, EULA terms complete, age rating accurate, export compliance declared |
| `/dr-qa` | Verify: all assets uploaded, metadata complete for all locales, screenshots match current UI, links valid |
| `/dr-archive` (Step 0.5) | Note: preparing the privacy nutrition labels early avoided a rejection cycle |

---

## Website Launch Preparation

Pre-launch checklist for websites — from domain configuration to analytics to social previews.

**Example: Pre-launch checklist for a product landing page**

| Stage | What happens |
|-------|-------------|
| `/dr-init` | Scope: final pre-launch verification before going live. Complexity: L2 |
| `/dr-plan` | Checklist categories: DNS/SSL, performance, SEO, analytics, social previews, legal pages, accessibility |
| `/dr-do` | Execute each category: verify SSL, test redirects, compress images, add OG tags, set up 404 page |
| `/dr-qa` | Cross-browser test, mobile test, PageSpeed audit, broken link scan, form submission test, social preview cards |
| `/dr-compliance` | Documentation checklist: cookie consent present, privacy policy linked, terms of service linked, GDPR compliance (if EU), contact info visible |
| `/dr-archive` (Step 0.5) | Note: social preview card testing caught a missing OG image that would have looked unprofessional on first shares |

---

## Key Takeaway

The pipeline stages map to universal project phases:

| Pipeline Stage | Universal Meaning |
|---------------|-------------------|
| **init** | Define what you're doing and how big it is |
| **prd** | Clarify requirements and constraints |
| **plan** | Break work into manageable steps |
| **design** | Make key decisions before committing |
| **do** | Execute the actual work |
| **qa** | Verify the work meets requirements |
| **compliance** | Final hardening and cross-checks |
| **archive → Step 0.5** | Learn from the experience (reflection runs inside archive) |
| **archive** | Store for future reference |

Any project that benefits from this structure can use Datarim. The complexity routing ensures you don't over-process simple tasks or under-process complex ones.

# Standards Mapping — Datarim Security Baseline (S1–S9)

> **Source skill:** [`skills/security-baseline.md`](../skills/security-baseline.md)
> **Authoritative versions:**
> - OWASP ASVS v5.0.0 (2025)
> - SOC 2 Trust Services Criteria 2017 (revised 2022)
> - ISO/IEC 27001:2022 Annex A
> - CIS Controls v8 (2021)
>
> **Status:** informative, not certificative. A Datarim-managed project that satisfies S1–S9 has measurable coverage of these frameworks, but a formal audit is the only certificate of compliance. The mapping is maintained by the framework maintainer; consumer projects layer their own application-level baseline on top.

---

## Mapping table

| S* cluster                           | OWASP ASVS v5                        | SOC 2 CC                | ISO/IEC 27001:2022 Annex A             | CIS Controls v8           |
|--------------------------------------|--------------------------------------|-------------------------|----------------------------------------|---------------------------|
| **S1** — Shell scripts & embedded    | V14.4, V12.3                         | CC6.1, CC8.1            | A.8.16, A.8.27, A.8.31                 | 2.1, 4.1, 16.1            |
| **S2** — Python & python-fenced      | V5.1, V8.3                           | CC6.1, CC6.7            | A.8.25, A.8.27                         | 16.1, 16.5                |
| **S3** — Credentials & secrets       | V2.10, V8.1                          | CC6.1, CC6.6, CC6.7     | A.5.15, A.5.17, A.8.5                  | 5.1, 6.1, 6.5             |
| **S4** — Supply chain                | V14.2, V14.6                         | CC8.1, CC9.2            | A.8.30, A.5.20, A.5.21                 | 16.4, 16.10               |
| **S5** — Markdown docs as code       | V14.4                                | CC8.1                   | A.5.10                                 | 16.1                      |
| **S6** — Repo hygiene                | V14.6                                | CC8.1, CC9.2            | A.5.30, A.5.31, A.5.34                 | 16.1, 16.4                |
| **S7** — CI verification gate        | V14.2, V14.4                         | CC7.1, CC7.2            | A.8.16, A.8.32                         | 16.1, 16.11               |
| **S8** — Standards mapping (meta)    | (this document)                      | CC1.4, CC2.2            | A.5.36                                 | (meta)                    |
| **S9** — Drift, evolution, response  | V1.14.6                              | CC2.3, CC7.3, CC7.4     | A.5.24, A.5.25, A.5.26, A.5.27         | 17.1, 17.4                |

---

## Per-framework notes

### OWASP ASVS v5

ASVS organises requirements by chapter (V1 Architecture, V2 Authentication, V3 Session, …, V14 Configuration). Datarim's S1–S9 deliberately concentrate on the **infrastructure-and-supply-chain layer** that ships shared developer tooling — not the application surface. Concretely:

- **High coverage:** V14 (Configuration), V8 (Data Protection at rest), V2 (selected authentication-as-supply-chain controls).
- **Partial coverage:** V5 (Validation, Sanitization & Encoding) — applies only to the embedded shell/Python blocks Datarim ships, not to consumer application logic.
- **Out of scope (consumer responsibility):** V3 (Session), V4 (Access Control), V7 (Cryptography at the application boundary), V9 (Communications), V11 (Business Logic), V13 (API/Web Service).

A Datarim-managed project that wants ASVS v5 Level 2 must add an application-level baseline on top — Datarim covers the developer-tool floor, not the ceiling.

### SOC 2 (Trust Services Criteria 2017, rev. 2022)

Datarim baseline aligns with the **Common Criteria** (CC1–CC9), specifically:

<!-- security:rule-statement -->
- **CC6 — Logical & Physical Access:** S3 (credentials), S2 (atomic mode-0o600 writes), S1 (no `StrictHostKeyChecking=no`).
<!-- /security:rule-statement -->
- **CC7 — System Operations:** S7 (CI verification gate), S9 (incident response).
- **CC8 — Change Management:** S4 (supply chain), S5 (docs-as-code), S6 (repo hygiene).
- **CC9 — Risk Mitigation:** S4 (signed releases, SBOM), S6 (CODEOWNERS, branch protection).

Datarim is a **dev-tool baseline**, not an applicative SOC 2 control set. Consumer projects pursuing SOC 2 Type II audits run their own evidence collection — Datarim provides the technical scaffolding, not the operational evidence trail.

### ISO/IEC 27001:2022 Annex A

The 2022 revision restructured Annex A into 4 themes (Organisational A.5, People A.6, Physical A.7, Technological A.8). Datarim S1–S9 anchor in **A.5 (Organisational)** and **A.8 (Technological)**:

- **A.5 themes:** A.5.10 (information classification — S5), A.5.15 (access control — S3), A.5.20–5.21 (supplier — S4), A.5.24–5.27 (incident response — S9), A.5.30–5.36 (continuity / compliance — S6, S8).
- **A.8 themes:** A.8.5 (secure authentication — S3), A.8.16 (monitoring — S1, S7), A.8.25 (secure development life cycle — S2), A.8.27 (secure system architecture — S1, S2), A.8.30 (outsourced development — S4), A.8.31–8.32 (separation of dev/prod / change management — S1, S7).

Datarim provides controls; the **Information Security Management System (ISMS)** itself is a project-level concern that lives outside the framework.

### CIS Controls v8

CIS v8 replaces CSC v7's 20 controls with 18 controls organised by Implementation Group (IG1, IG2, IG3). Datarim S1–S9 cover **IG1 + selected IG2** controls relevant to dev-tooling supply chain:

- **CIS 2 — Inventory of Software Assets:** S1, S6 (LICENSE, SECURITY.md as inventory anchors).
- **CIS 4 — Secure Configuration:** S1.
- **CIS 5 — Account Management:** S3.
- **CIS 6 — Access Control Management:** S3.
- **CIS 16 — Application Software Security:** S1, S2, S4, S5, S6, S7 (the bulk of Datarim's surface).
- **CIS 17 — Incident Response Management:** S9.

**IG3 (advanced threat modelling, red-team exercises):** outside framework scope. Project consumers that need IG3 build their own threat-model artefacts; Datarim provides the developer-tooling floor those exercises rest on.

---

## Coverage summary

Out of 9 S* clusters:

- **9/9** map to ≥1 ASVS v5 chapter
- **9/9** map to ≥1 SOC 2 Common Criterion
- **9/9** map to ≥1 ISO/IEC 27001:2022 Annex A control
- **7/9** map to ≥1 CIS Controls v8 control (S8 and S2 are meta / partial)

Aggregate: every S* cluster has a non-empty mapping to at least three of the four frameworks. The two CIS gaps reflect framework intent — CIS v8 is operations-centric, while S8 (this mapping) is a meta-cluster about traceability and S2 (Python rules) is finer-grained than CIS's IG1/IG2 application-software family.

---

## Limitations (transparent)

Datarim S1–S9 baseline does **not** address:

- **Application-level OWASP Top 10** (web/API/mobile injection, broken access control, etc.) — project-specific, lives in the consumer codebase.
- **NIST SP 800-53** (federal control catalogue) — too broad for a developer-tooling framework; consumer projects in regulated environments map their own implementation.
- **PCI DSS** (payment industry) — payment-flow specific.
- **HIPAA / GDPR** (privacy regimes) — data-handling specific to the application's data classification.

Datarim baseline = **developer-tool security floor**. Consumer projects layer their own application-level baseline (OWASP Top 10, regulatory compliance) on top. The mapping above tells you which control families the floor covers; the gap analysis between the floor and the project's certification target is the project's own work.

---

## Maintenance

| Trigger                                              | Action                                                                                              |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| Major framework version bump (e.g. ASVS v5 → v6)     | Review affected rows, update version line in header, log review in `documentation/archive/security/triage-YYYY-MM.md` |
| Quarterly cadence (≥1 per 90 days)                   | Sweep all rows, confirm rule-cluster→control alignment, log the review                              |
| New audit finding with no current S* anchor          | Either extend an existing S* cluster or document the gap explicitly in this file's Limitations section |
| Standards body retires a referenced control          | Annotate the row inline with a forward pointer to the replacement control                            |

**Owner:** Datarim framework maintainer.

**Audit log location:** `documentation/archive/security/triage-YYYY-MM.md`.

**Source artefacts feeding this document:**

- `skills/security-baseline.md` § S1–S9 (canonical rule reference)
- `documentation/archive/security/findings-2026-04-28.md` (corporate audit baseline)
- `~/arcanada/datarim/insights/INSIGHTS-security-baseline-oss-cli-2026.md` (research baseline)
- `tests/security/baseline.json` (machine-readable suppressions registry)

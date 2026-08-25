# Security & Compliance — DecisionMesh

**DECIMESHI (OPC) PRIVATE LIMITED**
CIN: U62013TS2026OPC216945
Last updated: June 2026

---

## Security Statement

DecisionMesh has implemented SOC 2 technical controls including:

- ✅ **Multi-Factor Authentication (MFA)** — enforced for all users via Zitadel
- ✅ **Vulnerability Scanning** — Trivy scans every Docker image on every CI build; results published to GitHub Security tab
- ✅ **Penetration Testing** — OWASP ZAP baseline scan: 0 failures, 66 checks passed (June 2026)
- ✅ **Encrypted Secrets Management** — all API keys and credentials stored in OpenBao (HashiCorp Vault compatible); never in code or config files
- ✅ **Tamper-Evident Audit Logging** — every AI governance decision is logged in an append-only audit trail (ORM-enforced no-update policy); a separate SHA-256 hash-chained governance ledger provides cryptographic tamper evidence for intent replay
- ✅ **GDPR Right to Erasure** — automated erasure API compliant with GDPR Article 17; 30-day SLA
- ✅ **Data Retention Policy** — automated nightly enforcement; 7-year retention for financial/audit records
- ✅ **Backup Verification** — monthly automated backup restore and row-count verification
- ✅ **Encryption in Transit** — TLS 1.2+ enforced by Caddy with automatic Let's Encrypt certificates; HSTS enabled
- ✅ **Encryption at Rest** — AES-256 for all stored data
- ✅ **Non-root Containers** — all Docker containers run as non-root user
- ✅ **Role-Based Access Control** — ADMIN, ANALYST, VIEWER roles enforced via Zitadel OAuth2/OIDC
- ✅ **Uptime Monitoring** — UptimeRobot monitors every 5 minutes; email + Discord alerts
- ✅ **Metrics & Observability** — Prometheus + Grafana dashboard; real-time visibility into API health, JVM, and error rates

---

## Compliance Frameworks

| Framework | Status |
|---|---|
| SOC 2 Type I | Controls implemented — formal audit pending |
| SOC 2 Type II | Pursuing — observation period started June 2026 |
| GDPR | Compliant — DPA available on request |
| EU AI Act | Compliant by design — tamper-evident audit trail, intent classification, policy enforcement |
| DPDPA 2023 | Compliant — data residency in EU (Hetzner, Germany) |

---

## Policy Documents

| Document | ID |
|---|---|
| Information Security Policy | DM-POL-001 |
| Access Control Policy | DM-POL-002 |
| Data Retention Policy | DM-POL-003 |
| Incident Response Policy | DM-POL-004 |
| Change Management Policy | DM-POL-005 |
| Vendor Management Policy | DM-POL-006 |
| Risk Register | DM-RISK-001 |

Available to enterprise customers under NDA. Contact: thiru@decimeshi.com

---

## Infrastructure

- **Hosting:** Hetzner Cloud, Nuremberg, Germany (EU jurisdiction)
- **Frontend:** Cloudflare Pages (global CDN)
- **Identity:** Zitadel (EU cloud instance)
- **Payments:** Stripe (PCI DSS Level 1) + Razorpay (PCI DSS)
- **Secrets:** OpenBao (Vault-compatible, self-hosted)

---

## Penetration Test Results (June 2026)

Tool: OWASP ZAP Baseline Scan
Target: https://api.decimeshi.com

```
FAIL-NEW:  0
WARN-NEW:  1  (Non-Storable Content — intentional, API security best practice)
PASS:      66
```

---

## Contact

Security issues: support@decimeshi.com
Enterprise security reviews: thiru@decimeshi.com
Mob: +91 9100493877

*DecisionMesh is pursuing formal SOC 2 Type II certification. Full audit report available to enterprise customers upon request.*

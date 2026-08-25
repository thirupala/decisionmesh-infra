# Deployment Topology — DecisionMesh

**DECIMESHI (OPC) PRIVATE LIMITED**
Last updated: 2026-08-25

---

## Purpose

For each deployment mode DecisionMesh offers or is asked about, this
document states plainly what crosses the customer's network perimeter to a
third party or to a DecisionMesh-operated service — not what could
theoretically be configured, what is actually wired up in the codebase
today. Where a mode has a real gap, it's stated as a gap, not glossed over.

---

## Mode 1 — Shared SaaS (current production deployment)

The only mode actually running today. Single deployment, multi-tenant,
operated by DecisionMesh.

**Hosting**: Hetzner Cloud, Nuremberg, Germany (EU jurisdiction) — backend,
Postgres, Redis, Kafka, OpenBao. Frontend on Cloudflare Pages (global CDN).

**What crosses the perimeter, always:**
- **Identity — Zitadel Cloud.** Every login and role check goes to
  `https://decisionmesh-1pgrry.eu1.zitadel.cloud`, a DecisionMesh-owned
  tenant on Zitadel's hosted SaaS. Not self-hosted.
- **LLM calls — whichever provider the request is routed to.** Every
  hosted-adapter call leaves Hetzner for the provider's public API:
  OpenAI (`api.openai.com`), Anthropic (`api.anthropic.com`), Google Gemini
  (`generativelanguage.googleapis.com`), DeepSeek (`api.deepseek.com`),
  Qwen (`dashscope-intl.aliyuncs.com`). This is unavoidable for any of
  these providers by definition — the whole point of routing to them is
  that they run the model.
- **Payments — Stripe / Razorpay.** Checkout and webhook traffic only; not
  on the intent/execution/governance path.

**What stays internal:** Postgres, Redis, Kafka, OpenBao (secrets) all run
on Hetzner infrastructure, not third-party SaaS.

---

## Mode 2 — Dedicated single-tenant

A customer-isolated deployment (own database, own adapter pool, own kill
switches — no cross-tenant blast radius) — still DecisionMesh-operated or
deployed into the customer's own cloud account. The codebase is
multi-tenant-capable throughout, so this mode is mechanically the same
software as Mode 1, scoped to one tenant.

**Same perimeter crossings as Mode 1, with one exception:**
- Identity still crosses to Zitadel Cloud — no self-hosted IdP path exists
  today (see Mode 3).
- LLM calls still cross to whichever provider(s) the customer enables —
  same as Mode 1, avoidable only by restricting the tenant to
  Ollama-routed (self-hosted/local) models exclusively.
- Payments/billing can be fully disabled for this mode if the customer is
  on a direct contract rather than the self-serve billing flow — it has no
  code-level coupling to intent execution or governance decisions.

This mode removes cross-tenant risk and gives the customer their own
infrastructure boundary; it does not remove the Zitadel Cloud or
hosted-LLM crossings.

---

## Mode 3 — On-premises / air-gapped

**Not achievable with the current codebase.** Stated directly because this
is the mode most likely to be oversold, and overselling it is worse than
saying so plainly.

**Hard blocker — identity, and it's deeper than a config value.** Every
environment profile (`application-dev.properties`,
`application-staging.properties`, `application-prod.properties`) points
OIDC at the same Zitadel Cloud tenant — but `quarkus.oidc.auth-server-url`/
`token.issuer`/`client-id` are standard Quarkus OIDC properties, not
custom code; nothing hardcodes them at the Java level, and a new
`application-{profile}.properties` pointing at a different OIDC provider
is mechanically straightforward. Two things are NOT that simple:

1. `quarkus.oidc.roles.role-claim-path=urn:zitadel:iam:org:project:roles`
   is a Zitadel-specific custom-claim convention. A different provider
   (self-hosted Zitadel, Keycloak, Okta, Auth0) would need its own claim
   path, so this can't just be copied to a new profile unchanged.
2. ~~`OnboardingService` calls Zitadel's own management API directly...~~
   **Fixed 2026-08-25.** `OnboardingService` still writes tenant/account
   metadata to Zitadel (`writeKey()`, `PUT .../management/v1/users/{userId}/metadata/{key}`)
   and reads a profile back (`fetchZitadelProfile()`), but neither is
   load-bearing for tenant resolution any more — both were already
   best-effort/non-fatal (failures logged, swallowed). `TenantContextFilter`
   now resolves `tenantId` from the local `users` table (by the JWT's
   `sub` claim) *first*, falling back to a JWT `tenantId` claim only when
   no DB row exists yet (e.g. a brand-new user whose row hasn't committed).
   A JWT that never carries a custom `tenantId` claim at all — the case
   for any OIDC provider with no Zitadel-Action equivalent injecting one —
   now resolves correctly through the DB path alone. See
   `TenantContextFilter.resolveTenantId()` in `decisionmesh-security`.

Zitadel itself is self-hostable in general — nothing here is wired to use
a self-hosted instance today. Making this mode real now requires only
(a) OIDC config as a genuine per-deployment setting including the claim
path, and (b) a self-hosted Zitadel (or equivalent OIDC provider) the
customer operates — the tenant-resolution replacement point (2) used to
require is done.

**Solvable today — data plane.** Postgres, Redis, Kafka, and OpenBao are
already bundled and self-hostable — `decisionmesh-infra/backend/docker-compose.yml`
runs all four with no external dependency, so this part of an air-gapped
deployment is not a gap.

**Solvable today, with a constraint — LLM calls.** `OllamaAdapter` exists
specifically for this: point it at a model running on the customer's own
infrastructure (on-prem GPU box, VPC-internal server, edge device), no
outbound call, no external auth. For a genuinely air-gapped deployment,
Ollama (or another self-hosted model server) must be the *only* enabled
adapter — enabling OpenAI/Anthropic/Gemini/DeepSeek/Qwen alongside it
reopens the exact crossing air-gapping is meant to close. This is a
configuration discipline the deployment must enforce, not a code gap.

**Minor coupling to flag.** `decisionmesh-governance` has a compile-time
dependency on `decisionmesh-billing` (subscription-tier limits feed policy
decisions via `SubscriptionPolicyService`). This is a data-model coupling,
not an outbound network call — no Stripe/Razorpay traffic occurs on the
governance or execution path — but it means the billing module isn't
cleanly excisable from a from-scratch air-gapped build without stubbing
those entity types.

**Bottom line:** an honest on-prem/air-gapped offering today would need
(1) OIDC config genuinely made per-deployment (issuer, client-id, and the
Zitadel-specific roles claim path) and (2) an enforced Ollama-only adapter
policy for that deployment — both config/deployment-discipline work, not
code. The tenant-resolution mechanism no longer depends on Zitadel's
management API (see point 2 above, fixed 2026-08-25). What remains is
still real: neither (1) nor (2) is actually configured/enforced for any
deployment today, and a genuine alternate-OIDC-provider deployment has
never been tested end-to-end against this codebase — so the honest answer
to "can DecisionMesh run fully air-gapped today" is still no, but the
concrete path to yes is now two deployment-configuration items, not an
architecture change.

---

## Summary table

| Crosses the perimeter | Shared SaaS | Dedicated single-tenant | On-prem / air-gapped |
|---|---|---|---|
| Zitadel Cloud (identity) | Yes | Yes | **Config only — OIDC issuer/claim-path are portable properties; tenant resolution no longer depends on Zitadel's management API. Needs per-deployment config and a real alternate-OIDC test, not an architecture change.** |
| Hosted LLM provider APIs | Yes (per routed request) | Yes, unless Ollama-only | Must be Ollama-only to avoid |
| Stripe / Razorpay | Yes (billing only) | Optional — disable for direct contracts | Should be disabled |
| Postgres / Redis / Kafka / OpenBao | DecisionMesh-hosted (Hetzner) | Customer or DecisionMesh infra | Self-hosted — already solved |

---

## Contact

Architecture questions: thiru@decimeshi.com

# DecisionMesh — Environment Reference

## Overview

| Environment | Branch  | Frontend URL                    | Backend API URL                      |
|-------------|---------|----------------------------------|--------------------------------------|
| Local       | dev     | http://localhost:3000            | http://localhost:8080                |
| Staging     | staging | https://app-staging.decimeshi.com | https://api-staging.decimeshi.com   |
| Production  | main    | https://decimeshi.com            | https://api.decimeshi.com            |

---

## Infrastructure

### Hetzner Server
- **IP:** 178.105.87.59
- **User:** decisionmesh
- **Infra repo path:** /opt/decisionmesh/infra

### Cloudflare
- **DNS Zone:** decimeshi.com
- **Frontend hosting:** Cloudflare Pages (Workers & Pages)

---

## DNS Records

| Type  | Name          | Value                        | Proxy  | Purpose              |
|-------|---------------|------------------------------|--------|----------------------|
| A     | api           | 178.105.87.59                | Grey   | Prod API             |
| A     | api-staging   | 178.105.87.59                | Grey   | Staging API          |
| CNAME | decimeshi.com | decisionmesh-ui.pages.dev    | Orange | Prod frontend        |
| CNAME | www           | decisionmesh-ui.pages.dev    | Orange | Prod frontend (www)  |
| CNAME | app-staging   | decisionmesh-ui-staging...   | Orange | Staging frontend     |

---

## Cloudflare Pages Projects

### Production: `decisionmesh-ui`
- **Git repo:** thirupala/decisionmesh-ui
- **Production branch:** main
- **Build command:** `npm run build`
- **Build output:** dist
- **Custom domain:** decimeshi.com
- **Env file used:** `.env.production` (on main branch)

### Staging: `decisionmesh-ui-staging`
- **Git repo:** thirupala/decisionmesh-ui
- **Production branch:** staging
- **Build command:** `npm run build` (staging branch uses `vite build --mode staging`)
- **Build output:** dist
- **Custom domain:** app-staging.decimeshi.com
- **Env file used:** `.env.staging` (on staging branch)

---

## Frontend Environment Files

### Local — `.env.local` (gitignored)
```
VITE_API_BASE_URL=http://localhost:8080/api
VITE_ZITADEL_AUTHORITY=https://decisionmesh-1pgrry.eu1.zitadel.cloud
VITE_ZITADEL_CLIENT_ID=368134611768783581
VITE_ZITADEL_REDIRECT_URI=http://localhost:3000/auth/callback
VITE_ZITADEL_POST_LOGOUT_URI=http://localhost:3000
VITE_ZITADEL_SILENT_REDIRECT_URI=http://localhost:3000/auth/silent-callback
```

### Staging — `.env.staging` (staging branch only)
```
VITE_API_BASE_URL=https://api-staging.decimeshi.com/api
VITE_APP_ENV=staging
VITE_ZITADEL_AUTHORITY=https://decisionmesh-1pgrry.eu1.zitadel.cloud
VITE_ZITADEL_CLIENT_ID=368134611768783581
VITE_ZITADEL_REDIRECT_URI=https://app-staging.decimeshi.com/auth/callback
VITE_ZITADEL_POST_LOGOUT_URI=https://app-staging.decimeshi.com
VITE_ZITADEL_SILENT_REDIRECT_URI=https://app-staging.decimeshi.com/auth/silent-callback
```

### Production — `.env.production` (main branch only)
```
VITE_API_BASE_URL=https://api.decimeshi.com/api
VITE_APP_ENV=production
VITE_ZITADEL_AUTHORITY=https://decisionmesh-1pgrry.eu1.zitadel.cloud
VITE_ZITADEL_CLIENT_ID=368134611768783581
VITE_ZITADEL_REDIRECT_URI=https://decimeshi.com/auth/callback
VITE_ZITADEL_POST_LOGOUT_URI=https://decimeshi.com
VITE_ZITADEL_SILENT_REDIRECT_URI=https://decimeshi.com/auth/silent-callback
```

---

## Backend Containers (Hetzner)

### Production
| Container                  | Image                                   | Port (internal) |
|----------------------------|-----------------------------------------|-----------------|
| dm-api                     | ghcr.io/thirupala/decisionmesh:latest   | 8080            |
| decisionmesh-postgres-1    | pgvector/pgvector:pg16                  | 5432            |
| decisionmesh-redis-1       | redis:7-alpine                          | 6379            |
| decisionmesh-kafka-1       | apache/kafka:3.7.0                      | 9092            |
| decisionmesh-openbao-1     | openbao/openbao:2 (server mode)         | 8200            |
| decisionmesh-ollama-1      | ollama/ollama:latest                    | 11434           |
| dm-caddy                   | caddy:2-alpine                          | 80, 443         |

### Staging
| Container                          | Image                                   | Port (internal) |
|------------------------------------|-----------------------------------------|-----------------|
| dm-api-staging                     | ghcr.io/thirupala/decisionmesh:staging  | 8081            |
| decisionmesh-staging-postgres-1    | pgvector/pgvector:pg16                  | 5432            |
| decisionmesh-staging-redis-1       | redis:7-alpine                          | 6379            |
| decisionmesh-staging-kafka-1       | apache/kafka:3.7.0                      | 9092            |
| decisionmesh-staging-openbao-1     | hashicorp/vault:1.15 (dev mode)         | 8200            |
| decisionmesh-staging-ollama-1      | ollama/ollama:latest                    | 11434           |

---

## OpenBao (Secrets)

### Staging — Dev Mode (hashicorp/vault:1.15)
- **Token:** root
- **Auto-unseals:** Yes (dev mode)
- **Data persists:** No (lost on restart)
- **Address:** http://openbao:8200 (internal)
- **Secrets path:** secret/decisionmesh/

### Production — Server Mode (openbao/openbao:2)
- **Token:** stored in /opt/decisionmesh/infra/.env.prod
- **Auto-unseals:** No — run `scripts/unseal-prod.sh` after restart
- **Data persists:** Yes (file storage)
- **Init keys:** /opt/decisionmesh/secrets/openbao-init.json
- **Address:** http://openbao:8200 (internal)
- **Secrets path:** secret/decisionmesh/

### Secrets stored in OpenBao (both environments)
| Path                          | Keys                                              |
|-------------------------------|---------------------------------------------------|
| secret/decisionmesh/db        | password, url, reactive_url, username             |
| secret/decisionmesh/llm       | llm.openai.api-key, llm.anthropic.api-key, llm.gemini.api-key, llm.deepseek.api-key |
| secret/decisionmesh/stripe    | stripe.secret.key                                 |
| secret/decisionmesh/razorpay  | razorpay.key.id, razorpay.key.secret, razorpay.webhook.secret |
| secret/decisionmesh/email     | quarkus.mailer.password, username                 |
| secret/decisionmesh/auth      | vault_token, zitadel_service_account_token        |
| secret/decisionmesh/redis     | quarkus.redis.password                            |
| secret/decisionmesh/zitadel   | zitadel.url, zitadel.organization-id, zitadel.service-account-token |

---

## Quarkus Application Profiles

### Dev (`application-dev.properties`)
- OIDC: Zitadel cloud (tls.verification=none)
- OpenBao: http://host.docker.internal:8200, token=dev-root-token
- DB: localhost:5432
- Redis: localhost:6379
- Kafka: localhost:9092
- CORS: http://localhost:3000

### Staging (`application-staging.properties`)
- OIDC: Zitadel cloud (tls.verification=certificate-validation)
- OpenBao: http://openbao:8200
- DB: postgres:5432
- Redis: redis:6379
- Kafka: kafka:9092
- CORS: https://app-staging.decimeshi.com
- HTTP port: 8081

### Production (`application-prod.properties`)
- OIDC: Zitadel cloud (tls.verification=certificate-validation)
- OpenBao: http://openbao:8200
- DB: postgres:5432
- Redis: redis:6379
- Kafka: kafka:9092
- CORS: https://decimeshi.com
- HTTP port: 8080

---

## CI/CD Pipeline

### App Repo (decisionmesh)
**Workflow:** `.github/workflows/ci.yml`

| Branch push | Image tag built    | Deploys to         |
|-------------|--------------------|--------------------|
| dev         | :dev               | Nothing            |
| staging     | :staging           | Hetzner staging    |
| main        | :latest            | Hetzner prod (approval required) |

### Infra Repo (decisionmesh-infra)
**Workflows:** `deploy-staging.yml`, `deploy-prod.yml`
- Triggered via `repository_dispatch` from app repo
- SSHs into Hetzner and recreates API container

### GitHub Secrets

**In decisionmesh-infra repo:**
| Secret           | Value                        |
|------------------|------------------------------|
| HETZNER_HOST     | 178.105.87.59                |
| HETZNER_USER     | decisionmesh                 |
| HETZNER_SSH_KEY  | SSH private key (ed25519)    |

**In decisionmesh app repo:**
| Secret                  | Value                                       |
|-------------------------|---------------------------------------------|
| INFRA_DISPATCH_TOKEN    | PAT with repo scope on decisionmesh-infra   |

---

## Zitadel Configuration

- **Instance:** https://decisionmesh-1pgrry.eu1.zitadel.cloud
- **Organization ID:** 368134337511633629
- **Client ID:** 368134611768783581
- **Type:** Single Zitadel instance shared across all environments

### Redirect URIs registered in Zitadel
```
http://localhost:3000/auth/callback
https://decimeshi.com/auth/callback
https://app-staging.decimeshi.com/auth/callback
https://app-staging.decimeshi.com
```

### Post Logout URIs
```
http://localhost:3000
https://decimeshi.com
https://app-staging.decimeshi.com
```

---

## Useful Commands

### Check status
```bash
# All containers
docker ps | grep -E 'dm-api|caddy|openbao|postgres|redis|kafka'

# Health checks
curl -s https://api.decimeshi.com/health | python3 -m json.tool | grep status
curl -s https://api-staging.decimeshi.com/health | python3 -m json.tool | grep status

# Logs
docker logs dm-api --tail 20
docker logs dm-api-staging --tail 20
```

### Start/restart services
```bash
cd /opt/decisionmesh/infra

# Start staging
bash scripts/start-staging.sh

# Start prod (unseals OpenBao first)
bash scripts/start-prod.sh

# Start gateway
docker compose -f backend/docker-compose.gateway.yml up -d

# Unseal prod OpenBao after restart
bash scripts/unseal-prod.sh
```

### Import secrets
```bash
cd /opt/decisionmesh/infra
bash scripts/import-bao-secrets.sh --env staging
bash scripts/import-bao-secrets.sh --env prod
```

### Deploy manually
```bash
# Staging
docker pull ghcr.io/thirupala/decisionmesh:staging
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging \
  up -d --no-deps --force-recreate api

# Prod
docker pull ghcr.io/thirupala/decisionmesh:latest
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml \
  --env-file .env.prod up -d --no-deps --force-recreate api
```

### After server reboot
```bash
cd /opt/decisionmesh/infra

# Staging (OpenBao auto-unseals in dev mode)
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging up -d

# Prod (needs manual unseal)
bash scripts/unseal-prod.sh
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml \
  --env-file .env.prod up -d

# Gateway
docker compose -f backend/docker-compose.gateway.yml up -d
```

# decisionmesh-infra

Infrastructure as code for DecisionMesh. Completely separate from application repos.

## Repo layout

```
decisionmesh-infra/
├── backend/
│   ├── docker-compose.yml           Base infrastructure
│   ├── docker-compose.local.yml     Local dev overlay (exposes ports)
│   ├── docker-compose.staging.yml   Standalone staging (OpenBao dev mode)
│   ├── docker-compose.prod.yml      Production overlay (OpenBao server mode)
│   ├── docker-compose.gateway.yml   Shared Caddy (prod + staging)
│   ├── Caddyfile                    Routes: api.decimeshi.com + staging.decimeshi.com
│   ├── application-staging.properties   → copy to app repo src/main/resources/
│   ├── application-prod.properties      → copy to app repo src/main/resources/
│   ├── .env.local.example
│   ├── .env.staging.example
│   └── .env.prod.example
├── config/
│   └── openbao.hcl                  Prod OpenBao server config
├── frontend/
│   ├── .env.development             Local Vite proxy → localhost:8080
│   ├── .env.staging                 Cloudflare Pages staging
│   ├── .env.production              Cloudflare Pages prod
│   └── vite.config.js
├── scripts/
│   ├── setup-hetzner.sh             One-time server setup
│   ├── start-staging.sh             Start/restart staging
│   ├── start-prod.sh                Start/restart prod
│   ├── init-openbao-prod.sh         First-time OpenBao init
│   ├── unseal-prod.sh               Unseal prod after restart
│   └── import-bao-secrets.sh        Import secrets to either env
└── .github/workflows/
    ├── app-ci.yml           → Copy this to decisionmesh app repo
    ├── deploy-staging.yml   Triggered by app repo via repository_dispatch
    └── deploy-prod.yml      Triggered by app repo (requires approval)
```

## Branch → Deployment

| App branch | Image tag  | Deploys to      | Approval |
|------------|------------|-----------------|----------|
| dev        | :dev       | Nothing         | —        |
| staging    | :staging   | Hetzner staging | No       |
| main       | :latest    | Hetzner prod    | Yes      |

## First-time Hetzner setup

```bash
git clone https://github.com/thirupala/decisionmesh-infra.git /opt/decisionmesh/infra
cd /opt/decisionmesh/infra

cp backend/.env.staging.example .env.staging  # fill values
cp backend/.env.prod.example    .env.prod      # fill values

bash scripts/start-staging.sh
bash scripts/import-bao-secrets.sh --env staging

bash scripts/init-openbao-prod.sh              # ONCE only
bash scripts/import-bao-secrets.sh --env prod

bash scripts/start-prod.sh
docker compose -f backend/docker-compose.gateway.yml up -d
```

## GitHub Secrets needed

In decisionmesh-infra repo:
- HETZNER_HOST, HETZNER_USER, HETZNER_SSH_KEY

In decisionmesh app repo:
- INFRA_DISPATCH_TOKEN (PAT with repo scope on decisionmesh-infra)

## After server reboot

```bash
cd /opt/decisionmesh/infra
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging up -d
bash scripts/unseal-prod.sh
docker compose -f backend/docker-compose.gateway.yml up -d
```

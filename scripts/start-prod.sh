#!/usr/bin/env bash
# scripts/start-prod.sh
# Start or restart the production stack.
# Handles OpenBao unseal automatically.
#
# Usage: bash scripts/start-prod.sh

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

[[ -f .env.prod ]] || fail ".env.prod not found."

info "Starting prod infrastructure (postgres, redis, kafka, openbao)..."
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml --env-file .env.prod \
  up -d postgres redis kafka openbao ollama

sleep 10

info "Unsealing OpenBao..."
bash scripts/unseal-prod.sh

info "Starting prod API..."
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml --env-file .env.prod \
  up -d --no-deps api

info "Starting gateway Caddy..."
docker compose -f backend/docker-compose.gateway.yml up -d

sleep 10

ok "Production stack started!"
echo ""
echo "  API:    https://api.decimeshi.com"
echo "  Health: https://api.decimeshi.com/health"
echo ""
docker logs dm-api --tail 10

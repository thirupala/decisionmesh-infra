#!/usr/bin/env bash
# scripts/start-staging.sh
# Start or restart the staging stack.
# Staging uses OpenBao in DEV MODE — no unseal needed.
#
# Usage: bash scripts/start-staging.sh

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

[[ -f .env.staging ]] || fail ".env.staging not found. Copy .env.staging.example and fill values."

info "Starting staging stack..."
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging up -d

info "Waiting for services to be healthy..."
sleep 15

info "Importing secrets to staging OpenBao..."
VAULT_TOKEN=$(grep VAULT_TOKEN .env.staging | cut -d= -f2)

docker exec decisionmesh-staging-openbao-1 sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN
  vault secrets list 2>/dev/null | grep -q '^secret/' || vault secrets enable -path=secret -version=2 kv
  echo 'KV engine ready'
" && ok "OpenBao KV engine ready"

ok "Staging stack started!"
echo ""
echo "  API:    http://staging.decimeshi.com (via gateway)"
echo "  Health: http://staging.decimeshi.com/health"
echo ""
echo "Run 'docker logs dm-api-staging --tail 50' to check API startup."

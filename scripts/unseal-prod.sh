#!/usr/bin/env bash
# scripts/unseal-prod.sh
# Unseal prod OpenBao after every restart.
# Run after server reboot or after docker restart of openbao.
#
# Usage: bash scripts/unseal-prod.sh

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

INIT_FILE=/opt/decisionmesh/secrets/openbao-init.json
[[ -f $INIT_FILE ]] || fail "Init file not found: $INIT_FILE. Run scripts/init-openbao-prod.sh first."

UNSEAL_KEY=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")

info "Checking OpenBao status..."
STATUS=$(docker exec decisionmesh-openbao-1 bao status -address=http://127.0.0.1:8200 2>/dev/null || echo "error")

if echo "$STATUS" | grep -q 'Sealed.*false'; then
  ok "OpenBao is already unsealed."
  exit 0
fi

info "Unsealing OpenBao..."
docker exec decisionmesh-openbao-1 bao operator unseal \
  -address=http://127.0.0.1:8200 "$UNSEAL_KEY"

sleep 3

docker exec decisionmesh-openbao-1 bao status -address=http://127.0.0.1:8200 | grep Sealed
ok "OpenBao unsealed!"

info "Starting prod API (if stopped)..."
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml --env-file .env.prod \
  up -d --no-deps api
ok "Done."

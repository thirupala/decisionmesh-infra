#!/usr/bin/env bash
# scripts/init-openbao-prod.sh
# Initialise prod OpenBao for the first time.
# Run ONCE on a fresh server. Saves keys to /opt/decisionmesh/secrets/openbao-init.json
# KEEP THAT FILE SAFE — loss means permanent data loss.
#
# Usage: bash scripts/init-openbao-prod.sh

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SECRETS_DIR=/opt/decisionmesh/secrets
INIT_FILE=$SECRETS_DIR/openbao-init.json

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

[[ -f .env.prod ]] || fail ".env.prod not found."

info "Starting prod OpenBao..."
docker compose -f backend/docker-compose.yml -f backend/docker-compose.prod.yml --env-file .env.prod up -d openbao
sleep 10

# Fix permissions
docker exec -u root decisionmesh-openbao-1 chown -R openbao:openbao /openbao/data 2>/dev/null || true
sleep 2

info "Initialising OpenBao..."
docker exec decisionmesh-openbao-1 bao operator init \
  -address=http://127.0.0.1:8200 \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > "$INIT_FILE"

chmod 600 "$INIT_FILE"

UNSEAL_KEY=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('$INIT_FILE'))['root_token'])")

info "Unsealing..."
docker exec decisionmesh-openbao-1 bao operator unseal \
  -address=http://127.0.0.1:8200 "$UNSEAL_KEY"

info "Enabling KV v2..."
docker exec decisionmesh-openbao-1 sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$ROOT_TOKEN
  bao secrets enable -path=secret -version=2 kv
"

# Update .env.prod with the root token
sed -i "s|VAULT_TOKEN=.*|VAULT_TOKEN=$ROOT_TOKEN|" .env.prod

ok "OpenBao initialised!"
echo ""
warn "IMPORTANT: Save these securely (e.g. password manager):"
echo "  Unseal key:  $UNSEAL_KEY"
echo "  Root token:  $ROOT_TOKEN"
echo "  Init file:   $INIT_FILE"
echo ""
echo "Next: run scripts/import-bao-secrets.sh --env prod"

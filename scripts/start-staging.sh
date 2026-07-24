#!/usr/bin/env bash
# scripts/start-staging.sh
# Start or restart the staging stack.
#
# OpenBao runs with FILE STORAGE, not dev mode — so it seals on every restart and
# must be unsealed before the API can read its secrets. Dev mode was simpler but
# lost every secret whenever the container was recreated, which turned an
# unrelated Docker restart into a dead environment.
#
# Usage: bash scripts/start-staging.sh
set -euo pipefail

cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

INIT_FILE=/opt/decisionmesh/secrets/openbao-staging-init.json

[[ -f .env.staging ]] || fail ".env.staging not found. Copy .env.staging.example and fill values."

info "Starting staging stack..."
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging up -d

info "Waiting for services to be healthy..."
sleep 15

# ── Unseal ───────────────────────────────────────────────────────────────────
# File-backed Vault comes up sealed. Without this the API starts, fails to read
# any secret, and crash-loops — with an error that points at config rather than
# at the vault.
info "Unsealing OpenBao..."
if [[ -f "$INIT_FILE" ]]; then
  UNSEAL_KEY=$(sudo python3 -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
  # || true: an already-unsealed vault exits non-zero, which would abort under set -e.
  docker exec decisionmesh-staging-openbao-1 \
    vault operator unseal -address=http://127.0.0.1:8200 "$UNSEAL_KEY" > /dev/null 2>&1 || true

  if docker exec decisionmesh-staging-openbao-1 \
       vault status -address=http://127.0.0.1:8200 2>/dev/null | grep -q "Sealed.*false"; then
    ok "OpenBao unsealed"
  else
    fail "OpenBao is still sealed — check $INIT_FILE and 'docker logs decisionmesh-staging-openbao-1'"
  fi
else
  fail "$INIT_FILE not found. Vault has never been initialised, or the keys were lost.
       Initialise with:
         docker exec decisionmesh-staging-openbao-1 vault operator init \\
           -address=http://127.0.0.1:8200 -key-shares=1 -key-threshold=1 -format=json \\
           | sudo tee $INIT_FILE"
fi

# ── KV engine ────────────────────────────────────────────────────────────────
info "Ensuring KV engine..."
# Anchored grep. An unanchored 'grep VAULT_TOKEN' also matches commented-out
# lines like '#VAULT_TOKEN=s.old...', so the variable ends up holding two values
# and every vault call returns 403 — which reads as a permissions problem rather
# than a parsing one.
VAULT_TOKEN=$(grep "^VAULT_TOKEN=" .env.staging | cut -d= -f2-)
[[ -n "$VAULT_TOKEN" ]] || fail "VAULT_TOKEN not set in .env.staging"

docker exec decisionmesh-staging-openbao-1 sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN
  vault secrets list 2>/dev/null | grep -q '^secret/' || vault secrets enable -path=secret -version=2 kv
  echo 'KV engine ready'
" && ok "OpenBao KV engine ready"

# ── Secrets check ────────────────────────────────────────────────────────────
# Vault storage persists now, so secrets survive a restart. If it is empty, the
# vault was re-initialised and the import has to be re-run — better to say so
# here than to let the API crash-loop with a config error.
if ! docker exec decisionmesh-staging-openbao-1 sh -c "
       export VAULT_ADDR=http://127.0.0.1:8200
       export VAULT_TOKEN=$VAULT_TOKEN
       vault kv list secret/decisionmesh" > /dev/null 2>&1; then
  warn "No secrets found in the vault. The API will crash-loop until you run:"
  warn "  ANTHROPIC_API_KEY='...' bash scripts/import-bao-secrets.sh --env staging"
fi

info "Restarting API to pick up secrets..."
docker compose -f backend/docker-compose.staging.yml --env-file .env.staging \
  up -d --no-deps --force-recreate api
sleep 20

ok "Staging stack started!"
echo ""
echo "  API:    https://api-staging.decimeshi.com"
echo "  Health: https://api-staging.decimeshi.com/health"
echo ""
docker logs dm-api-staging --tail 15

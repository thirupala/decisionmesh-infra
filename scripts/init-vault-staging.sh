#!/usr/bin/env bash
# scripts/init-vault-staging.sh
#
# One-time init of the now-PERSISTENT staging Vault (HashiCorp), plus
# auto-unseal sidecar wiring. Run this after switching vault-staging.hcl
# from inmem -> file storage.
#
# What it does:
#   1. (guarded) wipes the old ephemeral vault volume so we start clean
#   2. starts vault on file storage
#   3. initialises it (1 key share), saves init JSON + bare unseal key
#   4. writes the unseal key where the sidecar reads it
#   5. unseals, enables KV v2 at secret/, writes root token to .env.staging
#   6. starts the unsealer sidecar, verifies self-heal by restarting vault
#
# NOTE: staging holds no precious data — if the unseal key is lost you
# just re-run this. The key file matters for OPERATION (the sidecar), not
# for recovery.
#
# Usage:
#   bash scripts/init-vault-staging.sh          # prompts before wiping
#   bash scripts/init-vault-staging.sh --force  # no prompt

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SECRETS_DIR=/opt/decisionmesh/secrets
INIT_FILE=$SECRETS_DIR/vault-staging-init.json
KEY_FILE=$SECRETS_DIR/vault-staging-unseal.key
COMPOSE=(-f backend/docker-compose.staging.yml --env-file .env.staging)
CONTAINER=decisionmesh-staging-openbao-1
VOLUME=decisionmesh-staging_openbao-staging-data

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

[[ -f .env.staging ]] || fail ".env.staging not found in $(pwd)."
command -v python3 >/dev/null || fail "python3 required."
mkdir -p "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR"

# 1. teardown old ephemeral vault (its inmem data was never real anyway)
docker compose "${COMPOSE[@]}" rm -sf openbao-unsealer 2>/dev/null || true
if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  warn "Existing volume '$VOLUME' will be destroyed (was ephemeral/inmem — no real data)."
  if [[ $FORCE -ne 1 ]]; then
    read -r -p "Type 'wipe' to confirm: " ans
    [[ "$ans" == "wipe" ]] || fail "Aborted."
  fi
  docker compose "${COMPOSE[@]}" rm -sf openbao 2>/dev/null || true
  docker volume rm "$VOLUME" 2>/dev/null || true
  ok "Old vault volume removed."
fi

# 2. start vault on file storage
info "Starting staging Vault (file storage)..."
docker compose "${COMPOSE[@]}" up -d openbao
sleep 8

# 3. init (skip if somehow already initialised)
if docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$CONTAINER" vault status -format=json 2>/dev/null | grep -q '"initialized": true'; then
  warn "Vault already initialised — skipping init. If this is unexpected, wipe and re-run."
else
  info "Initialising Vault..."
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$CONTAINER" \
    vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  ok "Vault initialised. Init JSON saved to $INIT_FILE"
fi

UNSEAL_KEY=$(python3 -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
ROOT_TOKEN=$(python3 -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")

# 4. write bare key for the sidecar
printf '%s\n' "$UNSEAL_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"
ok "Unseal key written to $KEY_FILE"

# 5. unseal, enable KV, update .env.staging
info "Unsealing..."
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$CONTAINER" vault operator unseal "$UNSEAL_KEY" >/dev/null

info "Enabling KV v2 at secret/ ..."
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$ROOT_TOKEN" "$CONTAINER" \
  vault secrets enable -path=secret -version=2 kv 2>/dev/null || warn "KV may already be enabled."

sed -i "s|^VAULT_TOKEN=.*|VAULT_TOKEN=$ROOT_TOKEN|" .env.staging
grep -q '^VAULT_TOKEN=' .env.staging || echo "VAULT_TOKEN=$ROOT_TOKEN" >> .env.staging
ok "VAULT_TOKEN updated in .env.staging"

# 6. start sidecar + verify self-heal
info "Starting unsealer sidecar..."
docker compose "${COMPOSE[@]}" up -d openbao-unsealer || \
  warn "Could not start openbao-unsealer — check the service block in the compose file."

info "Verifying self-heal (restarting vault)..."
docker restart "$CONTAINER" >/dev/null
sleep 15
if docker exec -e VAULT_ADDR=http://127.0.0.1:8200 "$CONTAINER" vault status -format=json 2>/dev/null | grep -q '"sealed": false'; then
  ok "Vault re-unsealed itself after restart. Auto-unseal working."
else
  warn "Vault still sealed after restart — check: docker logs decisionmesh-staging-openbao-unsealer-1"
fi

echo ""
ok "Staging Vault is now persistent + auto-unsealing."
echo "  Init JSON:   $INIT_FILE"
echo "  Unseal key:  $KEY_FILE (mounted into the sidecar)"
echo "  Root token:  written to .env.staging as VAULT_TOKEN"
echo ""
info "Next: seed staging secrets, then recreate the API:"
info "  export ANTHROPIC_API_KEY=... ZITADEL_TOKEN=...   # staging values"
info "  bash scripts/import-bao-secrets.sh --env staging"
info "  docker compose ${COMPOSE[*]} up -d --no-deps --force-recreate api"
#!/usr/bin/env bash
# scripts/init-openbao-prod.sh
#
# Rebuild prod OpenBao from scratch with SELF-CONTAINED AUTO-UNSEAL.
#
# What this does:
#   1. (guarded) wipes the existing openbao container + data volume
#   2. starts a fresh openbao
#   3. initialises it, saving the full init JSON to /opt/decisionmesh/secrets/
#   4. writes the bare unseal key to openbao-unseal.key
#         ^-- the openbao-unsealer sidecar mounts and reads this file
#   5. unseals, enables KV v2, writes the root token into .env.prod
#   6. starts the openbao-unsealer sidecar so the vault re-unseals itself
#         after any VM / daemon / container restart
#   7. verifies self-heal by restarting the vault and checking it comes back unsealed
#
# NOTE ON DATA LOSS: there is no precious data in this vault, and this script
#   rebuilds it end-to-end. If the unseal key file is ever lost, you do NOT lose
#   data permanently — you just re-run this script. The key file matters for
#   OPERATION (the sidecar needs it), not for recovery.
#
# SECURITY TRADEOFF (accepted): the unseal key sits at
#   /opt/decisionmesh/secrets/openbao-unseal.key (mode 600) and is mounted
#   read-only into the sidecar. Anyone with root or that file can unseal the
#   vault. Fine given no sensitive data; if that changes, swap the sidecar's
#   file mount for AWS KMS and the rest of this stays identical.
#
# PREREQUISITE (one-time, manual): the `openbao-unsealer` service must exist in
#   backend/docker-compose.prod.yml, as a sibling of the `openbao` service:
#
#     openbao-unsealer:
#       image: openbao/openbao:2
#       depends_on: [openbao]
#       restart: unless-stopped
#       environment:
#         BAO_ADDR: http://openbao:8200
#       entrypoint: ["/bin/sh", "/usr/local/bin/unsealer.sh"]
#       volumes:
#         - ./scripts/openbao-unsealer.sh:/usr/local/bin/unsealer.sh:ro
#         - /opt/decisionmesh/secrets/openbao-unseal.key:/unseal.key:ro
#
# Usage:
#   bash scripts/init-openbao-prod.sh          # prompts before wiping
#   bash scripts/init-openbao-prod.sh --force  # no prompt (CI / re-runs)

set -euo pipefail
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SECRETS_DIR=/opt/decisionmesh/secrets
INIT_FILE=$SECRETS_DIR/openbao-init.json
KEY_FILE=$SECRETS_DIR/openbao-unseal.key
UNSEALER_SCRIPT=scripts/openbao-unsealer.sh
CONTAINER=decisionmesh-openbao-1
VOLUME=decisionmesh_openbao-data
COMPOSE=(-f backend/docker-compose.yml -f backend/docker-compose.prod.yml --env-file .env.prod)

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ -f .env.prod ]] || fail ".env.prod not found in $(pwd)."
command -v python3 >/dev/null || fail "python3 required."
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# ---------------------------------------------------------------------------
# Write the unsealer sidecar script if it isn't already present.
# Uses `bao status` EXIT CODES (2 = sealed) so there's no JSON to parse/break.
# ---------------------------------------------------------------------------
if [[ ! -f "$UNSEALER_SCRIPT" ]]; then
  info "Writing $UNSEALER_SCRIPT ..."
  cat > "$UNSEALER_SCRIPT" <<'USCRIPT'
#!/bin/sh
# Keeps openbao unsealed across VM / daemon / container restarts.
# Loops forever; whenever the vault reports sealed, unseals it with the
# key mounted at $KEY_FILE. Runs as the `openbao-unsealer` compose service.
: "${BAO_ADDR:=http://openbao:8200}"; export BAO_ADDR
KEY_FILE="${KEY_FILE:-/unseal.key}"
while true; do
  bao status >/dev/null 2>&1; s=$?
  if [ "$s" -eq 2 ]; then                 # 2 = reachable but sealed
    if bao operator unseal "$(cat "$KEY_FILE")" >/dev/null 2>&1; then
      echo "$(date -Iseconds) openbao unsealed"
    fi
  fi
  sleep 10
done
USCRIPT
  chmod +x "$UNSEALER_SCRIPT"
  ok "Wrote $UNSEALER_SCRIPT"
else
  info "$UNSEALER_SCRIPT already present — leaving as-is."
fi

# ---------------------------------------------------------------------------
# Guarded teardown of the existing vault (this is a REBUILD, not a first init).
# ---------------------------------------------------------------------------
docker compose "${COMPOSE[@]}" rm -sf openbao-unsealer 2>/dev/null || true

if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  warn "Existing volume '$VOLUME' found — it will be DESTROYED and the vault re-initialised."
  if [[ $FORCE -ne 1 ]]; then
    read -r -p "Type 'wipe' to confirm teardown of the prod vault: " ans
    [[ "$ans" == "wipe" ]] || fail "Aborted — nothing changed."
  fi
  info "Tearing down old openbao..."
  docker compose "${COMPOSE[@]}" rm -sf openbao 2>/dev/null || true
  docker volume rm "$VOLUME"
  ok "Old vault removed."
fi

# ---------------------------------------------------------------------------
# Fresh vault
# ---------------------------------------------------------------------------
info "Starting fresh prod OpenBao..."
docker compose "${COMPOSE[@]}" up -d openbao
sleep 10

# Ensure the data dir is writable by the openbao user (fixes first-run perms).
docker exec -u root "$CONTAINER" chown -R openbao:openbao /openbao/data 2>/dev/null || true
sleep 2

info "Initialising OpenBao..."
docker exec "$CONTAINER" bao operator init \
  -address=http://127.0.0.1:8200 \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > "$INIT_FILE"
chmod 600 "$INIT_FILE"

UNSEAL_KEY=$(python3 -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][0])")
ROOT_TOKEN=$(python3 -c "import json;print(json.load(open('$INIT_FILE'))['root_token'])")

# The bare key the sidecar mounts and reads. (cat in the sidecar strips the
# trailing newline via command substitution, so the newline here is harmless.)
printf '%s\n' "$UNSEAL_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"
ok "Unseal key written to $KEY_FILE (read by openbao-unsealer)."

info "Unsealing..."
docker exec "$CONTAINER" bao operator unseal \
  -address=http://127.0.0.1:8200 "$UNSEAL_KEY"

info "Enabling KV v2 at secret/ ..."
docker exec "$CONTAINER" sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$ROOT_TOKEN
  bao secrets enable -path=secret -version=2 kv
"

# Update .env.prod with the root token
sed -i "s|^VAULT_TOKEN=.*|VAULT_TOKEN=$ROOT_TOKEN|" .env.prod
ok "VAULT_TOKEN updated in .env.prod"

# ---------------------------------------------------------------------------
# Start the auto-unseal sidecar
# ---------------------------------------------------------------------------
info "Starting openbao-unsealer sidecar..."
if ! docker compose "${COMPOSE[@]}" up -d openbao-unsealer 2>/dev/null; then
  warn "Could not start 'openbao-unsealer' — is the service defined in your compose?"
  warn "Add the service block from this script's header, then re-run:"
  warn "  docker compose ${COMPOSE[*]} up -d openbao-unsealer"
fi

# ---------------------------------------------------------------------------
# Verify self-heal — the actual acceptance test.
# Restart the vault; the sidecar should re-unseal it within ~15s.
# ---------------------------------------------------------------------------
info "Verifying self-heal (restarting vault; sidecar should re-unseal it)..."
docker restart "$CONTAINER" >/dev/null
sleep 15
if docker exec -e BAO_ADDR=http://127.0.0.1:8200 "$CONTAINER" bao status 2>/dev/null \
     | grep -Eq 'Sealed[[:space:]]+false'; then
  ok "Vault re-unsealed itself after restart. Auto-unseal is working."
else
  warn "Vault still sealed after restart — investigate:"
  warn "  docker logs --tail 20 \$(docker ps -qf name=openbao-unsealer)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
ok "Prod OpenBao rebuilt with self-contained auto-unseal."
echo "  Init JSON:       $INIT_FILE   (mode 600)"
echo "  Unseal key file: $KEY_FILE    (mounted into the unsealer sidecar)"
echo "  Root token:      written to .env.prod as VAULT_TOKEN"
echo ""
info "Next: bash scripts/import-bao-secrets.sh --env prod"
info "Then: docker compose ${COMPOSE[*]} up -d --force-recreate api"
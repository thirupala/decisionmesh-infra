#!/usr/bin/env bash
# scripts/start-local.sh — Build image and start all local containers
#
# Usage: bash scripts/start-local.sh
#
# NOTE: API keys (OpenAI, Anthropic, Stripe, Razorpay, etc.) are NOT stored here.
#       After running this script, import secrets via:
#         bash scripts/import-bao-secrets.sh --env local
#
set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${RED}[WARN]${NC}  $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="/mnt/d/DM/decisionmesh"

# ── Step 1: Build the Docker image ──────────────────────────
info "Building decisionmesh:local image..."
cd "$APP_DIR"
mvn package -DskipTests -q
docker build \
  -f decisionmesh-bootstrap/src/main/docker/Dockerfile.jvm \
  -t decisionmesh:local \
  decisionmesh-bootstrap/
ok "Image built: decisionmesh:local"

# ── Step 2: Stop any old local containers ───────────────────
cd "$INFRA_DIR"
info "Stopping any existing local containers..."
docker compose -f backend/docker-compose.local.yml --env-file backend/.env.local down 2>/dev/null || true

# ── Step 3: Start all containers ────────────────────────────
info "Starting all local containers..."
docker compose \
  -f backend/docker-compose.local.yml \
  --env-file backend/.env.local \
  up -d

# ── Step 4: Wait for OpenBao and import non-sensitive config ─
info "Waiting for OpenBao to be ready..."
sleep 15

info "Configuring local OpenBao (non-sensitive config only)..."
docker exec decisionmesh-local-openbao-1 sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=dev-root-token

  # Enable KV v2 engine (idempotent)
  vault secrets enable -path=secret -version=2 kv 2>/dev/null || true

  # ── Database (non-sensitive — local dev passwords only) ───
  vault kv put secret/decisionmesh/db \
    password='decisionmesh' \
    url='jdbc:postgresql://localhost:5432/decisionmesh' \
    reactive_url='postgresql://localhost:5432/decisionmesh' \
    username='decisionmesh'

  # ── Redis (non-sensitive — local dev password only) ───────
  vault kv put secret/decisionmesh/redis \
    quarkus.redis.password='decisionmesh'

  echo 'Non-sensitive config imported.'
" && ok "OpenBao base config ready" || warn "OpenBao config failed — check logs"

# ── Step 5: Remind user to import API keys ───────────────────
echo ""
echo "════════════════════════════════════════════════════════"
warn "ACTION REQUIRED: Import API keys into OpenBao"
echo ""
echo "  Edit scripts/import-bao-secrets.sh and fill in your keys:"
echo "    - OpenAI API key"
echo "    - Anthropic API key"
echo "    - Gemini API key"
echo "    - DeepSeek API key"
echo "    - Stripe secret key"
echo "    - Razorpay key ID + secret + webhook secret"
echo "    - Gmail app password"
echo "    - Zitadel service account token"
echo ""
echo "  Then run:"
echo "    bash scripts/import-bao-secrets.sh --env local"
echo "════════════════════════════════════════════════════════"
echo ""

# ── Step 6: Health check ─────────────────────────────────────
info "Waiting for API to start (up to 60s)..."
for i in $(seq 1 12); do
  sleep 5
  STATUS=$(curl -s http://localhost:8080/q/health 2>/dev/null | grep -o '"status":"[^"]*"' | head -1)
  if [[ "$STATUS" == *"UP"* ]]; then
    ok "API is UP! → http://localhost:8080"
    break
  fi
  echo "  Waiting... ($((i*5))s)"
done

echo ""
echo "════════════════════════════════════════════════════════"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "════════════════════════════════════════════════════════"
ok "Local stack ready!"
echo ""
echo "  API:      http://localhost:8080"
echo "  Health:   http://localhost:8080/q/health"
echo "  Metrics:  http://localhost:8080/q/metrics"
echo "  Dev UI:   http://localhost:8080/q/dev-ui"
echo "  OpenBao:  http://localhost:8200  (token: dev-root-token)"
echo "  Frontend: cd /mnt/d/DM/decisionmesh-ui && npm run dev"
echo ""
echo "  Next: bash scripts/import-bao-secrets.sh --env local"

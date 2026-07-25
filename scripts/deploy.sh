#!/usr/bin/env bash
# deploy.sh — pull latest images and recreate the API for prod + staging.
#
# Improves on a bare "pull && up -d --force-recreate" by:
#   - verifying the container actually STAYED up (catches Flyway crash-loops)
#   - dumping logs immediately if a deploy fails, instead of walking past it
#   - reloading Caddy so it re-resolves the recreated API containers (no stray 502)
#
# Usage:
#   bash deploy.sh          # deploy both
#   bash deploy.sh prod     # prod only
#   bash deploy.sh staging  # staging only

set -uo pipefail            # NOT -e: we handle failures per-deploy, don't abort the whole run
cd /opt/decisionmesh/infra

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[FAIL]${NC}  $*"; }

deploy() {
  local name="$1" tag="$2" container="$3" url="$4"; shift 4
  local files=("$@")   # remaining args are the -f ... compose flags

  info "Deploying $name ($tag)..."
  docker pull "ghcr.io/decimeshi/decisionmesh:$tag"
  docker compose "${files[@]}" --env-file ".env.$name" up -d --no-deps --force-recreate api

  # give it time to boot, then confirm it's RUNNING (not restarting/exited)
  sleep 25
  local state
  state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
  if [ "$state" != "running" ]; then
    err "$container is '$state' — deploy FAILED. Recent logs:"
    docker logs "$container" --tail 30 2>&1 | tail -30
    return 1
  fi

  local rev
  rev=$(docker inspect "$container" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null)
  ok "$container running — revision ${rev:0:12}"

  if curl -sf "$url" >/dev/null 2>&1; then
    ok "$name health OK ($url)"
  else
    warn "$name health check did not pass ($url) — check Caddy routing / app health"
  fi
  return 0
}

TARGET="${1:-both}"
FAILED=0

if [ "$TARGET" = "prod" ] || [ "$TARGET" = "both" ]; then
  deploy prod latest dm-api "https://api.decimeshi.com/health" \
    -f backend/docker-compose.yml -f backend/docker-compose.prod.yml || FAILED=1
fi

if [ "$TARGET" = "staging" ] || [ "$TARGET" = "both" ]; then
  deploy staging staging dm-api-staging "https://api-staging.decimeshi.com/health" \
    -f backend/docker-compose.staging.yml || FAILED=1
fi

# reload Caddy so it re-resolves the freshly recreated API containers
info "Reloading Caddy..."
if docker exec dm-caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
  ok "Caddy reloaded"
else
  warn "caddy reload failed — restarting the container instead"
  docker restart dm-caddy >/dev/null && ok "Caddy restarted"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  ok "Deploy complete."
else
  err "One or more deploys failed — see logs above."
  exit 1
fi
#!/bin/bash
# ============================================================
#  DECIMESHI — Copy Vault/OpenBao secrets: local -> e2e
#
#  Reads every secret under secret/decisionmesh/* from the local
#  dev OpenBao (port 8200, token dev-root-token) and writes it to
#  the e2e OpenBao (port 8201, token e2e-root-token, per
#  decisionmesh-ui/e2e/docker-compose.e2e.yml's "-dev-root-token-id").
#
#  Both containers publish their ports to the host, so this talks
#  to Vault's HTTP API directly over localhost -- no docker exec
#  needed. Recurses into nested KV folders if any exist (the
#  current seed-vault.sh layout is flat: db, redis, kafka, auth,
#  llm, email, razorpay, stripe).
#
#  e2e's vault runs in "-dev" mode, so it's wiped every time that
#  container restarts -- that's exactly why this script exists
#  instead of a one-time seed.
#
#  Usage:
#    ./copy-vault-to-e2e.sh            # copy everything
#    ./copy-vault-to-e2e.sh --dry-run  # list what would be copied, copy nothing
#
#  Requires: curl, jq
# ============================================================

set -euo pipefail

SRC_ADDR="http://localhost:8200"
SRC_TOKEN="dev-root-token"
DST_ADDR="http://localhost:8201"
DST_TOKEN="e2e-root-token"
MOUNT="secret"
ROOT="decisionmesh"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

GREEN='\033[0;32m'
TEAL='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${TEAL}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
divider() { echo -e "${TEAL}────────────────────────────────────────────────${NC}"; }

command -v jq >/dev/null 2>&1 || error "jq is required but not found on PATH."

divider
echo -e "  ${BOLD}DECIMESHI — Copy Vault secrets: local -> e2e${NC}"
divider
info "Source:      $SRC_ADDR (local)"
info "Destination: $DST_ADDR (e2e)"
$DRY_RUN && warn "Dry run — nothing will be written."
divider
echo ""

# ── Reachability checks ──────────────────────────────────────
curl -sf -m 5 -H "X-Vault-Token: $SRC_TOKEN" "$SRC_ADDR/v1/sys/health" > /dev/null \
  || error "Cannot reach source vault at $SRC_ADDR. Is decisionmesh-local-openbao-1 up?"
curl -sf -m 5 -H "X-Vault-Token: $DST_TOKEN" "$DST_ADDR/v1/sys/health" > /dev/null \
  || error "Cannot reach e2e vault at $DST_ADDR. Is decisionmesh-e2e-vault-1 up?"
success "Both vaults reachable."
echo ""

COPIED=0
SKIPPED=0

copy_recursive() {
  local rel="$1"   # path relative to $ROOT, "" for the root itself
  local list_path="$ROOT${rel:+/$rel}"
  local keys
  keys=$(curl -sf -H "X-Vault-Token: $SRC_TOKEN" \
    "$SRC_ADDR/v1/$MOUNT/metadata/$list_path?list=true" 2>/dev/null \
    | jq -r '.data.keys[]?' || true)

  if [ -z "$keys" ]; then
    return
  fi

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if [[ "$key" == */ ]]; then
      copy_recursive "${rel:+$rel/}${key%/}"
    else
      local full_path="$ROOT${rel:+/$rel}/$key"
      local data
      data=$(curl -sf -H "X-Vault-Token: $SRC_TOKEN" \
        "$SRC_ADDR/v1/$MOUNT/data/$full_path" | jq -c '.data.data')

      if [ -z "$data" ] || [ "$data" = "null" ]; then
        warn "skip (empty): $full_path"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi

      if $DRY_RUN; then
        info "would copy: $full_path ($(echo "$data" | jq 'keys | length') keys)"
      else
        curl -sf -H "X-Vault-Token: $DST_TOKEN" -H "Content-Type: application/json" \
          -X POST -d "{\"data\": $data}" \
          "$DST_ADDR/v1/$MOUNT/data/$full_path" > /dev/null
        success "copied: $full_path"
      fi
      COPIED=$((COPIED + 1))
    fi
  done <<< "$keys"
}

copy_recursive ""

echo ""
divider
if [ "$COPIED" -eq 0 ]; then
  warn "No secrets found under $MOUNT/$ROOT on the source vault — nothing copied."
else
  if $DRY_RUN; then
    success "Dry run complete: $COPIED path(s) would be copied, $SKIPPED skipped."
  else
    success "Done: $COPIED path(s) copied to e2e, $SKIPPED skipped."
    info "Verify with: curl -s -H \"X-Vault-Token: $DST_TOKEN\" $DST_ADDR/v1/$MOUNT/metadata/$ROOT?list=true | jq"
  fi
fi
divider

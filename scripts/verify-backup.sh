#!/usr/bin/env bash
# scripts/verify-backup.sh
# Monthly backup verification — SOC 2 CC9.1
#
# Usage:
#   bash scripts/verify-backup.sh --env staging
#   bash scripts/verify-backup.sh --env prod
#
# Cron (1st of every month at 03:00 UTC):
#   0 3 1 * * bash /opt/decisionmesh/infra/scripts/verify-backup.sh --env prod >> /var/log/decisionmesh/backup-verify.log 2>&1

set -uo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────
ENV=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --env) ENV="$2"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
[[ -n "$ENV" ]] || fail "Usage: $0 --env [staging|prod]"

cd /opt/decisionmesh/infra/backend

# ── Load env ──────────────────────────────────────────────────────────────────
if [[ "$ENV" == "staging" ]]; then
  ENV_FILE=".env.staging"
  POSTGRES_CONTAINER="decisionmesh-staging-postgres-1"
elif [[ "$ENV" == "prod" ]]; then
  ENV_FILE=".env.prod"
  POSTGRES_CONTAINER="decisionmesh-prod-postgres-1"
else
  fail "ENV must be 'staging' or 'prod'"
fi

[[ -f "$ENV_FILE" ]] || fail "$ENV_FILE not found"

DB_NAME=$(grep DB_NAME "$ENV_FILE" | cut -d= -f2 | tr -d "\r")
DB_USER=$(grep DB_USER "$ENV_FILE" | cut -d= -f2 | tr -d "\r")
DB_PASSWORD=$(grep DB_PASSWORD "$ENV_FILE" | cut -d= -f2 | tr -d "\r")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/decisionmesh_backup_${ENV}_${TIMESTAMP}.sql"
VERIFY_DB="decisionmesh_verify_${TIMESTAMP}"
LOG_FILE="/var/log/decisionmesh/backup-verify-${ENV}-${TIMESTAMP}.log"

mkdir -p /var/log/decisionmesh

info "=========================================="
info " DecisionMesh Backup Verification"
info " Environment : $ENV"
info " Timestamp   : $TIMESTAMP"
info "=========================================="

# ── Step 1: Take backup ───────────────────────────────────────────────────────
info "Step 1: Taking PostgreSQL backup..."
if docker exec "$POSTGRES_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -E UTF8 --format=plain > "$BACKUP_FILE"; then
  BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
  ok "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
else
  fail "Backup failed"
fi

# ── Step 2: Get source row counts ─────────────────────────────────────────────
info "Step 2: Getting source row counts..."
SOURCE_COUNTS=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
  SELECT 'tenants='          || COUNT(*) FROM tenants
  UNION ALL SELECT 'users='              || COUNT(*) FROM users
  UNION ALL SELECT 'intents='            || COUNT(*) FROM intents
  UNION ALL SELECT 'execution_records='  || COUNT(*) FROM execution_records
  UNION ALL SELECT 'audit_log='          || COUNT(*) FROM audit_log
  UNION ALL SELECT 'api_keys='           || COUNT(*) FROM api_keys
  UNION ALL SELECT 'policies='           || COUNT(*) FROM policies;
" | tr -d ' \t' | grep -v '^$')
ok "Source counts captured:"
echo "$SOURCE_COUNTS"

# ── Step 3: Create temp verification database ─────────────────────────────────
info "Step 3: Creating verification database: $VERIFY_DB..."
if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $VERIFY_DB;" > /dev/null 2>&1; then
  ok "Verification database created"
else
  fail "Could not create verification database"
fi

# ── Step 4: Restore backup ────────────────────────────────────────────────────
info "Step 4: Restoring backup to verification database..."
if docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$VERIFY_DB" --quiet < "$BACKUP_FILE" > /dev/null 2>&1; then
  ok "Backup restored successfully"
else
  fail "Restore failed"
fi

# ── Step 5: Verify row counts match ───────────────────────────────────────────
info "Step 5: Verifying row counts..."
VERIFY_COUNTS=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$VERIFY_DB" -t -c "
  SELECT 'tenants='          || COUNT(*) FROM tenants
  UNION ALL SELECT 'users='              || COUNT(*) FROM users
  UNION ALL SELECT 'intents='            || COUNT(*) FROM intents
  UNION ALL SELECT 'execution_records='  || COUNT(*) FROM execution_records
  UNION ALL SELECT 'audit_log='          || COUNT(*) FROM audit_log
  UNION ALL SELECT 'api_keys='           || COUNT(*) FROM api_keys
  UNION ALL SELECT 'policies='           || COUNT(*) FROM policies;
" | tr -d ' \t' | grep -v '^$')

PASSED=0
FAILED=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if echo "$SOURCE_COUNTS" | grep -qF "$line"; then
    ok "MATCH: $line"
    ((PASSED++)) || true
  else
    warn "MISMATCH: $line (not found in source)"
    ((FAILED++)) || true
  fi
done <<< "$VERIFY_COUNTS"

# ── Step 6: Cleanup ───────────────────────────────────────────────────────────
info "Step 6: Cleaning up..."
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE $VERIFY_DB;" > /dev/null 2>&1 || true
rm -f "$BACKUP_FILE"
ok "Cleanup complete"

# ── Step 7: Report ────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " BACKUP VERIFICATION REPORT"
echo " Environment : $ENV"
echo " Date        : $(date)"
echo " Backup Size : $BACKUP_SIZE"
echo " Tables OK   : $PASSED"
echo " Mismatches  : $FAILED"
echo "=========================================="

if [[ $FAILED -eq 0 ]]; then
  ok "BACKUP VERIFICATION PASSED ✅"
  echo "RESULT=PASSED date=$(date)" >> "$LOG_FILE"
  exit 0
else
  warn "BACKUP VERIFICATION FAILED ❌ — $FAILED mismatches found"
  echo "RESULT=FAILED date=$(date)" >> "$LOG_FILE"
  exit 1
fi

#!/usr/bin/env bash
# scripts/import-bao-secrets.sh
# Import secrets into OpenBao for staging or prod.
# Edit the SECRET VALUES section below before running.
#
# Usage:
#   bash scripts/import-bao-secrets.sh --env staging
#   bash scripts/import-bao-secrets.sh --env prod

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

ENV=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --env) ENV="$2"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$ENV" ]] || fail "Usage: $0 --env [staging|prod]"

if [[ "$ENV" == "staging" ]]; then
  CONTAINER="decisionmesh-staging-openbao-1"
  ENV_FILE=".env.staging"
  VAULT_CMD="vault"
elif [[ "$ENV" == "prod" ]]; then
  CONTAINER="decisionmesh-openbao-1"
  ENV_FILE=".env.prod"
  VAULT_CMD="bao"
else
  fail "ENV must be 'staging' or 'prod'"
fi

cd /opt/decisionmesh/infra
[[ -f $ENV_FILE ]] || fail "$ENV_FILE not found."
VAULT_TOKEN=$(grep VAULT_TOKEN "$ENV_FILE" | cut -d= -f2)

info "Importing secrets to $ENV OpenBao ($CONTAINER)..."

# ============================================================
# SECRET VALUES — edit these before running
# ============================================================
OPENAI_KEY="sk-proj-..."
ANTHROPIC_KEY="sk-ant-api03-..."
GEMINI_KEY="AIzaSy..."
DEEPSEEK_KEY="sk-..."
STRIPE_KEY="sk_test_..."
RAZORPAY_KEY_ID="rzp_test_..."
RAZORPAY_KEY_SECRET="..."
RAZORPAY_WEBHOOK_SECRET="..."
MAILER_PASSWORD="..."
MAILER_USERNAME="thirupala@gmail.com"
ZITADEL_TOKEN="..."
DB_PASSWORD=$(grep DB_PASSWORD "$ENV_FILE" | cut -d= -f2)
# ============================================================

docker exec "$CONTAINER" sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN

  $VAULT_CMD secrets list 2>/dev/null | grep -q '^secret/' || \
    $VAULT_CMD secrets enable -path=secret -version=2 kv

  $VAULT_CMD kv put secret/decisionmesh/db \
    password='$DB_PASSWORD' \
    url='jdbc:postgresql://postgres:5432/decisionmesh' \
    reactive_url='postgresql://postgres:5432/decisionmesh' \
    username='decisionmesh'

  $VAULT_CMD kv put secret/decisionmesh/llm \
    llm.openai.api-key='$OPENAI_KEY' \
    llm.anthropic.api-key='$ANTHROPIC_KEY' \
    llm.gemini.api-key='$GEMINI_KEY' \
    llm.deepseek.api-key='$DEEPSEEK_KEY'

  $VAULT_CMD kv put secret/decisionmesh/stripe \
    stripe.secret.key='$STRIPE_KEY'

  $VAULT_CMD kv put secret/decisionmesh/razorpay \
    razorpay.key.id='$RAZORPAY_KEY_ID' \
    razorpay.key.secret='$RAZORPAY_KEY_SECRET' \
    razorpay.webhook.secret='$RAZORPAY_WEBHOOK_SECRET'

  $VAULT_CMD kv put secret/decisionmesh/email \
    quarkus.mailer.password='$MAILER_PASSWORD' \
    username='$MAILER_USERNAME'

  $VAULT_CMD kv put secret/decisionmesh/auth \
    vault_token='$VAULT_TOKEN' \
    zitadel_service_account_token='$ZITADEL_TOKEN'

  echo 'All secrets imported.'
"

ok "Secrets imported to $ENV OpenBao!"
info "Verify: docker exec $CONTAINER $VAULT_CMD kv list -address=http://127.0.0.1:8200 secret/decisionmesh"

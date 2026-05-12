#!/usr/bin/env bash
# scripts/setup-hetzner.sh
# First-time setup on a fresh Hetzner server.
# Run once as root/sudo.
#
# Usage: bash scripts/setup-hetzner.sh

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }

info "Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
ok "Docker installed"

info "Creating deploy user (decisionmesh)..."
id decisionmesh &>/dev/null || useradd -m -s /bin/bash decisionmesh
usermod -aG docker decisionmesh
ok "User ready"

info "Creating directory structure..."
mkdir -p /opt/decisionmesh/infra/{config,scripts}
chown -R decisionmesh:decisionmesh /opt/decisionmesh
ok "Directories created"

info "Cloning repo..."
su - decisionmesh -c "
  git clone https://github.com/thirupala/decisionmesh.git /opt/decisionmesh/infra
"
ok "Repo cloned"

info "Setting up SSH for GitHub Actions deploy..."
mkdir -p /home/decisionmesh/.ssh
chmod 700 /home/decisionmesh/.ssh
echo "Add the deploy public key to /home/decisionmesh/.ssh/authorized_keys"
echo "Then add the private key as HETZNER_SSH_KEY in GitHub Secrets"

info "Generating Kafka cluster IDs..."
STAGING_KAFKA_ID=$(docker run --rm apache/kafka:3.7.0 kafka-storage.sh random-uuid 2>/dev/null)
PROD_KAFKA_ID=$(docker run --rm apache/kafka:3.7.0 kafka-storage.sh random-uuid 2>/dev/null)
echo ""
echo "STAGING KAFKA_CLUSTER_ID: $STAGING_KAFKA_ID"
echo "PROD    KAFKA_CLUSTER_ID: $PROD_KAFKA_ID"
echo ""
echo "Add these to .env.staging and .env.prod respectively."

ok "Setup complete! Next steps:"
echo "  1. Copy .env.staging.example → .env.staging  and fill values"
echo "  2. Copy .env.prod.example    → .env.prod      and fill values"
echo "  3. Run: scripts/start-staging.sh"
echo "  4. Run: scripts/start-prod.sh"
echo "  5. Add GitHub Secrets: HETZNER_HOST, HETZNER_USER, HETZNER_SSH_KEY"

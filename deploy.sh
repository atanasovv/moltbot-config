#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw Quick Deploy Script
# 
# Usage:
#   ./deploy.sh [version]
#   USE_DOCKERHUB=true ./deploy.sh [version]
#
# Examples:
#   ./deploy.sh                    # Build locally and deploy
#   USE_DOCKERHUB=true ./deploy.sh # Pull latest from Docker Hub
#   USE_DOCKERHUB=true ./deploy.sh v1.2.3  # Pull specific version
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Parse arguments
IMAGE_VERSION="${1:-secure}"
USE_DOCKERHUB=${USE_DOCKERHUB:-false}
DOCKERHUB_USER="vladislav2502"
DOCKERHUB_IMAGE="${DOCKERHUB_USER}/openclaw:${IMAGE_VERSION}"

echo "═══════════════════════════════════════════════════════════════════"
echo "   OpenClaw Quick Deploy"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Source:  ${USE_DOCKERHUB}"
echo "  Image:   ${DOCKERHUB_IMAGE}"
echo "  Version: ${IMAGE_VERSION}"
echo ""

# Check secrets exist
if [[ ! -d "secrets" ]] || [[ ! -f "secrets/telegram_bot_token.txt" ]]; then
    echo "Error: Secrets not initialized"
    echo "Run: ./init-secrets.sh"
    exit 1
else
    echo "✓ Secrets already initialized"
fi

# Deploy image based on source
if [[ "${USE_DOCKERHUB}" == "true" ]]; then
    echo ""
    echo "Pulling Docker image from Docker Hub..."
    if docker pull "${DOCKERHUB_IMAGE}"; then
        docker tag "${DOCKERHUB_IMAGE}" openclaw:secure
        echo "✓ Image pulled from Docker Hub: ${DOCKERHUB_IMAGE}"
    else
        echo "Error: Failed to pull ${DOCKERHUB_IMAGE}"
        echo "Available tags at: https://hub.docker.com/r/${DOCKERHUB_USER}/openclaw/tags"
        exit 1
    fi
else
    if ! docker images | grep -q "openclaw.*secure"; then
        echo ""
        echo "Building Docker image locally..."
        docker build -t openclaw:secure .
        echo "✓ Image built locally"
    else
        echo "✓ Using existing local Docker image"
    fi
fi

# Create necessary directories
echo ""
echo "Creating directories..."
mkdir -p config workspace logs
chmod 700 secrets

echo "✓ Directories ready"

# Start OpenClaw
echo ""
echo "Starting OpenClaw..."
docker compose up -d

echo ""
echo "Waiting for OpenClaw to be ready..."
sleep 10

# Check status
if docker compose ps | grep -q "healthy\|running"; then
    echo "✓ OpenClaw is running"
else
    echo "⚠ OpenClaw may not be healthy. Check logs:"
    echo "  docker compose logs openclaw"
fi

# Optional: Start monitoring
echo ""
read -p "Start monitoring stack (Prometheus/Grafana)? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd monitoring
    ./setup-monitoring.sh
    cd ..
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "   OpenClaw Deployment Complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Services running:"
docker compose ps
echo ""
echo "Useful commands:"
echo "  View logs:        docker compose logs -f openclaw"
echo "  Check status:     docker compose ps"
echo "  Stop OpenClaw:    docker compose down"
echo "  Restart:          docker compose restart openclaw"
echo ""
echo "Configuration: config/openclaw.json"
echo "Workspace:     workspace/"
echo "Logs:          logs/"
echo ""
echo "Next steps:"
echo "  1. Message your Telegram bot to trigger pairing"
echo "  2. Approve the pairing code"
echo "  3. Add user ID to config/openclaw.json allowFrom"
echo "  4. Restart: docker compose restart openclaw"
echo ""
echo "Monitoring (if enabled):"
echo "  Grafana:   http://localhost:3000"
echo "  Prometheus: http://localhost:9090"
echo ""

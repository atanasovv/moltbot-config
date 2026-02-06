#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw Quick Deploy Script
# 
# One-command deployment for OpenClaw with all components
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "═══════════════════════════════════════════════════════════════════"
echo "   OpenClaw Quick Deploy"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check if Docker is running
if ! docker ps &>/dev/null; then
    echo "Error: Docker is not running."
    echo "Please start Docker Desktop (macOS) or Docker service (Ubuntu)"
    exit 1
fi

echo "✓ Docker is running"

# Check if secrets are initialized
if [[ ! -f secrets/.initialized ]]; then
    echo ""
    echo "Secrets not initialized. Running init-secrets.sh..."
    ./init-secrets.sh
else
    echo "✓ Secrets already initialized"
fi

# Check if Docker image exists
if ! docker images | grep -q "openclaw.*secure"; then
    echo ""
    echo "Building Docker image..."
    docker build -t openclaw:secure .
else
    echo "✓ Docker image exists"
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

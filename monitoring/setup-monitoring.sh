#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw Monitoring Stack Setup Script
# 
# Deploys Prometheus, Grafana, and Alertmanager for OpenClaw monitoring
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=== OpenClaw Monitoring Stack Setup ==="
echo ""

# Check if Docker is running
if ! docker ps &>/dev/null; then
    echo "Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if OpenClaw network exists
if ! docker network ls | grep -q openclaw-net; then
    echo "Creating OpenClaw network..."
    docker network create openclaw-net
fi

# Create monitoring directories if they don't exist
mkdir -p grafana-dashboards

# Start monitoring stack
echo "Starting monitoring stack..."
docker compose -f docker-compose.monitoring.yml up -d

echo ""
echo "Waiting for services to be ready..."
sleep 10

# Check service health
echo ""
echo "=== Service Status ==="
docker compose -f docker-compose.monitoring.yml ps

echo ""
echo "=== Monitoring Stack Deployed ==="
echo ""
echo "Access points:"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000 (admin/admin)"
echo "  Alertmanager: http://localhost:9093"
echo ""
echo "Next steps:"
echo "  1. Login to Grafana at http://localhost:3000"
echo "  2. Change admin password (Settings → Change Password)"
echo "  3. View OpenClaw dashboard (Dashboards → OpenClaw Overview)"
echo "  4. Configure email alerts in alertmanager.yml"
echo ""
echo "To stop monitoring:"
echo "  docker compose -f docker-compose.monitoring.yml down"
echo ""

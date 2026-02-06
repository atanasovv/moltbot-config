# OpenClaw Deployment Guide

Complete guide for building and deploying OpenClaw on remote Ubuntu server with Docker Hub.

## Table of Contents
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Initial Server Setup](#initial-server-setup)
- [Build and Push to Docker Hub](#build-and-push-to-docker-hub)
- [Deploy on Remote Server](#deploy-on-remote-server)
- [Monitoring Setup](#monitoring-setup)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Complete Deployment (First Time)

```bash
# 1. Setup remote server (one-time)
scp setup-ubuntu.sh vaki-lenovo:~
ssh vaki-lenovo 'chmod +x setup-ubuntu.sh && ./setup-ubuntu.sh'

# 2. Build and push image to Docker Hub
./build-remote.sh --push

# 3. Deploy on remote server from Docker Hub
ssh vaki-lenovo 'cd ~/openclaw && USE_DOCKERHUB=true ./deploy.sh'
```

### Update Existing Deployment

```bash
# Rebuild and push new image
./build-remote.sh --push --no-cache

# Pull and restart on remote
ssh vaki-lenovo 'cd ~/openclaw && docker compose pull && docker compose up -d'
```

---

## Prerequisites

### On Your Local Machine (macOS)

```bash
# 1. Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop

# 2. Setup SSH access to remote server
# Add to ~/.ssh/config:
cat >> ~/.ssh/config << 'EOF'
Host vaki-lenovo
    HostName 192.168.2.102  # Your server IP
    User vatanasov           # Your username
    IdentityFile ~/.ssh/id_rsa
    ForwardAgent yes
EOF

# 3. Test SSH connection
ssh vaki-lenovo 'echo "Connection successful"'
```

### On Remote Server (Ubuntu)

```bash
# Will be installed by setup-ubuntu.sh:
# - Docker (rootless mode)
# - gVisor runtime
# - Node.js 22.12+
# - UFW firewall
# - fail2ban
# - Tailscale VPN
```

---

## Initial Server Setup

### Step 1: Prepare Server

```bash
# Copy setup script to remote server
scp setup-ubuntu.sh vaki-lenovo:~

# Run setup script on remote
ssh vaki-lenovo 'chmod +x setup-ubuntu.sh && ./setup-ubuntu.sh'

# The script will:
# - Install Docker in rootless mode
# - Install gVisor runtime
# - Configure firewall (UFW)
# - Install fail2ban for SSH protection
# - Setup automatic security updates
# - Configure Tailscale VPN (optional)
```

### Step 2: Verify Setup

```bash
# SSH to server and verify
ssh vaki-lenovo

# Check Docker
docker --version
docker ps

# Check gVisor
docker run --runtime=runsc hello-world

# Check firewall
sudo ufw status

# Exit back to local machine
exit
```

---

## Build and Push to Docker Hub

### Step 1: Login to Docker Hub

```bash
# On remote server, login to Docker Hub
ssh vaki-lenovo 'docker login -u vladislav2502'
# Enter your Docker Hub password when prompted
```

### Step 2: Build on Remote Server

```bash
# From your local machine, trigger remote build
./build-remote.sh

# Options:
./build-remote.sh --push           # Build and push to Docker Hub
./build-remote.sh --no-cache       # Build without cache
./build-remote.sh --tag v1.0.0     # Use custom tag
./build-remote.sh --push --no-cache --tag latest  # All options
```

### What the build script does:

1. ✅ Tests SSH connection to `vaki-lenovo`
2. ✅ Verifies Docker is installed on remote
3. ✅ Creates remote directory (`~/openclaw`)
4. ✅ Syncs project files via rsync
5. ✅ Builds Docker image on remote server
6. ✅ Tags image as `vladislav2502/openclaw:secure`
7. ✅ Pushes to Docker Hub (if `--push` flag used)
8. ✅ Cleans up old images

### Alternative: Build Locally (macOS)

```bash
# Build on your local machine
docker build -t vladislav2502/openclaw:secure .

# Login to Docker Hub
docker login -u vladislav2502

# Push to Docker Hub
docker push vladislav2502/openclaw:secure
docker tag vladislav2502/openclaw:secure vladislav2502/openclaw:latest
docker push vladislav2502/openclaw:latest
```

---

## Deploy on Remote Server

### Method 1: Deploy from Docker Hub (Recommended)

```bash
# 1. Sync configuration files to remote
rsync -avz --exclude 'secrets/' \
  ./config/ ./docker-compose.yml ./deploy.sh ./init-secrets.sh \
  vaki-lenovo:~/openclaw/

# 2. Make scripts executable
ssh vaki-lenovo 'cd ~/openclaw && chmod +x *.sh'

# 3. Initialize secrets
ssh vaki-lenovo 'cd ~/openclaw && ./init-secrets.sh'

# 4. Deploy from Docker Hub
ssh vaki-lenovo 'cd ~/openclaw && USE_DOCKERHUB=true ./deploy.sh'
```

### Method 2: Deploy with Local Image

```bash
# If image was built on remote server
ssh vaki-lenovo 'cd ~/openclaw && ./deploy.sh'
```

### Deployment Script Actions:

1. ✅ Checks Docker is running
2. ✅ Initializes secrets (if not done)
3. ✅ Pulls image from Docker Hub OR builds locally
4. ✅ Creates directories (config, workspace, logs)
5. ✅ Starts Docker Compose services
6. ✅ Waits for health check
7. ✅ Optionally starts monitoring stack

---

## Initial Configuration

### Step 1: Initialize Secrets

```bash
# Run on remote server
ssh vaki-lenovo 'cd ~/openclaw && ./init-secrets.sh'
```

You'll be prompted for:
- **Anthropic API Key** (Claude) - Format: `sk-ant-api03-...`
- **OpenAI API Key** (GPT-4o/o1) - Format: `sk-proj-...`
- **Google API Key** (Gemini) - Format: `AIza...`
- **Telegram Bot Token** - Get from [@BotFather](https://t.me/botfather)

### Step 2: Configure OpenClaw

```bash
# Edit configuration
ssh vaki-lenovo 'cd ~/openclaw && nano config/openclaw.json'
```

Key settings:
```json
{
  "dmPolicy": "pairing",      // Require pairing for security
  "allowFrom": [],            // Add Telegram user IDs after pairing
  "model": {
    "primary": "anthropic/claude-sonnet-4-5",
    "fastModel": "google/gemini-2.0-flash",
    "reasoningModel": "openai/o1"
  },
  "cost": {
    "limits": {
      "daily": 100,           // Max $100/day
      "perUser": 50           // Max $50/user/day
    }
  }
}
```

### Step 3: Telegram Pairing

```bash
# 1. Start OpenClaw
ssh vaki-lenovo 'cd ~/openclaw && docker compose up -d'

# 2. Message your bot on Telegram
# Bot will respond with pairing code

# 3. View logs to get pairing code
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs -f openclaw'

# 4. Approve pairing and get user ID from logs

# 5. Add user ID to allowFrom in config/openclaw.json

# 6. Restart to apply
ssh vaki-lenovo 'cd ~/openclaw && docker compose restart openclaw'
```

---

## Monitoring Setup

### Deploy Monitoring Stack

```bash
# Start Prometheus, Grafana, Alertmanager
ssh vaki-lenovo 'cd ~/openclaw/monitoring && ./setup-monitoring.sh'
```

### Access Dashboards

```bash
# Setup SSH tunnel for secure access
ssh -L 3000:localhost:3000 -L 9090:localhost:9090 vaki-lenovo

# Then open in browser:
# - Grafana:     http://localhost:3000 (admin/admin)
# - Prometheus:  http://localhost:9090
```

### Configure Grafana

1. Login: `admin` / `admin` (change on first login)
2. Dashboard already provisioned: "OpenClaw Overview"
3. Setup email alerts in Alertmanager

---

## Daily Operations

### View Logs

```bash
# Real-time logs
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs -f openclaw'

# Last 100 lines
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs --tail=100 openclaw'

# Search logs
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs openclaw | grep ERROR'
```

### Check Status

```bash
# Container status
ssh vaki-lenovo 'cd ~/openclaw && docker compose ps'

# Health check
ssh vaki-lenovo 'docker inspect openclaw-gateway --format="{{.State.Health.Status}}"'

# Resource usage
ssh vaki-lenovo 'docker stats openclaw-gateway --no-stream'
```

### Restart Service

```bash
# Restart OpenClaw
ssh vaki-lenovo 'cd ~/openclaw && docker compose restart openclaw'

# Full restart (recreate containers)
ssh vaki-lenovo 'cd ~/openclaw && docker compose down && docker compose up -d'

# Update and restart
ssh vaki-lenovo 'cd ~/openclaw && docker compose pull && docker compose up -d'
```

### Stop Service

```bash
# Stop OpenClaw
ssh vaki-lenovo 'cd ~/openclaw && docker compose down'

# Stop with cleanup
ssh vaki-lenovo 'cd ~/openclaw && docker compose down -v'
```

---

## Secret Management

### Check Secret Expiry

```bash
ssh vaki-lenovo 'cd ~/openclaw && ./check-secret-expiry.sh'
```

### Rotate Secrets (90-day schedule)

```bash
# Rotate single secret
ssh vaki-lenovo 'cd ~/openclaw && ./rotate-secrets.sh --secret-name ANTHROPIC_API_KEY'

# Rotate all secrets
ssh vaki-lenovo 'cd ~/openclaw && ./rotate-secrets.sh --all'
```

### Backup Secrets

```bash
# Backup to local machine (encrypted)
ssh vaki-lenovo 'cd ~/openclaw && tar czf secrets-backup.tar.gz secrets/'
scp vaki-lenovo:~/openclaw/secrets-backup.tar.gz ./backups/

# Store securely (e.g., 1Password, encrypted USB)
```

---

## Update Workflow

### Update Configuration Only

```bash
# 1. Edit local config
nano config/openclaw.json

# 2. Sync to remote
rsync -avz config/openclaw.json vaki-lenovo:~/openclaw/config/

# 3. Restart
ssh vaki-lenovo 'cd ~/openclaw && docker compose restart openclaw'
```

### Update Docker Image

```bash
# 1. Rebuild and push
./build-remote.sh --push --no-cache

# 2. Pull on remote and restart
ssh vaki-lenovo 'cd ~/openclaw && docker compose pull && docker compose up -d'

# 3. Verify
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs -f openclaw'
```

### Update Dockerfile

```bash
# 1. Edit Dockerfile locally
nano Dockerfile

# 2. Rebuild and push
./build-remote.sh --push --no-cache

# 3. Deploy update
ssh vaki-lenovo 'cd ~/openclaw && docker compose pull && docker compose up -d'
```

---

## Troubleshooting

### Build Issues

#### Error: GID/UID already exists
**Solution:** Already fixed in Dockerfile with fallback logic

#### Error: Cannot connect to vaki-lenovo
```bash
# Check SSH config
cat ~/.ssh/config | grep -A 5 vaki-lenovo

# Test connection
ssh -v vaki-lenovo

# Check SSH key
ssh-add -l
```

#### Error: Docker not found on remote
```bash
# Re-run setup script
ssh vaki-lenovo 'cd ~ && ./setup-ubuntu.sh'
```

### Deployment Issues

#### Error: Permission denied
```bash
# Make scripts executable
ssh vaki-lenovo 'cd ~/openclaw && chmod +x *.sh'

# Fix ownership
ssh vaki-lenovo 'sudo chown -R $USER:$USER ~/openclaw'
```

#### Error: Container not starting
```bash
# Check logs
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs openclaw'

# Check secrets
ssh vaki-lenovo 'cd ~/openclaw && ls -la secrets/'

# Verify gVisor
ssh vaki-lenovo 'docker run --runtime=runsc hello-world'
```

#### Error: Port already in use
```bash
# Check what's using port 18789
ssh vaki-lenovo 'sudo lsof -i :18789'

# Kill process or change port in docker-compose.yml
```

### Runtime Issues

#### Bot not responding
```bash
# 1. Check container is running
ssh vaki-lenovo 'cd ~/openclaw && docker compose ps'

# 2. Check logs for errors
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs --tail=50 openclaw'

# 3. Verify Telegram token
ssh vaki-lenovo 'cat ~/openclaw/secrets/TELEGRAM_BOT_TOKEN'

# 4. Test webhook
curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo
```

#### API errors (401/403)
```bash
# Check API keys are valid
ssh vaki-lenovo 'cd ~/openclaw && cat secrets/ANTHROPIC_API_KEY'

# Test API key
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $(ssh vaki-lenovo 'cat ~/openclaw/secrets/ANTHROPIC_API_KEY')" \
  -H "anthropic-version: 2023-06-01"
```

#### High costs
```bash
# Check Grafana dashboard
ssh -L 3000:localhost:3000 vaki-lenovo
# Open http://localhost:3000

# Review logs for unusual activity
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs openclaw | grep -i "cost\|usage"'

# Lower limits in config/openclaw.json
```

### Recovery

#### Restore from backup
```bash
# 1. Stop service
ssh vaki-lenovo 'cd ~/openclaw && docker compose down'

# 2. Restore secrets
scp ./backups/secrets-backup.tar.gz vaki-lenovo:~/openclaw/
ssh vaki-lenovo 'cd ~/openclaw && tar xzf secrets-backup.tar.gz'

# 3. Restart
ssh vaki-lenovo 'cd ~/openclaw && docker compose up -d'
```

#### Complete reset
```bash
# 1. Stop everything
ssh vaki-lenovo 'cd ~/openclaw && docker compose down -v'

# 2. Remove data
ssh vaki-lenovo 'rm -rf ~/openclaw/workspace/* ~/openclaw/logs/*'

# 3. Reinitialize secrets
ssh vaki-lenovo 'cd ~/openclaw && ./init-secrets.sh'

# 4. Deploy fresh
ssh vaki-lenovo 'cd ~/openclaw && USE_DOCKERHUB=true ./deploy.sh'
```

---

## Command Reference

### Essential Commands

```bash
# Build and push image
./build-remote.sh --push

# Deploy from Docker Hub
ssh vaki-lenovo 'cd ~/openclaw && USE_DOCKERHUB=true ./deploy.sh'

# View logs
ssh vaki-lenovo 'cd ~/openclaw && docker compose logs -f openclaw'

# Check status
ssh vaki-lenovo 'cd ~/openclaw && docker compose ps'

# Restart
ssh vaki-lenovo 'cd ~/openclaw && docker compose restart openclaw'

# Stop
ssh vaki-lenovo 'cd ~/openclaw && docker compose down'

# Update
./build-remote.sh --push && \
  ssh vaki-lenovo 'cd ~/openclaw && docker compose pull && docker compose up -d'
```

### File Sync Commands

```bash
# Sync all configs to remote
rsync -avz --exclude 'secrets/' --exclude '.git/' \
  ./ vaki-lenovo:~/openclaw/

# Sync single file
rsync -avz config/openclaw.json vaki-lenovo:~/openclaw/config/

# Download logs from remote
rsync -avz vaki-lenovo:~/openclaw/logs/ ./logs-backup/
```

---

## Security Checklist

### Before First Deployment

- [ ] Run `setup-ubuntu.sh` on remote server
- [ ] Enable UFW firewall
- [ ] Configure fail2ban
- [ ] Setup Tailscale VPN (optional but recommended)
- [ ] Generate strong API keys
- [ ] Enable 2FA on all API provider accounts
- [ ] Use pairing mode (`dmPolicy: "pairing"`)
- [ ] Set cost limits in config

### After Deployment

- [ ] Change Grafana admin password
- [ ] Setup email alerts
- [ ] Configure secret rotation schedule
- [ ] Review and restrict `allowFrom` list
- [ ] Enable monitoring dashboards
- [ ] Test backup and restore procedure
- [ ] Document emergency contacts

### Regular Maintenance

- [ ] Weekly: Review logs for suspicious activity
- [ ] Weekly: Check Grafana for cost anomalies
- [ ] Monthly: Review and update allowlist
- [ ] Monthly: Check system updates
- [ ] Quarterly: Rotate all secrets
- [ ] Quarterly: Test disaster recovery

---

## Support

For issues or questions:

1. Check logs: `docker compose logs openclaw`
2. Review [SECURITY.md](./SECURITY.md) for security best practices
3. Check [README.md](./README.md) for detailed configuration
4. Search GitHub issues: [OpenClaw Issues](https://github.com/openclaw/openclaw/issues)

---

## Quick Reference Card

Print and keep handy:

```
┌─────────────────────────────────────────────────────────────┐
│ OPENCLAW QUICK REFERENCE                                    │
├─────────────────────────────────────────────────────────────┤
│ Remote Server: vaki-lenovo (192.168.2.102)                 │
│ User: vatanasov                                             │
│ Path: ~/openclaw                                            │
│ Docker Hub: vladislav2502/openclaw                          │
├─────────────────────────────────────────────────────────────┤
│ BUILD & PUSH                                                │
│   ./build-remote.sh --push                                  │
│                                                             │
│ DEPLOY                                                      │
│   ssh vaki-lenovo 'cd ~/openclaw && \                       │
│     USE_DOCKERHUB=true ./deploy.sh'                         │
│                                                             │
│ LOGS                                                        │
│   ssh vaki-lenovo 'cd ~/openclaw && \                       │
│     docker compose logs -f openclaw'                        │
│                                                             │
│ RESTART                                                     │
│   ssh vaki-lenovo 'cd ~/openclaw && \                       │
│     docker compose restart openclaw'                        │
│                                                             │
│ UPDATE                                                      │
│   ./build-remote.sh --push && \                             │
│   ssh vaki-lenovo 'cd ~/openclaw && \                       │
│     docker compose pull && docker compose up -d'            │
│                                                             │
│ MONITORING                                                  │
│   ssh -L 3000:localhost:3000 vaki-lenovo                    │
│   http://localhost:3000                                     │
└─────────────────────────────────────────────────────────────┘
```

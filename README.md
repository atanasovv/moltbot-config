# OpenClaw - Secure Multi-LLM Personal AI Assistant

Production-ready deployment configuration for OpenClaw with enterprise-grade security, multi-LLM routing, and comprehensive monitoring.

## 🎯 Overview

This repository provides a complete, security-hardened deployment solution for OpenClaw featuring:

- **Multi-LLM Intelligence**: Kimi-k2 (primary, 128K context), Claude 3.5 Sonnet, Gemini 2.0 Flash (speed/vision), OpenAI o1 (reasoning)
- **Security First**: Docker rootless mode, gVisor isolation, read-only filesystems, capability dropping
- **Zero-Trust Secrets**: Docker Secrets with 90-day rotation, encrypted storage, expiry tracking
- **Telegram Integration**: Pairing-mode authentication, webhook support, mention-based group control
- **Cost Control**: Real-time tracking, budget alerts, per-model analytics
- **Production Monitoring**: Prometheus metrics, Grafana dashboards, Alertmanager notifications

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Options](#deployment-options)
  - [Ubuntu Server (Production)](#ubuntu-server-production)
  - [macOS (Development)](#macos-development)
- [Configuration](#configuration)
- [Security](#security)
- [Monitoring](#monitoring)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## 📚 Additional Guides

- **[SKIP-STEPS-GUIDE.md](SKIP-STEPS-GUIDE.md)** - How to skip setup steps and minimal installation
- **[KIMI-K2-INTEGRATION.md](KIMI-K2-INTEGRATION.md)** - Kimi-k2 model integration details
- **[QUICK-REFERENCE.txt](QUICK-REFERENCE.txt)** - Command cheat sheet and quick reference
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Comprehensive deployment guide
- **[SECURITY.md](SECURITY.md)** - Security hardening and best practices

## ✅ Prerequisites

### Ubuntu Server
- Ubuntu 22.04 LTS or 24.04 LTS
- 2GB RAM minimum (4GB recommended)
- 2 CPU cores (4 recommended)
- 20GB disk space
- Root or sudo access

### macOS
- macOS Sonoma (14.x) or Sequoia (15.x)
- 4GB RAM minimum
- Docker Desktop installed (or script will install)
- Administrator access

### API Keys Required
- **Moonshot API Key** - Get from [platform.moonshot.cn](https://platform.moonshot.cn/console/api-keys) (Primary - Kimi-k2)
- **Anthropic API Key** - Get from [console.anthropic.com](https://console.anthropic.com/settings/keys)
- **OpenAI API Key** - Get from [platform.openai.com](https://platform.openai.com/api-keys)
- **Google API Key** - Get from [aistudio.google.com](https://aistudio.google.com/app/apikey)
- **Telegram Bot Token** - Get from [@BotFather](https://t.me/BotFather) on Telegram

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone <your-repo-url>
cd moltbot-config
chmod +x *.sh
```

### 2. Run Setup Script

**Ubuntu:**
```bash
./setup-ubuntu.sh
```

**macOS:**
```bash
./setup-macos.sh
```

### 3. Initialize Secrets

```bash
./init-secrets.sh
```

Follow the prompts to enter your API keys securely.

### 4. Build Docker Image

```bash
docker build -t openclaw:secure .
```

### 5. Start OpenClaw

```bash
docker compose up -d
```

### 6. Verify Deployment

```bash
docker compose ps
docker compose logs -f openclaw
```

### 7. Configure Telegram

1. Message your bot on Telegram
2. Approve the pairing code when prompted
3. Start chatting!

## 🏗️ Deployment Options

### Ubuntu Server (Production)

The Ubuntu setup script (`setup-ubuntu.sh`) provides a complete production environment:

#### What Gets Installed

- **Docker Engine** (rootless mode for security)
- **gVisor Runtime** (kernel-level container isolation)
- **Node.js 22.12.0+** (CVE-patched version)
- **UFW Firewall** (SSH + Tailscale only)
- **fail2ban** (SSH brute-force protection)
- **AppArmor** (Mandatory Access Control)
- **Unattended Upgrades** (automatic security patches)
- **Tailscale VPN** (secure remote access)

#### Post-Installation

After running `setup-ubuntu.sh`:

```bash
# Check installation status
~/.openclaw/check-setup.sh

# Connect to Tailscale (optional but recommended)
sudo tailscale up

# Verify Docker rootless mode
docker context ls
systemctl --user status docker.service

# Test gVisor runtime
docker run --rm --runtime=runsc hello-world
```

#### Firewall Configuration

By default, only these ports are open:
- **22/tcp** - SSH
- **41641/udp** - Tailscale

OpenClaw gateway binds to `localhost:18789` for security. Access via:
- SSH tunnel: `ssh -L 18789:localhost:18789 user@server`
- Tailscale: Access directly via Tailscale IP

### macOS (Development)

The macOS setup script (`setup-macos.sh`) provides a development environment:

#### What Gets Installed

- **Homebrew** (package manager)
- **Docker Desktop** (includes gVisor support)
- **Node.js 22+**
- **Tailscale**
- **Development Tools** (jq, git, curl, wget, tree)
- **git-crypt** (encrypted secret storage)

#### Post-Installation

```bash
# Check setup
~/.openclaw/check-setup.sh

# Load environment variables
source ~/.openclaw/setup-env.sh

# Quick start
cd ~/.openclaw
./quick-start.sh
```

#### Using git-crypt for Secrets

```bash
cd ~/.openclaw
git init
git-crypt init
git-crypt add-gpg-user YOUR_GPG_KEY_ID

# Secrets in secrets/ directory will be encrypted automatically
git add .
git commit -m "Initial commit with encrypted secrets"
```

## ⚙️ Configuration

### OpenClaw Configuration

Main configuration file: `config/openclaw.json`

#### Key Settings

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5"
      }
    }
  },
  
  "channels": {
    "telegram": {
      "dmPolicy": "pairing",
      "allowFrom": [],  // Add approved user IDs here
      "groups": {
        "*": {
          "requireMention": true
        }
      }
    }
  },
  
  "security": {
    "sandbox": {
      "enabled": true,
      "runtime": "runsc"
    },
    "rateLimit": {
      "perUser": {
        "messages": 50,
        "window": "1h"
      }
    }
  },
  
  "cost": {
    "limits": {
      "daily": 100,
      "monthly": 1000
    }
  }
}
```

### Adding Telegram Users

After a user messages your bot, you'll receive a pairing code. To approve:

1. Check the pairing request in logs:
   ```bash
   docker compose logs openclaw | grep -i pairing
   ```

2. Add the user ID to `allowFrom`:
   ```bash
   # Edit config/openclaw.json
   "channels": {
     "telegram": {
       "allowFrom": ["123456789"]  // User's Telegram ID
     }
   }
   ```

3. Restart OpenClaw:
   ```bash
   docker compose restart openclaw
   ```

### Environment Variables

Create `.env` file for Docker Compose overrides:

```bash
# Optional overrides
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
OPENCLAW_LOG_DIR=./logs
```

## 🔐 Security

### Security Architecture

```
┌─────────────────────────────────────────┐
│          Internet / Telegram            │
└──────────────┬──────────────────────────┘
               │
        ┌──────▼──────┐
        │ UFW Firewall│
        │ (SSH only)  │
        └──────┬──────┘
               │
    ┌──────────▼───────────┐
    │ Docker Rootless Mode │
    │   (Non-root user)    │
    └──────────┬───────────┘
               │
        ┌──────▼──────┐
        │gVisor Runtime│
        │  (runsc)     │
        └──────┬──────┘
               │
    ┌──────────▼──────────┐
    │  OpenClaw Container │
    │ • Read-only FS      │
    │ • No capabilities   │
    │ • User namespace    │
    │ • Resource limits   │
    └─────────────────────┘
```

### Security Features

#### 1. Container Isolation

- **Rootless Docker**: Containers run as non-root user (UID 1000)
- **gVisor**: Kernel-level syscall interception and filtering
- **Read-only Filesystem**: Immutable container runtime
- **Capability Dropping**: All Linux capabilities dropped, only `NET_BIND_SERVICE` added
- **No New Privileges**: Prevents privilege escalation
- **User Namespace**: Additional UID/GID remapping

#### 2. Secret Management

- **Docker Secrets**: Secrets mounted at `/run/secrets` (memory-backed)
- **90-Day Rotation**: Automated expiry tracking
- **Encrypted Storage**: git-crypt for version control (macOS)
- **Zero Git Commits**: `.gitignore` prevents accidental commits
- **Minimal Permissions**: Secrets have `600` permissions

#### 3. Network Security

- **Localhost Binding**: Gateway binds to `127.0.0.1` only
- **UFW Firewall**: Default deny, explicit allow for SSH/Tailscale
- **fail2ban**: Automatic SSH brute-force protection
- **Tailscale VPN**: Encrypted mesh network for remote access
- **Isolated Network**: Docker bridge network for containers

#### 4. Application Security

- **Pairing Mode**: Telegram users must be explicitly approved
- **Rate Limiting**: Per-user and global message limits
- **Content Filtering**: Configurable input/output filters
- **PII Redaction**: Sensitive data redaction in logs
- **Audit Logging**: Security events logged to monitoring

### Secret Rotation

#### Check Secret Expiry

```bash
./check-secret-expiry.sh
```

Output:
```
Secret Rotation Status
======================
Created: 2026-02-06T10:00:00Z
Rotate by: 2026-05-07T10:00:00Z
Days remaining: 89

✓ Secrets are current (89 days remaining)
```

#### Rotate All Secrets

```bash
./rotate-secrets.sh --all
```

#### Rotate Specific Secret

```bash
./rotate-secrets.sh --secret-name anthropic_api_key
```

The rotation script performs:
1. Backs up current secret
2. Validates new secret format
3. Atomically updates secret file
4. Updates expiry metadata
5. Gracefully restarts OpenClaw (zero-downtime)

### Automated Expiry Checks

Add to crontab for weekly checks:

```bash
crontab -e
```

Add line:
```
0 9 * * 1 cd /path/to/moltbot-config && ./check-secret-expiry.sh
```

## 📊 Monitoring

### Start Monitoring Stack

```bash
docker compose -f monitoring/docker-compose.monitoring.yml up -d
```

### Access Dashboards

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)
- **Alertmanager**: http://localhost:9093

### Grafana Dashboards

Login to Grafana and navigate to **Dashboards → OpenClaw - LLM Cost & Performance Overview**

**Key Metrics Tracked:**

1. **Cost Metrics**
   - Daily LLM costs (USD)
   - Monthly LLM costs (USD)
   - Cost by model breakdown
   - Cost per user

2. **Performance Metrics**
   - Request latency (p50, p95, p99)
   - Token usage by model
   - Error rates
   - Rate limit hits

3. **Security Metrics**
   - Failed authentication attempts
   - Unauthorized access attempts
   - Secret expiry countdown
   - Suspicious activity patterns

4. **Availability Metrics**
   - Service uptime
   - Container restarts
   - Memory usage
   - CPU usage

### Alerts

Alerts are configured in `monitoring/alert-rules.yml`:

- **Daily cost >$80**: Warning
- **Daily cost >$100**: Critical
- **Failed auth >5/min**: Warning
- **Secrets expire <7 days**: Warning
- **High latency (>30s)**: Warning
- **Service down >2min**: Critical

### Configure Email Alerts

Edit `monitoring/alertmanager.yml`:

```yaml
global:
  smtp_from: 'your-email@example.com'
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'your-email@example.com'
  smtp_auth_password: 'your-app-password'

receivers:
  - name: 'critical'
    email_configs:
      - to: 'admin@example.com'
```

Restart Alertmanager:
```bash
docker compose -f monitoring/docker-compose.monitoring.yml restart alertmanager
```

## 🔧 Maintenance

### Daily Operations

#### View Logs

```bash
# Real-time logs
docker compose logs -f openclaw

# Last 100 lines
docker compose logs --tail=100 openclaw

# Errors only
docker compose logs openclaw | grep -i error
```

#### Check Status

```bash
# Container status
docker compose ps

# Resource usage
docker stats openclaw-gateway

# Health check
curl http://localhost:18789/health
```

#### Restart Service

```bash
# Graceful restart
docker compose restart openclaw

# Force recreate
docker compose up -d --force-recreate openclaw
```

### Weekly Tasks

1. **Check secret expiry**: `./check-secret-expiry.sh`
2. **Review cost metrics**: Check Grafana dashboard
3. **Check for updates**: 
   ```bash
   docker pull openclaw:latest
   docker compose up -d
   ```

### Monthly Tasks

1. **Review security logs**: Check Prometheus for security events
2. **Backup configuration**:
   ```bash
   tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz config/ workspace/
   ```
3. **Update system packages**:
   ```bash
   # Ubuntu (automatic with unattended-upgrades)
   sudo apt update && sudo apt upgrade
   
   # macOS
   brew update && brew upgrade
   ```

### Quarterly Tasks

1. **Rotate secrets**: `./rotate-secrets.sh --all`
2. **Review and optimize costs**: Analyze Grafana cost dashboard
3. **Security audit**: Review access logs, update allowlists
4. **Test disaster recovery**: Restore from backup

## 🩺 Troubleshooting

### OpenClaw Won't Start

```bash
# Check logs for errors
docker compose logs openclaw

# Common issues:
# 1. Secrets not initialized
./init-secrets.sh

# 2. Configuration errors
docker compose config

# 3. Port already in use
sudo lsof -i :18789
# Kill process or change port in docker-compose.yml

# 4. Permission issues
sudo chown -R 1000:1000 config/ workspace/ logs/
```

### Telegram Not Connecting

```bash
# Verify bot token
cat secrets/telegram_bot_token.txt

# Check Telegram connection in logs
docker compose logs openclaw | grep -i telegram

# Test bot token manually
curl "https://api.telegram.org/bot$(cat secrets/telegram_bot_token.txt)/getMe"

# Restart with clean state
docker compose down
docker compose up -d
```

### High Memory Usage

```bash
# Check current usage
docker stats openclaw-gateway

# Increase memory limit in docker-compose.yml
# limits:
#   memory: 4096M  # Increase from 2048M

# Restart with new limits
docker compose up -d --force-recreate
```

### gVisor Runtime Not Working

```bash
# Check if gVisor is installed
~/bin/runsc --version

# Test gVisor
docker run --rm --runtime=runsc hello-world

# If failing, fall back to default runtime
# Edit docker-compose.yml: runtime: runc

# Restart
docker compose up -d --force-recreate
```

### Cost Alerts Firing

```bash
# Check current costs in Grafana
# Navigate to: http://localhost:3000

# Reduce usage:
# 1. Lower rate limits in config/openclaw.json
# 2. Use cheaper models (Gemini Flash)
# 3. Implement request filtering

# Update cost limits
# Edit config/openclaw.json:
"cost": {
  "limits": {
    "daily": 50  # Reduce from 100
  }
}
```

### Pairing Not Working

```bash
# Check pairing policy
grep -A5 '"telegram"' config/openclaw.json

# Verify dmPolicy is "pairing"
# Check logs for pairing codes
docker compose logs openclaw | grep -i pairing

# Manual user approval
# Edit config/openclaw.json and add user ID to allowFrom
```

## 📁 Directory Structure

```
moltbot-config/
├── setup-ubuntu.sh           # Ubuntu server provisioning
├── setup-macos.sh            # macOS setup script
├── init-secrets.sh           # Initialize Docker secrets
├── rotate-secrets.sh         # Rotate secrets (90-day)
├── check-secret-expiry.sh    # Check expiry status
├── Dockerfile                # Security-hardened container
├── docker-compose.yml        # Main service orchestration
├── config/
│   └── openclaw.json         # OpenClaw configuration
├── workspace/                # Bot workspace (persistent)
├── logs/                     # Application logs
├── secrets/                  # Docker secrets (gitignored)
│   ├── anthropic_api_key.txt
│   ├── openai_api_key.txt
│   ├── google_api_key.txt
│   ├── telegram_bot_token.txt
│   └── .metadata.json        # Rotation tracking
└── monitoring/
    ├── docker-compose.monitoring.yml
    ├── prometheus.yml
    ├── alert-rules.yml
    ├── alertmanager.yml
    ├── grafana-datasources.yml
    └── grafana-dashboards/
        └── openclaw-overview.json
```

## 🎓 Best Practices

### Security

1. **Never commit secrets to git**
2. **Rotate secrets every 90 days** (automated tracking)
3. **Use Tailscale** for remote access (not public IPs)
4. **Enable 2FA** on all API provider accounts
5. **Review access logs** weekly
6. **Keep systems updated** (automatic on Ubuntu)

### Cost Management

1. **Set conservative limits** initially
2. **Monitor daily costs** in Grafana
3. **Use Gemini Flash** for simple tasks (cheaper)
4. **Implement rate limiting** per user
5. **Configure cost alerts** at 80% threshold

### Operations

1. **Backup configuration** weekly
2. **Test disaster recovery** quarterly
3. **Use version control** for config changes
4. **Document customizations**
5. **Keep monitoring stack running**

## 📚 Additional Resources

- **OpenClaw Documentation**: https://docs.openclaw.ai
- **OpenClaw GitHub**: https://github.com/openclaw/openclaw
- **Docker Security Guide**: https://docs.docker.com/engine/security/
- **gVisor Documentation**: https://gvisor.dev/docs/
- **Prometheus Best Practices**: https://prometheus.io/docs/practices/

## 🤝 Support

For issues and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review OpenClaw documentation
3. Check container logs: `docker compose logs openclaw`
4. Join OpenClaw Discord: https://discord.com/invite/clawd

## 📝 License

This configuration is provided as-is for use with OpenClaw. See OpenClaw license for the core software.

---

**Security Note**: This configuration implements defense-in-depth security practices. However, security is a continuous process. Always review logs, update systems, and follow security best practices for your specific environment.

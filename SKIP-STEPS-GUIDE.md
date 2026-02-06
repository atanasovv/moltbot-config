# Skip Setup Steps Guide

This guide shows you how to skip steps in the setup process when you already have prerequisites installed or want a minimal setup.

## 🚀 Quick Skip Options

### Option 1: Skip Individual Prerequisites (Recommended)

The setup scripts are **already idempotent** - they detect existing installations and skip them automatically:

```bash
# Ubuntu setup - automatically skips existing components
./setup-ubuntu.sh

# macOS setup - automatically skips existing components  
./setup-macos.sh
```

The scripts will show warnings like:
```
[WARN] Docker already installed: Docker version 25.0.0
[WARN] Node.js v22.12.0 already installed
[INFO] Skipping installation...
```

### Option 2: Skip Entire Setup Scripts

If you **already have** all prerequisites (Docker, Node.js, etc.), skip directly to deployment:

```bash
# 1. Initialize secrets only
./init-secrets.sh

# 2. Deploy OpenClaw
./deploy.sh
```

### Option 3: Skip Optional Secrets

If you don't want to use all LLM providers, you can:

#### A. Comment Out Models in Configuration

Edit `config/openclaw.json` and remove unwanted providers:

```json
{
  "models": {
    "providers": {
      "anthropic": { ... },
      // Remove providers you don't need:
      // "openai": { ... },
      // "google": { ... },
      "moonshot": { ... }
    }
  }
}
```

#### B. Provide Dummy Secrets

For secrets you won't use, provide dummy values during init:

```bash
./init-secrets.sh

# When prompted for unused keys, enter dummy values:
# Anthropic: sk-ant-dummy123... (if not using)
# OpenAI: sk-dummy123... (if not using)
# Google: AIzadummy123... (if not using)
# Moonshot: sk-dummy123... (if not using - your primary choice)
# Telegram: <your real token>
```

**Note**: Docker Compose requires all secrets to exist, even if unused.

### Option 4: Minimal Setup (Kimi-k2 Only)

For **Kimi-k2 only** deployment:

#### Step 1: Install Docker

**Ubuntu:**
```bash
# Install Docker only
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

**macOS:**
```bash
# Install Docker Desktop
brew install --cask docker
open -a Docker
```

#### Step 2: Create Minimal Directory Structure

```bash
mkdir -p ~/.openclaw/{config,workspace,logs,secrets}
cd ~/.openclaw
```

#### Step 3: Get Required Files

```bash
# Clone just the config files you need
git clone https://github.com/atanasovv/moltbot-config.git temp
cp temp/config/openclaw.json config/
cp temp/docker-compose.yml .
cp temp/Dockerfile .
cp temp/init-secrets.sh .
cp temp/deploy.sh .
rm -rf temp
```

#### Step 4: Configure for Kimi-k2

Edit `config/openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "moonshot/kimi-k2",  // Use Kimi-k2 as primary
        "thinking": {
          "enabled": true,
          "model": "moonshot/kimi-k2"
        }
      }
    }
  },
  
  "models": {
    "providers": {
      "moonshot": {
        "apiKey": "/run/secrets/moonshot_api_key",
        "baseURL": "https://api.moonshot.cn/v1",
        "models": {
          "kimi-k2": {
            "id": "moonshot-v1-128k",
            "maxTokens": 128000,
            "reasoning": true,
            "contextWindow": 128000
          }
        }
      }
    }
  }
}
```

#### Step 5: Create Dummy Secrets

Since Docker Compose requires all secrets, create dummy files:

```bash
mkdir -p secrets
chmod 700 secrets

# Create dummy secrets for unused providers
echo "sk-ant-dummy-not-used-anthropic-key-placeholder-value-00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > secrets/anthropic_api_key.txt
echo "sk-dummy-not-used-openai-key-12345" > secrets/openai_api_key.txt
echo "AIzadummy-not-used-google-key-1234567890" > secrets/google_api_key.txt

# Add your REAL Moonshot and Telegram keys
echo "sk-your-real-moonshot-key-here" > secrets/moonshot_api_key.txt
echo "123456789:your-real-telegram-token-here" > secrets/telegram_bot_token.txt

# Set permissions
chmod 600 secrets/*.txt
```

#### Step 6: Deploy

```bash
./deploy.sh
```

## 📋 Component Dependencies

Here's what you can skip based on your needs:

| Component | Required For | Can Skip If |
|-----------|-------------|-------------|
| Docker | Running containers | Never (core requirement) |
| gVisor | Enhanced security | Don't need kernel isolation |
| Node.js | Local development | Only using Docker |
| UFW Firewall | Ubuntu server security | Using cloud firewall |
| fail2ban | SSH protection | Not exposing SSH publicly |
| Tailscale | VPN access | Using other VPN/direct access |
| Prometheus/Grafana | Monitoring | Don't need metrics |
| git-crypt | Secret encryption in Git | Not storing secrets in Git |

## ⚙️ Customize Setup Scripts

### Skip Specific Steps in setup-ubuntu.sh

Edit `setup-ubuntu.sh` and comment out sections you don't need:

```bash
# Skip gVisor installation
# Uncomment this section to skip:
# log_info "Step 5/10: Installing gVisor..."
# ... (comment out entire section)

# Skip fail2ban
# Uncomment this section to skip:
# log_info "Step 7/10: Configuring fail2ban..."
# ... (comment out entire section)

# Skip Tailscale
# Uncomment this section to skip:
# log_info "Step 10/10: Installing Tailscale..."
# ... (comment out entire section)
```

### Skip Docker Rootless Mode

If you want to use rootful Docker:

Edit `docker-compose.yml` and remove the `user` line:

```yaml
services:
  openclaw:
    # Comment out or remove this line:
    # user: "1000:1000"
```

### Skip gVisor Runtime

If you don't need gVisor sandbox:

Edit `docker-compose.yml`:

```yaml
services:
  openclaw:
    # Comment out or change to 'runc':
    # runtime: runsc
    runtime: runc  # Standard Docker runtime
```

## 🔧 Environment-Specific Shortcuts

### Development (Local Machine)

Skip production security for faster iteration:

```bash
# Minimal dev setup
docker compose up -d
# No gVisor, no rootless, no firewall
```

### Production (Remote Server)

Run full security setup:

```bash
# Full production setup
./setup-ubuntu.sh
# All security features enabled
```

## 🎯 Common Scenarios

### "I already have Docker Desktop"

```bash
# Skip setup scripts entirely
./init-secrets.sh
./deploy.sh
```

### "I only want Kimi-k2 model"

See **Option 4: Minimal Setup (Kimi-k2 Only)** above.

### "I'm testing locally, don't need security"

```bash
# Edit docker-compose.yml:
# - Remove: runtime: runsc
# - Remove: user: "1000:1000"
# - Remove: security_opt

./deploy.sh
```

### "I need to re-run setup but keep existing Docker"

The scripts already handle this! Just run:

```bash
./setup-ubuntu.sh
# Will warn about existing Docker and skip it
```

## ⚠️ Important Notes

1. **Docker Secrets Requirement**: Even if you don't use a provider, you must create a dummy secret file because `docker-compose.yml` references it.

2. **Model Configuration**: After skipping providers, update `config/openclaw.json` to use only available models.

3. **Security Trade-offs**: Skipping security features (gVisor, rootless, firewall) is fine for development but **NOT recommended for production**.

4. **Idempotent Scripts**: The setup scripts are designed to be run multiple times safely - they check for existing installations.

## 🚨 Troubleshooting Skipped Steps

### "Error: secret 'anthropic_api_key' not found"

Create a dummy secret file:

```bash
echo "sk-ant-dummy-key-00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > secrets/anthropic_api_key.txt
chmod 600 secrets/anthropic_api_key.txt
```

### "gVisor runtime not found"

Either:
- Run `./setup-ubuntu.sh` to install gVisor, or
- Edit `docker-compose.yml` and change `runtime: runsc` to `runtime: runc`

### "Permission denied" errors

If you skipped rootless Docker setup, add yourself to docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## 📚 Further Reading

- **Full Setup**: See `README.md` for complete installation
- **Security**: See `SECURITY.md` for hardening details
- **Deployment**: See `DEPLOYMENT.md` for production deployment
- **Configuration**: See `config/openclaw.json` for all options

#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw macOS Setup Script
# 
# This script installs and configures a macOS development environment for OpenClaw:
# - Homebrew package manager
# - Docker Desktop
# - Node.js 22.12.0+
# - Tailscale for secure remote access
# - Service user configuration (optional)
# - Development dependencies
#
# Tested on: macOS Sonoma (14.x), macOS Sequoia (15.x)
# Requires: Administrator privileges
################################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script is designed for macOS only"
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion)
log_info "Detected macOS ${MACOS_VERSION}"

# Configuration
OPENCLAW_USER="${USER}"
OPENCLAW_HOME="${HOME}"
OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"
NODE_VERSION="22"

################################################################################
# 1. Install Homebrew
################################################################################
log_step "Step 1/7: Installing Homebrew..."

if ! command -v brew &> /dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        
        # Add to shell profile if not already there
        if ! grep -q "eval.*homebrew.*shellenv" "${OPENCLAW_HOME}/.zshrc" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${OPENCLAW_HOME}/.zshrc"
        fi
    fi
    
    log_info "Homebrew installed"
else
    log_info "Homebrew already installed"
    brew update
fi

################################################################################
# 2. Install Docker Desktop
################################################################################
log_step "Step 2/7: Installing Docker Desktop..."

if ! command -v docker &> /dev/null; then
    log_info "Installing Docker Desktop via Homebrew..."
    brew install --cask docker
    
    log_warn "Docker Desktop installed. Please:"
    log_warn "  1. Open Docker Desktop from Applications"
    log_warn "  2. Complete the initial setup"
    log_warn "  3. Ensure Docker is running (whale icon in menu bar)"
    log_warn ""
    read -p "Press Enter after Docker Desktop is running..."
    
    # Wait for Docker to be ready
    log_info "Waiting for Docker to be ready..."
    for i in {1..30}; do
        if docker ps &>/dev/null; then
            log_info "Docker is ready"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
else
    log_info "Docker already installed"
    
    if docker ps &>/dev/null; then
        log_info "Docker is running"
    else
        log_warn "Docker is installed but not running. Please start Docker Desktop."
        open -a Docker
        read -p "Press Enter after Docker Desktop is running..."
    fi
fi

# Verify Docker installation
docker --version
docker compose version

################################################################################
# 3. Configure Docker Resources (Recommended Settings)
################################################################################
log_step "Step 3/7: Checking Docker resource allocation..."

log_info "Recommended Docker Desktop settings for OpenClaw:"
echo "  - CPUs: 4 (minimum 2)"
echo "  - Memory: 4GB (minimum 2GB)"
echo "  - Disk: 64GB"
echo ""
log_info "Configure via: Docker Desktop → Settings → Resources"

################################################################################
# 4. Install Node.js 22.12.0+
################################################################################
log_step "Step 4/7: Installing Node.js ${NODE_VERSION}..."

if command -v node &> /dev/null; then
    CURRENT_NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "${CURRENT_NODE_VERSION}" -ge "${NODE_VERSION}" ]]; then
        log_info "Node.js $(node --version) already installed"
    else
        log_warn "Upgrading Node.js from v${CURRENT_NODE_VERSION} to v${NODE_VERSION}..."
        brew upgrade node || brew install node@${NODE_VERSION}
    fi
else
    log_info "Installing Node.js..."
    brew install node@${NODE_VERSION}
    
    # Link the specific version
    brew link node@${NODE_VERSION}
fi

# Verify Node.js installation
node --version
npm --version

# Install pnpm globally
if ! command -v pnpm &> /dev/null; then
    log_info "Installing pnpm..."
    npm install -g pnpm
fi

pnpm --version

################################################################################
# 5. Install Tailscale
################################################################################
log_step "Step 5/7: Installing Tailscale..."

if ! command -v tailscale &> /dev/null; then
    log_info "Installing Tailscale..."
    brew install --cask tailscale
    
    log_info "Tailscale installed. To connect:"
    log_info "  1. Open Tailscale from Applications"
    log_info "  2. Sign in with your Tailscale account"
    log_info "  3. Or run: open -a Tailscale"
else
    log_info "Tailscale already installed"
    
    if pgrep -x "Tailscale" > /dev/null; then
        log_info "Tailscale is running"
    else
        log_warn "Tailscale is installed but not running"
        log_info "Opening Tailscale..."
        open -a Tailscale || true
    fi
fi

################################################################################
# 6. Install Development Tools
################################################################################
log_step "Step 6/7: Installing development tools..."

# Install useful development tools
TOOLS=(
    "jq"          # JSON processor
    "git"         # Version control
    "curl"        # HTTP client
    "wget"        # File downloader
    "tree"        # Directory structure viewer
)

for tool in "${TOOLS[@]}"; do
    if ! command -v "${tool}" &> /dev/null; then
        log_info "Installing ${tool}..."
        brew install "${tool}"
    else
        log_info "${tool} already installed"
    fi
done

################################################################################
# 7. Setup OpenClaw Directory Structure
################################################################################
log_step "Step 7/7: Setting up OpenClaw directories..."

mkdir -p "${OPENCLAW_DIR}"/{config,workspace,secrets,backups,logs}
chmod 700 "${OPENCLAW_DIR}/secrets"

log_info "Directory structure created:"
tree -L 2 "${OPENCLAW_DIR}" 2>/dev/null || ls -la "${OPENCLAW_DIR}"

################################################################################
# Create Helper Scripts
################################################################################
log_info "Creating helper scripts..."

# Check setup status script
cat > "${OPENCLAW_DIR}/check-setup.sh" << 'EOF'
#!/bin/bash
echo "=== OpenClaw macOS Setup Status ==="
echo ""
echo "Docker Desktop:"
docker version --format 'Version: {{.Server.Version}}' 2>/dev/null || echo "Not running"
docker info 2>/dev/null | grep -E "CPUs:|Total Memory:|Operating System:" || true
echo ""
echo "Docker Compose:"
docker compose version
echo ""
echo "Node.js:"
node --version
echo ""
echo "npm:"
npm --version
echo ""
echo "pnpm:"
pnpm --version
echo ""
echo "Tailscale:"
if pgrep -x "Tailscale" > /dev/null; then
    echo "Status: Running"
else
    echo "Status: Not running"
fi
echo ""
echo "OpenClaw directories:"
ls -la ~/.openclaw/ 2>/dev/null || echo "Not created yet"
echo ""
echo "=== Setup Complete ==="
EOF
chmod +x "${OPENCLAW_DIR}/check-setup.sh"

# Quick start script
cat > "${OPENCLAW_DIR}/quick-start.sh" << 'EOF'
#!/bin/bash
set -e

echo "=== OpenClaw Quick Start ==="
echo ""

# Check if Docker is running
if ! docker ps &>/dev/null; then
    echo "Error: Docker is not running. Please start Docker Desktop."
    open -a Docker
    exit 1
fi

# Navigate to OpenClaw directory
cd ~/.openclaw

# Initialize secrets if not done
if [[ ! -f secrets/.initialized ]]; then
    echo "Initializing secrets..."
    ./init-secrets.sh
fi

# Start OpenClaw with Docker Compose
echo "Starting OpenClaw..."
docker compose up -d

echo ""
echo "OpenClaw is starting!"
echo "Check status: docker compose ps"
echo "View logs: docker compose logs -f"
echo "Stop: docker compose down"
echo ""
EOF
chmod +x "${OPENCLAW_DIR}/quick-start.sh"

# Environment setup script
cat > "${OPENCLAW_DIR}/setup-env.sh" << 'EOF'
#!/bin/bash
# Source this file to set up OpenClaw environment variables
# Usage: source ~/.openclaw/setup-env.sh

export OPENCLAW_HOME="${HOME}/.openclaw"
export OPENCLAW_CONFIG_DIR="${OPENCLAW_HOME}/config"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_HOME}/workspace"
export OPENCLAW_SECRETS_DIR="${OPENCLAW_HOME}/secrets"

# Docker settings (if using rootless or custom socket)
# export DOCKER_HOST="unix://${HOME}/.docker/run/docker.sock"

# OpenClaw settings
export OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
export OPENCLAW_LOG_LEVEL="info"

# Add to PATH
export PATH="${OPENCLAW_HOME}/bin:${PATH}"

echo "OpenClaw environment configured"
echo "OPENCLAW_HOME: ${OPENCLAW_HOME}"
EOF

# Add environment setup to shell profile if not already there
if ! grep -q "openclaw/setup-env.sh" "${OPENCLAW_HOME}/.zshrc" 2>/dev/null; then
    cat >> "${OPENCLAW_HOME}/.zshrc" << 'EOF'

# OpenClaw environment (optional - uncomment to auto-load)
# source ~/.openclaw/setup-env.sh
EOF
fi

################################################################################
# Configure git-crypt for Secret Management (Optional)
################################################################################
log_info "Installing git-crypt for encrypted secret storage..."

if ! command -v git-crypt &> /dev/null; then
    brew install git-crypt
    log_info "git-crypt installed"
else
    log_info "git-crypt already installed"
fi

cat > "${OPENCLAW_DIR}/.gitattributes" << 'EOF'
# Encrypt secret files with git-crypt
secrets/** filter=git-crypt diff=git-crypt
*.key filter=git-crypt diff=git-crypt
*.pem filter=git-crypt diff=git-crypt
.env filter=git-crypt diff=git-crypt
EOF

cat > "${OPENCLAW_DIR}/.gitignore" << 'EOF'
# OpenClaw local files
workspace/
logs/
backups/
*.log

# Node.js
node_modules/
npm-debug.log*

# Docker
.env.local

# macOS
.DS_Store
.AppleDouble
.LSOverride

# Editor
.vscode/
.idea/
*.swp
*.swo
*~
EOF

################################################################################
# Security Recommendations
################################################################################
cat > "${OPENCLAW_DIR}/SECURITY-MACOS.md" << 'EOF'
# macOS Security Recommendations for OpenClaw

## Firewall Configuration

Enable macOS firewall:
```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on
```

## FileVault Encryption

Enable full disk encryption:
1. System Settings → Privacy & Security → FileVault
2. Turn On FileVault

## Gatekeeper

Ensure Gatekeeper is enabled:
```bash
sudo spctl --master-enable
```

## Secret Management

### Using git-crypt (Development)

Initialize git-crypt in your OpenClaw directory:
```bash
cd ~/.openclaw
git init
git-crypt init
git-crypt add-gpg-user YOUR_GPG_KEY_ID
```

All files in `secrets/` will be automatically encrypted when committed.

### Manual Secret Encryption

For sensitive files, use encryption:
```bash
# Encrypt a file
openssl enc -aes-256-cbc -salt -in secrets/api-keys.txt -out secrets/api-keys.txt.enc

# Decrypt a file
openssl enc -aes-256-cbc -d -in secrets/api-keys.txt.enc -out secrets/api-keys.txt
```

## Backup Strategy

Use Time Machine or automated backups:
```bash
# Manual backup
rsync -av --exclude 'logs/' ~/.openclaw/ ~/Backups/openclaw-$(date +%Y%m%d)/
```

## Updates

Keep system updated:
- Enable automatic updates: System Settings → General → Software Update
- Check for updates regularly

## Docker Security

Configure Docker Desktop security:
1. Docker Desktop → Settings → General
2. Enable "Use kernel networking for UDP" (if available)
3. Resources → Advanced: Set appropriate limits
4. Enable "gRPC FUSE for file sharing" for better performance

## Monitoring

Install and configure monitoring tools:
```bash
# System monitoring
brew install htop
brew install glances

# Network monitoring
brew install wireshark  # GUI network analyzer
```
EOF

################################################################################
# Summary
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_info "macOS setup complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Installed components:"
echo "  ✓ Homebrew $(brew --version | head -n1)"
echo "  ✓ Docker Desktop $(docker --version)"
echo "  ✓ Node.js $(node --version)"
echo "  ✓ pnpm $(pnpm --version)"
echo "  ✓ Tailscale"
echo "  ✓ git-crypt (for encrypted secrets)"
echo "  ✓ Development tools (jq, git, curl, wget, tree)"
echo ""
echo "OpenClaw directory: ${OPENCLAW_DIR}"
echo ""
echo "Helper scripts created:"
echo "  ${OPENCLAW_DIR}/check-setup.sh    - Check installation status"
echo "  ${OPENCLAW_DIR}/quick-start.sh    - Quick start OpenClaw"
echo "  ${OPENCLAW_DIR}/setup-env.sh      - Environment variables"
echo ""
echo "Next steps:"
echo "  1. Ensure Docker Desktop is running"
echo "  2. Connect to Tailscale (optional): open -a Tailscale"
echo "  3. Clone OpenClaw configuration to ${OPENCLAW_DIR}"
echo "  4. Run: cd ${OPENCLAW_DIR} && ./init-secrets.sh"
echo "  5. Deploy: docker compose up -d"
echo ""
echo "Security recommendations:"
echo "  - Enable FileVault (full disk encryption)"
echo "  - Enable macOS Firewall"
echo "  - Use git-crypt for secret management"
echo "  - Review: ${OPENCLAW_DIR}/SECURITY-MACOS.md"
echo ""
echo "Check setup: ${OPENCLAW_DIR}/check-setup.sh"
echo ""
log_info "For daily use, source the environment:"
log_info "  source ~/.openclaw/setup-env.sh"
echo "═══════════════════════════════════════════════════════════════════"

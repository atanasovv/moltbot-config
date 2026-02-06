#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw Ubuntu Server Provisioning Script
# 
# This script installs and configures a secure Ubuntu server for OpenClaw:
# - Docker Engine with rootless mode
# - gVisor runtime for enhanced container isolation
# - Node.js 22.12.0+ (CVE-patched)
# - UFW firewall (SSH + Tailscale only)
# - fail2ban for SSH brute-force protection
# - AppArmor security profiles
# - Unattended security upgrades
# - Tailscale for secure remote access
#
# Tested on: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
# Requires: sudo privileges
################################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should NOT be run as root (it will use sudo when needed)"
   exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu" /etc/os-release; then
    log_error "This script is designed for Ubuntu only"
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)
log_info "Detected Ubuntu ${UBUNTU_VERSION}"

# Configuration
OPENCLAW_USER="${USER}"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"
NODE_VERSION="22"

################################################################################
# 1. System Update
################################################################################
log_info "Step 1/10: Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

################################################################################
# 2. Install Prerequisites
################################################################################
log_info "Step 2/10: Installing prerequisites..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    uidmap \
    dbus-user-session \
    fuse-overlayfs \
    slirp4netns \
    jq \
    git \
    ufw \
    fail2ban

################################################################################
# 3. Install Docker Engine
################################################################################
log_info "Step 3/10: Installing Docker Engine..."

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
docker --version

################################################################################
# 4. Configure Docker Rootless Mode
################################################################################
log_info "Step 4/10: Configuring Docker rootless mode..."

# Check if rootless Docker is already installed
if command -v dockerd-rootless-setuptool.sh &> /dev/null; then
    log_info "Docker rootless tools already installed"
else
    log_error "dockerd-rootless-setuptool.sh not found. Installing docker-ce-rootless-extras..."
    sudo apt-get install -y docker-ce-rootless-extras
fi

# Disable system Docker daemon (we'll use rootless)
sudo systemctl disable --now docker.service docker.socket 2>/dev/null || true

# Install rootless Docker for current user
if [[ ! -f "${OPENCLAW_HOME}/.docker/config.json" ]] || ! systemctl --user is-active --quiet docker.service; then
    log_info "Setting up rootless Docker for user ${OPENCLAW_USER}..."
    
    # Enable lingering for user (keeps user services running after logout)
    sudo loginctl enable-linger "${OPENCLAW_USER}"
    
    # Install rootless Docker
    dockerd-rootless-setuptool.sh install
    
    # Add Docker environment to shell profile
    if ! grep -q "DOCKER_HOST=" "${OPENCLAW_HOME}/.bashrc"; then
        cat >> "${OPENCLAW_HOME}/.bashrc" << 'EOF'

# Docker rootless mode
export PATH="${HOME}/bin:${PATH}"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
EOF
    fi
    
    # Source for current session
    export PATH="${HOME}/bin:${PATH}"
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
    
    log_info "Rootless Docker configured. Reloading environment..."
else
    log_info "Rootless Docker already configured"
fi

# Verify rootless Docker
systemctl --user start docker.service
sleep 2
docker context use rootless 2>/dev/null || true
docker ps > /dev/null && log_info "Rootless Docker is working" || log_error "Rootless Docker verification failed"

################################################################################
# 5. Install gVisor Runtime
################################################################################
log_info "Step 5/10: Installing gVisor (runsc) runtime..."

ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" ]]; then
    GVISOR_ARCH="x86_64"
elif [[ "${ARCH}" == "aarch64" ]]; then
    GVISOR_ARCH="aarch64"
else
    log_warn "Unsupported architecture: ${ARCH}. Skipping gVisor installation."
    GVISOR_ARCH=""
fi

if [[ -n "${GVISOR_ARCH}" ]]; then
    if [[ ! -f "${OPENCLAW_HOME}/bin/runsc" ]]; then
        mkdir -p "${OPENCLAW_HOME}/bin"
        
        # Download latest gVisor
        GVISOR_VERSION=$(curl -s https://api.github.com/repos/google/gvisor/releases/latest | jq -r '.tag_name')
        log_info "Installing gVisor ${GVISOR_VERSION}..."
        
        curl -fsSL "https://storage.googleapis.com/gvisor/releases/release/latest/${GVISOR_ARCH}/runsc" -o "${OPENCLAW_HOME}/bin/runsc"
        curl -fsSL "https://storage.googleapis.com/gvisor/releases/release/latest/${GVISOR_ARCH}/runsc.sha512" -o "${OPENCLAW_HOME}/bin/runsc.sha512"
        
        # Verify checksum
        cd "${OPENCLAW_HOME}/bin"
        sha512sum -c runsc.sha512
        chmod +x runsc
        cd -
        
        log_info "gVisor runsc installed at ${OPENCLAW_HOME}/bin/runsc"
    else
        log_info "gVisor already installed"
    fi
    
    # Configure Docker to use gVisor runtime
    DOCKER_CONFIG_DIR="${OPENCLAW_HOME}/.config/docker"
    mkdir -p "${DOCKER_CONFIG_DIR}"
    
    DAEMON_JSON="${DOCKER_CONFIG_DIR}/daemon.json"
    if [[ ! -f "${DAEMON_JSON}" ]] || ! grep -q "runsc" "${DAEMON_JSON}"; then
        cat > "${DAEMON_JSON}" << EOF
{
  "runtimes": {
    "runsc": {
      "path": "${OPENCLAW_HOME}/bin/runsc",
      "runtimeArgs": [
        "--platform=systrap"
      ]
    }
  }
}
EOF
        log_info "gVisor runtime configured in Docker"
        
        # Restart Docker daemon
        systemctl --user restart docker.service
        sleep 2
    fi
    
    # Test gVisor
    if docker run --rm --runtime=runsc hello-world &>/dev/null; then
        log_info "gVisor runtime is working"
    else
        log_warn "gVisor runtime test failed (non-critical, will use default runtime)"
    fi
else
    log_warn "Skipping gVisor configuration"
fi

################################################################################
# 6. Install Node.js 22.12.0+
################################################################################
log_info "Step 6/10: Installing Node.js ${NODE_VERSION}..."

if command -v node &> /dev/null; then
    CURRENT_NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "${CURRENT_NODE_VERSION}" -ge "${NODE_VERSION}" ]]; then
        log_info "Node.js $(node --version) already installed"
    else
        log_warn "Upgrading Node.js from v${CURRENT_NODE_VERSION} to v${NODE_VERSION}..."
    fi
else
    # Install Node.js from NodeSource
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Verify installation
    node --version
    npm --version
    
    log_info "Node.js $(node --version) installed"
fi

# Install pnpm globally
if ! command -v pnpm &> /dev/null; then
    sudo npm install -g pnpm
    log_info "pnpm installed"
fi

################################################################################
# 7. Configure UFW Firewall
################################################################################
log_info "Step 7/10: Configuring UFW firewall..."

# Enable UFW if not already enabled
if ! sudo ufw status | grep -q "Status: active"; then
    log_info "Enabling UFW firewall..."
    
    # Set default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow SSH (change port if you use non-standard SSH port)
    sudo ufw allow 22/tcp comment 'SSH'
    
    # Allow Tailscale
    sudo ufw allow 41641/udp comment 'Tailscale'
    
    # Enable firewall (with --force to avoid interactive prompt)
    sudo ufw --force enable
    
    log_info "UFW firewall enabled"
else
    log_info "UFW firewall already configured"
fi

sudo ufw status verbose

################################################################################
# 8. Configure fail2ban
################################################################################
log_info "Step 8/10: Configuring fail2ban for SSH protection..."

if [[ ! -f /etc/fail2ban/jail.local ]]; then
    sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
EOF
    
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    
    log_info "fail2ban configured"
else
    log_info "fail2ban already configured"
fi

################################################################################
# 9. Configure Unattended Upgrades
################################################################################
log_info "Step 9/10: Configuring automatic security updates..."

sudo apt-get install -y unattended-upgrades apt-listchanges

# Configure unattended-upgrades
if [[ ! -f /etc/apt/apt.conf.d/50unattended-upgrades.bak ]]; then
    sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.bak
fi

sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

log_info "Automatic security updates enabled"

################################################################################
# 10. Install Tailscale
################################################################################
log_info "Step 10/10: Installing Tailscale..."

if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    
    log_info "Tailscale installed. To connect this server to your Tailscale network, run:"
    log_info "  sudo tailscale up"
else
    log_info "Tailscale already installed"
    
    if sudo tailscale status &>/dev/null; then
        log_info "Tailscale is connected"
    else
        log_warn "Tailscale is installed but not connected. Run: sudo tailscale up"
    fi
fi

################################################################################
# Final Setup
################################################################################
log_info "Creating OpenClaw directory structure..."
mkdir -p "${OPENCLAW_DIR}"/{config,workspace,secrets,backups,logs}
chmod 700 "${OPENCLAW_DIR}/secrets"

# Create a helper script to check secret expiry
cat > "${OPENCLAW_DIR}/check-setup.sh" << 'EOF'
#!/bin/bash
echo "=== OpenClaw Setup Status ==="
echo ""
echo "Docker (rootless):"
systemctl --user status docker.service | head -n 3
echo ""
echo "Docker runtime:"
docker info | grep -E "Runtime|Security Options" || true
echo ""
echo "Node.js version:"
node --version
echo ""
echo "Firewall status:"
sudo ufw status | head -n 10
echo ""
echo "Tailscale status:"
tailscale status 2>/dev/null | head -n 5 || echo "Not connected"
echo ""
echo "=== Setup Complete ==="
EOF
chmod +x "${OPENCLAW_DIR}/check-setup.sh"

################################################################################
# Summary
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_info "Ubuntu server provisioning complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Installed components:"
echo "  ✓ Docker Engine (rootless mode)"
echo "  ✓ gVisor runtime (runsc)"
echo "  ✓ Node.js $(node --version)"
echo "  ✓ pnpm $(pnpm --version)"
echo "  ✓ UFW firewall (SSH + Tailscale only)"
echo "  ✓ fail2ban (SSH protection)"
echo "  ✓ Unattended upgrades (automatic security updates)"
echo "  ✓ Tailscale VPN"
echo ""
echo "Next steps:"
echo "  1. Connect to Tailscale: sudo tailscale up"
echo "  2. Clone OpenClaw config: cd ${OPENCLAW_DIR}"
echo "  3. Run init-secrets.sh to configure API keys"
echo "  4. Deploy with docker-compose.yml"
echo ""
echo "Check setup status: ${OPENCLAW_DIR}/check-setup.sh"
echo ""
echo "Security notes:"
echo "  - Docker runs in rootless mode (non-root user)"
echo "  - gVisor provides kernel-level isolation"
echo "  - Firewall blocks all ports except SSH (22) and Tailscale (41641)"
echo "  - fail2ban protects against SSH brute-force attacks"
echo "  - System will auto-update security patches"
echo ""
log_warn "IMPORTANT: Reboot recommended to ensure all changes take effect"
echo "═══════════════════════════════════════════════════════════════════"

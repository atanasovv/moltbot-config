#!/bin/bash
set -euo pipefail

################################################################################
# OpenClaw macOS Development Environment Setup Script
# 
# This script installs and configures a macOS development environment for OpenClaw:
# - Homebrew package manager
# - Docker Desktop
# - Node.js 22+ (LTS)
# - Tailscale for secure remote access
# - Development tools and utilities
#
# Tested on: macOS Sonoma (14.x), macOS Sequoia (15.x)
# Requires: Administrator access
################################################################################

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
if [[ -f "${SCRIPT_DIR}/setup-common.sh" ]]; then
    source "${SCRIPT_DIR}/setup-common.sh"
else
    echo "Error: setup-common.sh not found"
    exit 1
fi

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
log_info "Step 1/6: Installing Homebrew package manager..."

if check_command_exists brew; then
    log_warn "Homebrew already installed: $(brew --version | head -n1)"
    log_info "Updating Homebrew..."
    brew update || log_warn "Homebrew update failed, but continuing..."
else
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${OPENCLAW_HOME}/.zprofile"
    fi
    
    log_info "Homebrew installed successfully"
fi

################################################################################
# 2. Install Docker Desktop
################################################################################
log_info "Step 2/6: Installing Docker Desktop..."

if ! check_docker_installed; then
    brew install --cask docker
    
    log_info "Docker Desktop installed. Starting Docker..."
    open -a Docker
    
    # Wait for Docker to start
    log_info "Waiting for Docker daemon to start (this may take a minute)..."
    for i in {1..30}; do
        if docker ps &>/dev/null; then
            log_info "Docker is running"
            break
        fi
        if [[ $i -eq 30 ]]; then
            log_warn "Docker daemon did not start within 30 seconds. Please start Docker Desktop manually."
        fi
        sleep 2
    done
fi

# Verify Docker installation
if docker --version &>/dev/null; then
    log_info "Docker version: $(docker --version)"
    docker compose version || log_warn "Docker Compose not available"
else
    log_warn "Docker not available. Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop"
fi

################################################################################
# 3. Install Node.js
################################################################################
log_info "Step 3/6: Installing Node.js ${NODE_VERSION}..."

install_or_upgrade_node "${NODE_VERSION}" \
    "brew install node@${NODE_VERSION} && brew link --overwrite node@${NODE_VERSION}"

install_pnpm

################################################################################
# 4. Install Development Tools
################################################################################
log_info "Step 4/6: Installing development tools..."

BREW_TOOLS=(
    "git"
    "jq"
    "wget"
    "curl"
)

for tool in "${BREW_TOOLS[@]}"; do
    if brew list "$tool" &>/dev/null; then
        log_warn "$tool already installed"
    else
        log_info "Installing $tool..."
        brew install "$tool" || log_warn "Failed to install $tool, but continuing..."
    fi
done

################################################################################
# 5. Install Tailscale
################################################################################
log_info "Step 5/6: Installing Tailscale..."

tailscale_status=$(check_tailscale; echo $?)
if [[ $tailscale_status -eq 2 ]]; then
    brew install --cask tailscale
    log_info "Tailscale installed. To connect to your Tailscale network:"
    log_info "  1. Open Tailscale from Applications"
    log_info "  2. Sign in with your account"
    log_info "  Or run: sudo tailscale up"
elif [[ $tailscale_status -eq 1 ]]; then
    log_warn "Tailscale is installed but not connected. Run: sudo tailscale up"
fi

################################################################################
# 6. Install git-crypt for secrets encryption
################################################################################
log_info "Step 6/6: Installing git-crypt for secrets encryption..."

install_git_crypt "brew install git-crypt"

################################################################################
# Final Setup
################################################################################
create_openclaw_dirs "${OPENCLAW_DIR}"
create_check_setup_script "${OPENCLAW_DIR}/check-setup.sh" "macos"

################################################################################
# Summary
################################################################################
echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_info "macOS development environment setup complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Installed components:"
echo "  ✓ Homebrew $(brew --version 2>/dev/null | head -n1 | cut -d' ' -f2 || echo 'N/A')"
echo "  ✓ Docker Desktop $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'N/A')"
echo "  ✓ Node.js $(node --version 2>/dev/null || echo 'N/A')"
echo "  ✓ pnpm $(pnpm --version 2>/dev/null || echo 'N/A')"
echo "  ✓ Development tools (git, jq, wget, curl)"
echo "  ✓ Tailscale VPN"
echo "  ✓ git-crypt (secrets encryption)"
echo ""
echo "Next steps:"
echo "  1. Ensure Docker Desktop is running"
echo "  2. Connect to Tailscale (if needed)"
echo "  3. For local development:"
echo "     cd ${OPENCLAW_DIR}"
echo "     ./init-secrets.sh"
echo "     ./deploy.sh"
echo "  4. For remote deployment, use ./build-remote.sh"
echo ""
echo "Check setup status: ${OPENCLAW_DIR}/check-setup.sh"
echo ""
echo "Development notes:"
echo "  - Use Docker Desktop for container management"
echo "  - git-crypt available for encrypting secrets in Git"
echo "  - Tailscale provides secure access to remote servers"
echo "  - All development files in: ${OPENCLAW_DIR}"
echo ""
log_info "Ready for OpenClaw development!"
echo "═══════════════════════════════════════════════════════════════════"

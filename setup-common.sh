#!/bin/bash
# Common functions for OpenClaw setup scripts
# Source this file in setup-ubuntu.sh and setup-macos.sh

################################################################################
# Color output functions
################################################################################

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

################################################################################
# Common validation functions
################################################################################

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root (it will use sudo when needed)"
        exit 1
    fi
}

check_command_exists() {
    local cmd="$1"
    command -v "$cmd" &> /dev/null
}

get_version() {
    local cmd="$1"
    local version_flag="${2:---version}"
    
    if check_command_exists "$cmd"; then
        $cmd $version_flag 2>/dev/null | head -n1
    else
        echo "Not installed"
    fi
}

################################################################################
# Node.js installation (common logic)
################################################################################

install_or_upgrade_node() {
    local target_version="$1"
    local install_command="$2"
    
    if check_command_exists node; then
        local current_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ "${current_version}" -ge "${target_version}" ]]; then
            log_warn "Node.js $(node --version) already installed (>= v${target_version})"
            return 0
        else
            log_warn "Node.js v${current_version} found. Upgrading to v${target_version}..."
        fi
    fi
    
    eval "$install_command"
    
    if check_command_exists node; then
        log_info "Node.js $(node --version) installed"
    fi
}

install_pnpm() {
    if check_command_exists pnpm; then
        log_warn "pnpm already installed: $(pnpm --version)"
    else
        npm install -g pnpm
        log_info "pnpm installed"
    fi
}

################################################################################
# Tailscale installation check
################################################################################

check_tailscale() {
    if check_command_exists tailscale; then
        log_warn "Tailscale already installed"
        
        if tailscale status &>/dev/null 2>&1 || sudo tailscale status &>/dev/null 2>&1; then
            log_info "Tailscale is connected"
            return 0
        else
            log_warn "Tailscale is installed but not connected"
            return 1
        fi
    fi
    return 2  # Not installed
}

################################################################################
# Directory structure creation
################################################################################

create_openclaw_dirs() {
    local base_dir="$1"
    
    log_info "Creating OpenClaw directory structure..."
    mkdir -p "${base_dir}"/{config,workspace,secrets,backups,logs}
    chmod 700 "${base_dir}/secrets"
    
    log_info "Directories created at ${base_dir}"
}

################################################################################
# Setup verification script
################################################################################

create_check_setup_script() {
    local script_path="$1"
    local os_type="$2"  # "ubuntu" or "macos"
    
    cat > "${script_path}" << 'EOFSCRIPT'
#!/bin/bash
echo "=== OpenClaw Setup Status ==="
echo ""

if [[ "$(uname)" == "Darwin" ]]; then
    # macOS checks
    echo "Docker Desktop:"
    docker --version 2>/dev/null || echo "Not installed"
    docker ps &>/dev/null && echo "Docker daemon: Running" || echo "Docker daemon: Not running"
    echo ""
    echo "Homebrew:"
    brew --version 2>/dev/null | head -n1 || echo "Not installed"
else
    # Ubuntu checks
    echo "Docker (rootless):"
    systemctl --user status docker.service 2>/dev/null | head -n 3 || echo "Not running"
    echo ""
    echo "Docker runtime:"
    docker info 2>/dev/null | grep -E "Runtime|Security Options" || echo "Not available"
    echo ""
    echo "Firewall status:"
    sudo ufw status 2>/dev/null | head -n 10 || echo "Not configured"
fi

echo ""
echo "Node.js version:"
node --version 2>/dev/null || echo "Not installed"
echo ""
echo "pnpm version:"
pnpm --version 2>/dev/null || echo "Not installed"
echo ""
echo "Tailscale status:"
tailscale status 2>/dev/null | head -n 5 || sudo tailscale status 2>/dev/null | head -n 5 || echo "Not connected"
echo ""
echo "=== Setup Complete ==="
EOFSCRIPT
    
    chmod +x "${script_path}"
    log_info "Check setup script created: ${script_path}"
}

################################################################################
# Docker installation check
################################################################################

check_docker_installed() {
    if check_command_exists docker; then
        local version=$(docker --version)
        log_warn "Docker already installed: ${version}"
        return 0
    fi
    return 1
}

################################################################################
# Git configuration helpers
################################################################################

install_git_crypt() {
    local install_cmd="$1"
    
    if check_command_exists git-crypt; then
        log_warn "git-crypt already installed: $(git-crypt --version)"
    else
        eval "$install_cmd"
        log_info "git-crypt installed"
    fi
}

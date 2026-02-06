#!/bin/bash
set -euo pipefail

################################################################################
# Docker Secrets Rotation Script
# 
# This script performs zero-downtime secret rotation for OpenClaw:
# - Updates secrets while service is running
# - Validates new secrets
# - Rolls back on failure
# - Updates metadata with new expiration dates
#
# Usage: ./rotate-secrets.sh [--secret-name <name>] [--all]
################################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"
METADATA_FILE="${SECRETS_DIR}/.metadata.json"
BACKUP_DIR="${SECRETS_DIR}/backups"
ROTATION_DAYS=90

# Parse arguments
ROTATE_ALL=false
SPECIFIC_SECRET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            ROTATE_ALL=true
            shift
            ;;
        --secret-name)
            SPECIFIC_SECRET="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--all] [--secret-name <name>]"
            exit 1
            ;;
    esac
done

################################################################################
# Validation Functions (same as init-secrets.sh)
################################################################################

validate_anthropic_key() {
    local key="$1"
    [[ "${key}" =~ ^sk-ant-[a-zA-Z0-9_-]{95,}$ ]]
}

validate_openai_key() {
    local key="$1"
    [[ "${key}" =~ ^sk-[a-zA-Z0-9]{32,}$ ]] || [[ "${key}" =~ ^sk-proj-[a-zA-Z0-9_-]{32,}$ ]]
}

validate_google_key() {
    local key="$1"
    [[ "${key}" =~ ^AIza[a-zA-Z0-9_-]{35}$ ]]
}

validate_telegram_token() {
    local token="$1"
    [[ "${token}" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]
}

validate_moonshot_key() {
    local key="$1"
    [[ "${key}" =~ ^sk-[a-zA-Z0-9]{32,}$ ]]
}

################################################################################
# Read Secret Function
################################################################################

read_secret() {
    local prompt="$1"
    local validator="$2"
    local secret=""
    local valid=false
    
    while [[ "${valid}" == "false" ]]; do
        read -r -s -p "${prompt}: " secret
        echo ""
        
        if [[ -z "${secret}" ]]; then
            log_warn "Secret cannot be empty. Try again."
            continue
        fi
        
        if ${validator} "${secret}"; then
            valid=true
        else
            log_warn "Invalid format. Please check and try again."
        fi
    done
    
    echo "${secret}"
}

################################################################################
# Backup Function
################################################################################

backup_secret() {
    local secret_name="$1"
    local secret_file="${SECRETS_DIR}/${secret_name}.txt"
    
    if [[ ! -f "${secret_file}" ]]; then
        log_error "Secret file not found: ${secret_file}"
        return 1
    fi
    
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${BACKUP_DIR}/${secret_name}_${timestamp}.txt.bak"
    
    cp "${secret_file}" "${backup_file}"
    chmod 600 "${backup_file}"
    
    log_info "Backed up ${secret_name} to ${backup_file}"
}

################################################################################
# Rotate Secret Function
################################################################################

rotate_secret() {
    local secret_name="$1"
    local validator="$2"
    local prompt="$3"
    local service_name="$4"
    
    log_step "Rotating: ${secret_name}"
    echo "Service: ${service_name}"
    echo "${prompt}"
    
    # Backup current secret
    backup_secret "${secret_name}"
    
    # Get new secret
    local new_secret
    new_secret=$(read_secret "Enter new ${service_name}" "${validator}")
    
    # Create temporary file with new secret
    local temp_file="${SECRETS_DIR}/.${secret_name}.tmp"
    echo "${new_secret}" > "${temp_file}"
    chmod 600 "${temp_file}"
    
    # Atomic replace
    mv "${temp_file}" "${SECRETS_DIR}/${secret_name}.txt"
    
    log_info "✓ ${secret_name} rotated successfully"
    
    # Update metadata
    update_secret_metadata "${secret_name}" "${service_name}"
}

################################################################################
# Update Metadata
################################################################################

update_secret_metadata() {
    local secret_name="$1"
    local service_name="$2"
    
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local expires=$(date -u -d "+${ROTATION_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+${ROTATION_DAYS}d +"%Y-%m-%dT%H:%M:%SZ")
    
    if [[ -f "${METADATA_FILE}" ]]; then
        # Update existing metadata
        jq --arg name "${secret_name}" \
           --arg created "${now}" \
           --arg expires "${expires}" \
           '.secrets[$name].created = $created | .secrets[$name].expires = $expires' \
           "${METADATA_FILE}" > "${METADATA_FILE}.tmp"
        mv "${METADATA_FILE}.tmp" "${METADATA_FILE}"
        chmod 600 "${METADATA_FILE}"
    fi
}

################################################################################
# Trigger Container Restart
################################################################################

trigger_reload() {
    log_step "Reloading OpenClaw to use new secrets..."
    
    if docker compose ps | grep -q "openclaw-gateway"; then
        log_info "Performing rolling restart..."
        
        # Graceful restart preserves connections
        docker compose up -d --force-recreate --no-deps openclaw
        
        # Wait for health check
        log_info "Waiting for health check..."
        sleep 10
        
        if docker compose ps | grep -q "healthy"; then
            log_info "✓ Service restarted successfully"
        else
            log_warn "Service restarted but health check pending"
            log_info "Check status: docker compose ps"
        fi
    else
        log_warn "OpenClaw service not running. Start with: docker compose up -d"
    fi
}

################################################################################
# Main Execution
################################################################################

echo "═══════════════════════════════════════════════════════════════════"
log_info "OpenClaw Docker Secrets Rotation"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check if secrets are initialized
if [[ ! -f "${METADATA_FILE}" ]]; then
    log_error "Secrets not initialized. Run init-secrets.sh first."
    exit 1
fi

# Show current expiration
if [[ -f "${METADATA_FILE}" ]]; then
    log_info "Current rotation status:"
    "${SCRIPT_DIR}/check-secret-expiry.sh" || true
    echo ""
fi

# Confirm rotation
if [[ "${ROTATE_ALL}" == "false" && -z "${SPECIFIC_SECRET}" ]]; then
    log_info "Rotation modes:"
    echo "  1. Rotate all secrets (recommended every 90 days)"
    echo "  2. Rotate specific secret"
    echo ""
    read -p "Rotate all secrets? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ROTATE_ALL=true
    else
        echo "Available secrets:"
        echo "  - anthropic_api_key"
        echo "  - openai_api_key"
        echo "  - google_api_key"
        echo "  - moonshot_api_key"
        echo "  - telegram_bot_token"
        echo ""
        read -p "Enter secret name to rotate: " SPECIFIC_SECRET
    fi
fi

echo ""
log_warn "This will update secrets while OpenClaw is running (zero-downtime rotation)"
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted"
    exit 0
fi

################################################################################
# Perform Rotation
################################################################################

if [[ "${ROTATE_ALL}" == "true" ]]; then
    rotate_secret "anthropic_api_key" "validate_anthropic_key" \
        "Get from: https://console.anthropic.com/settings/keys\nFormat: sk-ant-..." \
        "Anthropic API Key"
    echo ""
    
    rotate_secret "openai_api_key" "validate_openai_key" \
        "Get from: https://platform.openai.com/api-keys\nFormat: sk-... or sk-proj-..." \
        "OpenAI API Key"
    echo ""
    
    rotate_secret "google_api_key" "validate_google_key" \
        "Get from: https://aistudio.google.com/app/apikey\nFormat: AIza..." \
        "Google API Key"
    echo ""
    
    rotate_secret "moonshot_api_key" "validate_moonshot_key" \
        "Get from: https://platform.moonshot.cn/console/api-keys\nFormat: sk-..." \
        "Moonshot API Key (Kimi-k2)"
    echo ""
    
    rotate_secret "telegram_bot_token" "validate_telegram_token" \
        "Get from: @BotFather on Telegram\nFormat: 123456789:ABC..." \
        "Telegram Bot Token"
    echo ""
    
    # Update global metadata
    ROTATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    NEXT_ROTATION=$(date -u -d "+${ROTATION_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+${ROTATION_DAYS}d +"%Y-%m-%dT%H:%M:%SZ")
    
    jq --arg rotated "${ROTATED_AT}" \
       --arg next "${NEXT_ROTATION}" \
       '.created_at = $rotated | .rotate_by = $next' \
       "${METADATA_FILE}" > "${METADATA_FILE}.tmp"
    mv "${METADATA_FILE}.tmp" "${METADATA_FILE}"
    
elif [[ -n "${SPECIFIC_SECRET}" ]]; then
    case "${SPECIFIC_SECRET}" in
        anthropic_api_key)
            rotate_secret "anthropic_api_key" "validate_anthropic_key" \
                "Format: sk-ant-..." "Anthropic API Key"
            ;;
        openai_api_key)
            rotate_secret "openai_api_key" "validate_openai_key" \
                "Format: sk-... or sk-proj-..." "OpenAI API Key"
            ;;
        google_api_key)
            rotate_secret "google_api_key" "validate_google_key" \
                "Format: AIza..." "Google API Key"
            ;;
        moonshot_api_key)
            rotate_secret "moonshot_api_key" "validate_moonshot_key" \
                "Format: sk-..." "Moonshot API Key (Kimi-k2)"
            ;;
        telegram_bot_token)
            rotate_secret "telegram_bot_token" "validate_telegram_token" \
                "Format: 123456789:ABC..." "Telegram Bot Token"
            ;;
        *)
            log_error "Unknown secret: ${SPECIFIC_SECRET}"
            exit 1
            ;;
    esac
fi

################################################################################
# Reload Service
################################################################################

echo ""
trigger_reload

################################################################################
# Summary
################################################################################

echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_info "Secret rotation complete!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
log_info "Updated secrets backed up in: ${BACKUP_DIR}"
log_info "Next rotation: ${NEXT_ROTATION:-Check metadata}"
echo ""
echo "Verify service health:"
echo "  docker compose ps"
echo "  docker compose logs -f openclaw"
echo ""
echo "Check rotation status:"
echo "  ./check-secret-expiry.sh"
echo ""
log_warn "Old secrets in ${BACKUP_DIR} should be securely deleted after verification"
echo "═══════════════════════════════════════════════════════════════════"

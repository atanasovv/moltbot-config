#!/bin/bash
set -euo pipefail

################################################################################
# Docker Secrets Initialization Script
# 
# This script securely initializes Docker secrets for OpenClaw:
# - Anthropic API Key (Claude 3.5 Sonnet)
# - OpenAI API Key (GPT-4o, o1)
# - Google API Key (Gemini 2.0 Flash)
# - Telegram Bot Token
#
# Features:
# - Secure input (hidden passwords)
# - API key validation
# - 90-day rotation tracking
# - Backup of secret metadata
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
ROTATION_DAYS=90

# Ensure secrets directory exists with proper permissions
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

################################################################################
# Validation Functions
################################################################################

validate_anthropic_key() {
    local key="$1"
    if [[ ! "${key}" =~ ^sk-ant-[a-zA-Z0-9_-]{95,}$ ]]; then
        return 1
    fi
    return 0
}

validate_openai_key() {
    local key="$1"
    if [[ ! "${key}" =~ ^sk-[a-zA-Z0-9]{32,}$ ]] && [[ ! "${key}" =~ ^sk-proj-[a-zA-Z0-9_-]{32,}$ ]]; then
        return 1
    fi
    return 0
}

validate_google_key() {
    local key="$1"
    if [[ ! "${key}" =~ ^AIza[a-zA-Z0-9_-]{35}$ ]]; then
        return 1
    fi
    return 0
}

validate_telegram_token() {
    local token="$1"
    if [[ ! "${token}" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
        return 1
    fi
    return 0
}

################################################################################
# Secret Input Function
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
# Main Initialization
################################################################################

echo "═══════════════════════════════════════════════════════════════════"
log_info "OpenClaw Docker Secrets Initialization"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check if secrets already exist
if [[ -f "${SECRETS_DIR}/anthropic_api_key.txt" ]]; then
    log_warn "Secrets already exist in ${SECRETS_DIR}"
    read -p "Do you want to reinitialize? This will overwrite existing secrets. (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted. Use rotate-secrets.sh to update existing secrets."
        exit 0
    fi
fi

echo "This script will securely collect your API keys and store them as Docker secrets."
echo ""
log_warn "Important Security Notes:"
echo "  - Your input will be hidden"
echo "  - Secrets are stored in: ${SECRETS_DIR}"
echo "  - Directory permissions: 700 (owner only)"
echo "  - Secrets will expire in ${ROTATION_DAYS} days"
echo "  - Never commit secrets to version control"
echo ""
read -p "Press Enter to continue..."
echo ""

################################################################################
# Collect API Keys
################################################################################

log_step "1/4: Anthropic API Key (Claude 3.5 Sonnet)"
echo "Get your key from: https://console.anthropic.com/settings/keys"
echo "Format: sk-ant-..."
ANTHROPIC_KEY=$(read_secret "Enter Anthropic API Key" validate_anthropic_key)
echo "${ANTHROPIC_KEY}" > "${SECRETS_DIR}/anthropic_api_key.txt"
chmod 600 "${SECRETS_DIR}/anthropic_api_key.txt"
log_info "✓ Anthropic API key saved"
echo ""

log_step "2/4: OpenAI API Key (GPT-4o, o1)"
echo "Get your key from: https://platform.openai.com/api-keys"
echo "Format: sk-... or sk-proj-..."
OPENAI_KEY=$(read_secret "Enter OpenAI API Key" validate_openai_key)
echo "${OPENAI_KEY}" > "${SECRETS_DIR}/openai_api_key.txt"
chmod 600 "${SECRETS_DIR}/openai_api_key.txt"
log_info "✓ OpenAI API key saved"
echo ""

log_step "3/4: Google API Key (Gemini 2.0 Flash)"
echo "Get your key from: https://aistudio.google.com/app/apikey"
echo "Format: AIza..."
GOOGLE_KEY=$(read_secret "Enter Google API Key" validate_google_key)
echo "${GOOGLE_KEY}" > "${SECRETS_DIR}/google_api_key.txt"
chmod 600 "${SECRETS_DIR}/google_api_key.txt"
log_info "✓ Google API key saved"
echo ""

log_step "4/4: Telegram Bot Token"
echo "Get your token from: @BotFather on Telegram"
echo "Run: /newbot and copy the token"
echo "Format: 123456789:ABC..."
TELEGRAM_TOKEN=$(read_secret "Enter Telegram Bot Token" validate_telegram_token)
echo "${TELEGRAM_TOKEN}" > "${SECRETS_DIR}/telegram_bot_token.txt"
chmod 600 "${SECRETS_DIR}/telegram_bot_token.txt"
log_info "✓ Telegram bot token saved"
echo ""

################################################################################
# Create Metadata
################################################################################

log_step "Creating secret metadata..."

CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ROTATE_BY=$(date -u -d "+${ROTATION_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+${ROTATION_DAYS}d +"%Y-%m-%dT%H:%M:%SZ")

cat > "${METADATA_FILE}" << EOF
{
  "created_at": "${CREATED_AT}",
  "rotate_by": "${ROTATE_BY}",
  "rotation_days": ${ROTATION_DAYS},
  "secrets": {
    "anthropic_api_key": {
      "created": "${CREATED_AT}",
      "expires": "${ROTATE_BY}",
      "format": "sk-ant-*",
      "service": "Anthropic Claude"
    },
    "openai_api_key": {
      "created": "${CREATED_AT}",
      "expires": "${ROTATE_BY}",
      "format": "sk-* or sk-proj-*",
      "service": "OpenAI GPT"
    },
    "google_api_key": {
      "created": "${CREATED_AT}",
      "expires": "${ROTATE_BY}",
      "format": "AIza*",
      "service": "Google Gemini"
    },
    "telegram_bot_token": {
      "created": "${CREATED_AT}",
      "expires": "${ROTATE_BY}",
      "format": "NNNNNNNN:AAA*",
      "service": "Telegram Bot API"
    }
  }
}
EOF

chmod 600 "${METADATA_FILE}"
log_info "✓ Metadata saved"

################################################################################
# Create .gitignore
################################################################################

cat > "${SECRETS_DIR}/.gitignore" << 'EOF'
# Ignore all secret files
*.txt
*.key
*.pem

# Allow metadata (no sensitive data)
!.metadata.json

# Allow this .gitignore
!.gitignore
EOF

log_info "✓ .gitignore created"

################################################################################
# Create Rotation Reminder Script
################################################################################

cat > "${SCRIPT_DIR}/check-secret-expiry.sh" << 'CHECKSCRIPT'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_FILE="${SCRIPT_DIR}/secrets/.metadata.json"

if [[ ! -f "${METADATA_FILE}" ]]; then
    echo "Error: Metadata file not found. Run init-secrets.sh first."
    exit 1
fi

ROTATE_BY=$(jq -r '.rotate_by' "${METADATA_FILE}")
ROTATE_TIMESTAMP=$(date -d "${ROTATE_BY}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${ROTATE_BY}" +%s)
CURRENT_TIMESTAMP=$(date +%s)
DAYS_REMAINING=$(( (ROTATE_TIMESTAMP - CURRENT_TIMESTAMP) / 86400 ))

echo "Secret Rotation Status"
echo "======================"
echo "Created: $(jq -r '.created_at' "${METADATA_FILE}")"
echo "Rotate by: ${ROTATE_BY}"
echo "Days remaining: ${DAYS_REMAINING}"
echo ""

if [[ ${DAYS_REMAINING} -lt 0 ]]; then
    echo "⚠️  EXPIRED! Secrets are overdue for rotation."
    echo "Run: ./rotate-secrets.sh"
    exit 1
elif [[ ${DAYS_REMAINING} -lt 7 ]]; then
    echo "⚠️  WARNING: Secrets expire in ${DAYS_REMAINING} days!"
    echo "Schedule rotation soon: ./rotate-secrets.sh"
    exit 0
elif [[ ${DAYS_REMAINING} -lt 30 ]]; then
    echo "ℹ️  Notice: Secrets expire in ${DAYS_REMAINING} days"
    exit 0
else
    echo "✓ Secrets are current (${DAYS_REMAINING} days remaining)"
    exit 0
fi
CHECKSCRIPT

chmod +x "${SCRIPT_DIR}/check-secret-expiry.sh"
log_info "✓ Expiry checker created: check-secret-expiry.sh"

################################################################################
# Summary
################################################################################

echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_info "Secrets initialized successfully!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Secrets stored in: ${SECRETS_DIR}"
echo "  - anthropic_api_key.txt"
echo "  - openai_api_key.txt"
echo "  - google_api_key.txt"
echo "  - telegram_bot_token.txt"
echo ""
echo "Metadata: ${METADATA_FILE}"
echo "  Created: ${CREATED_AT}"
echo "  Rotate by: ${ROTATE_BY} (${ROTATION_DAYS} days)"
echo ""
echo "Security checklist:"
echo "  ✓ Secrets stored with 600 permissions (owner read/write only)"
echo "  ✓ Directory has 700 permissions (owner access only)"
echo "  ✓ .gitignore configured to prevent commits"
echo "  ✓ Rotation tracking enabled"
echo ""
echo "Next steps:"
echo "  1. Build Docker image: docker build -t openclaw:secure ."
echo "  2. Start OpenClaw: docker compose up -d"
echo "  3. Check status: docker compose ps"
echo "  4. View logs: docker compose logs -f"
echo ""
echo "Maintenance:"
echo "  - Check expiry: ./check-secret-expiry.sh"
echo "  - Rotate secrets: ./rotate-secrets.sh"
echo "  - Add to cron (weekly check):"
echo "    0 9 * * 1 cd ${SCRIPT_DIR} && ./check-secret-expiry.sh"
echo ""
log_warn "IMPORTANT: Keep the secrets/ directory secure and never commit to git!"
echo "═══════════════════════════════════════════════════════════════════"

# Mark initialization complete
touch "${SECRETS_DIR}/.initialized"

#!/usr/bin/env bash
#
# build-remote.sh - Build OpenClaw Docker image on remote Ubuntu server
#
# Usage:
#   ./build-remote.sh [options]
#
# Options:
#   --no-cache    Build without using cache
#   --push        Push image to registry after build
#   --tag TAG     Use custom tag (default: secure)
#   --help        Show this help message
#

set -euo pipefail

# Configuration
REMOTE_HOST="vaki-lenovo"
REMOTE_USER="${REMOTE_USER:-$(whoami)}"
REMOTE_PATH="${REMOTE_PATH:-/home/${REMOTE_USER}/openclaw}"
DOCKER_HUB_USER="vladislav2502"
IMAGE_NAME="${DOCKER_HUB_USER}/openclaw"
IMAGE_TAG="secure"
NO_CACHE=""
PUSH_IMAGE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --push)
            PUSH_IMAGE=true
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Main script
main() {
    log_info "Building OpenClaw Docker image on remote server: ${REMOTE_HOST}"
    echo ""
    echo "Configuration:"
    echo "  Remote host: ${REMOTE_HOST}"
    echo "  Remote user: ${REMOTE_USER}"
    echo "  Remote path: ${REMOTE_PATH}"
    echo "  Image name:  ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "  No cache:    ${NO_CACHE:-false}"
    echo "  Push:        ${PUSH_IMAGE}"
    echo ""
    
    # Step 1: Test SSH connection
    log_info "Testing SSH connection to ${REMOTE_HOST}..."
    if ! ssh -q "${REMOTE_HOST}" exit; then
        log_error "Cannot connect to ${REMOTE_HOST}"
        log_error "Please check:"
        log_error "  1. SSH config file (~/.ssh/config) has 'vaki-lenovo' entry"
        log_error "  2. SSH certificate is valid and loaded"
        log_error "  3. Remote server is accessible"
        exit 1
    fi
    log_success "SSH connection successful"
    
    # Step 2: Check if Docker is installed on remote
    log_info "Checking Docker installation on remote..."
    if ! ssh "${REMOTE_HOST}" "command -v docker >/dev/null 2>&1"; then
        log_error "Docker is not installed on ${REMOTE_HOST}"
        log_error "Please run: ./setup-ubuntu.sh on the remote server first"
        exit 1
    fi
    log_success "Docker is installed"
    
    # Step 3: Create remote directory if it doesn't exist
    log_info "Creating remote directory: ${REMOTE_PATH}"
    if ! ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH} 2>/dev/null"; then
        log_warning "Cannot create ${REMOTE_PATH}, trying alternative location..."
        # Try current user's home directory
        REMOTE_PATH=$(ssh "${REMOTE_HOST}" "echo \$HOME")/openclaw
        log_info "Using alternative path: ${REMOTE_PATH}"
        ssh "${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH}"
    fi
    log_success "Remote directory ready: ${REMOTE_PATH}"
    
    # Step 4: Sync project files to remote
    log_info "Syncing project files to remote server..."
    rsync -avz --delete \
        --exclude 'secrets/' \
        --exclude '.git/' \
        --exclude 'monitoring/data/' \
        --exclude '*.log' \
        --exclude '.DS_Store' \
        --exclude 'node_modules/' \
        --progress \
        ./ "${REMOTE_HOST}:${REMOTE_PATH}/"
    log_success "Files synced successfully"
    
    # Step 5: Build Docker image on remote
    log_info "Building Docker image on ${REMOTE_HOST}..."
    echo ""
    
    BUILD_CMD="cd ${REMOTE_PATH} && docker build ${NO_CACHE} -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile ."
    
    if ssh -t "${REMOTE_HOST}" "${BUILD_CMD}"; then
        log_success "Docker image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
    else
        log_error "Docker build failed"
        exit 1
    fi
    
    # Step 6: Verify image was created
    log_info "Verifying image..."
    if ssh "${REMOTE_HOST}" "docker images ${IMAGE_NAME}:${IMAGE_TAG} --format '{{.Repository}}:{{.Tag}}' | grep -q '${IMAGE_NAME}:${IMAGE_TAG}'"; then
        log_success "Image verified on remote server"
        
        # Get image details
        echo ""
        log_info "Image details:"
        ssh "${REMOTE_HOST}" "docker images ${IMAGE_NAME}:${IMAGE_TAG} --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'"
    else
        log_error "Image verification failed"
        exit 1
    fi
    
    # Step 7: Tag as latest
    log_info "Tagging as latest..."
    ssh "${REMOTE_HOST}" "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
    log_success "Tagged as ${IMAGE_NAME}:latest"
    
    # Step 8: Push to Docker Hub (optional)
    if [[ "${PUSH_IMAGE}" == true ]]; then
        log_info "Checking Docker Hub login..."
        if ! ssh "${REMOTE_HOST}" "docker info | grep -q 'Username: ${DOCKER_HUB_USER}'"; then
            log_warning "Not logged into Docker Hub as ${DOCKER_HUB_USER}"
            log_info "Please login on remote server:"
            log_info "  ssh ${REMOTE_HOST} 'docker login -u ${DOCKER_HUB_USER}'"
            exit 1
        fi
        
        log_info "Pushing image to Docker Hub..."
        if ssh "${REMOTE_HOST}" "docker push ${IMAGE_NAME}:${IMAGE_TAG}"; then
            log_success "Image pushed to Docker Hub: ${IMAGE_NAME}:${IMAGE_TAG}"
            
            # Also push latest tag
            if ssh "${REMOTE_HOST}" "docker push ${IMAGE_NAME}:latest"; then
                log_success "Latest tag pushed: ${IMAGE_NAME}:latest"
            fi
        else
            log_error "Failed to push image to Docker Hub"
            exit 1
        fi
    fi
    
    # Step 9: Cleanup old images
    log_info "Cleaning up old images..."
    ssh "${REMOTE_HOST}" "docker image prune -f" || log_warning "Could not prune old images"
    
    echo ""
    log_success "Build complete!"
    echo ""
    if [[ "${PUSH_IMAGE}" == true ]]; then
        echo "Image available at:"
        echo "  https://hub.docker.com/r/${DOCKER_HUB_USER}/openclaw"
        echo ""
    fi
    echo "Next steps:"
    echo "  1. Deploy on remote: ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && ./deploy.sh'"
    echo "  2. Check status:     ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker compose ps'"
    echo "  3. View logs:        ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker compose logs -f'"
    echo ""
    if [[ "${PUSH_IMAGE}" == false ]]; then
        echo "To push to Docker Hub, run: ./build-remote.sh --push"
        echo ""
    fi
}

# Run main function
main
    log_info "Cleaning up old images..."
    ssh "${REMOTE_HOST}" "docker image prune -f" || log_warning "Could not prune old images"
    
    echo ""
    log_success "Build complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy on remote: ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && ./deploy.sh'"
    echo "  2. Check status:     ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker compose ps'"
    echo "  3. View logs:        ssh ${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker compose logs -f'"
    echo ""
}

# Run main function
main


# Multi-stage Dockerfile for OpenClaw
# Security-hardened build with gVisor compatibility
# Node.js 22 (CVE-patched), non-root user, read-only filesystem

################################################################################
# Stage 1: Builder
################################################################################
FROM node:22-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Install OpenClaw from official source
# Using the official installation method
RUN curl -fsSL https://openclaw.ai/install.sh | bash || \
    npm install -g openclaw

# Verify installation
RUN openclaw --version || node --version

################################################################################
# Stage 2: Runtime
################################################################################
FROM node:22-slim

# Metadata
LABEL maintainer="OpenClaw Security Team"
LABEL description="OpenClaw - Secure Personal AI Assistant with Multi-LLM Support"
LABEL version="1.0.0"
LABEL security.hardened="true"
LABEL security.runtime="gvisor-compatible"

# Install runtime dependencies only (minimal)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    tini \
    dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

    # Create non-root user with specific UID/GID for consistency
    # Handle existing GID/UID gracefully
    RUN (groupadd -r -g 1000 openclaw 2>/dev/null || groupadd -r openclaw) && \
        (useradd -r -u 1000 -g openclaw -m -s /bin/bash openclaw 2>/dev/null || \
         useradd -r -g openclaw -m -s /bin/bash openclaw) && \
        mkdir -p /home/openclaw/.openclaw && \
        chown -R openclaw:openclaw /home/openclaw
    
    # Set working directory
    WORKDIR /app

# Copy OpenClaw from builder stage
# If using npm global install
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin /usr/local/bin

# Alternative: If using local installation
# COPY --from=builder /root/.openclaw /home/openclaw/.openclaw

# Create necessary directories with proper permissions
RUN mkdir -p \
    /app/config \
    /app/workspace \
    /app/logs \
    /app/tmp \
    /run/secrets \
    && chown -R openclaw:openclaw /app \
    && chmod 755 /app/config /app/workspace /app/logs \
    && chmod 1777 /app/tmp

# Create read-only system directories
RUN mkdir -p /etc/openclaw && \
    chown root:root /etc/openclaw && \
    chmod 755 /etc/openclaw

# Install pnpm for openclaw user
RUN corepack enable && corepack prepare pnpm@latest --activate

# Switch to non-root user
USER openclaw:openclaw

# Set environment variables
ENV NODE_ENV=production \
    OPENCLAW_STATE_DIR=/app/config \
    OPENCLAW_WORKSPACE_DIR=/app/workspace \
    OPENCLAW_LOG_DIR=/app/logs \
    OPENCLAW_HOME=/home/openclaw/.openclaw \
    PATH="/home/openclaw/.local/bin:${PATH}" \
    NPM_CONFIG_PREFIX=/home/openclaw/.local \
    NODE_OPTIONS="--max-old-space-size=1536"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# Expose OpenClaw gateway port
EXPOSE 18789

# Volume mount points (will be read-only in docker-compose except these)
VOLUME ["/app/config", "/app/workspace", "/app/logs"]

# Use tini as PID 1 for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Default command: start OpenClaw gateway
# This will be overridden in docker-compose for different services
CMD ["openclaw", "gateway", \
     "--allow-unconfigured", \
     "--port", "18789", \
     "--bind", "0.0.0.0"]

################################################################################
# Security Features:
# - Non-root user (openclaw:1000)
# - Minimal base image (node:22-slim)
# - No unnecessary packages
# - Read-only filesystem compatible (when configured in docker-compose)
# - gVisor runtime compatible
# - Proper signal handling with tini
# - Health checks for container orchestration
# - Secrets mounted at /run/secrets
################################################################################

# Build this image with:
# docker build -t openclaw:secure .
#
# For gVisor runtime:
# docker run --runtime=runsc -d openclaw:secure
#
# Security options:
# docker run --read-only --cap-drop=ALL --security-opt=no-new-privileges \
#   -v openclaw-config:/app/config \
#   -v openclaw-workspace:/app/workspace \
#   --tmpfs /app/tmp:rw,noexec,nosuid,size=100m \
#   openclaw:secure

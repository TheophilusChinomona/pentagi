#!/usr/bin/env bash
# ============================================================================
# Athena Pentest — Full Self-Contained Setup
# Run this on any Ubuntu 24.04 server with Docker installed
# The agent can run this — no human interaction needed
#
# Usage:
#   ./setup.sh                                    # Interactive
#   ./setup.sh --openrouter-key sk-or-v1-xxx     # Non-interactive
#   ./setup.sh --openrouter-key xxx --public-url https://pentest.example.com
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
step() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Parse Arguments
# ============================================================================

OPENROUTER_KEY=""
PUBLIC_URL=""
LISTEN_IP="127.0.0.1"
LISTEN_PORT="8443"
POSTGRES_PASSWORD=""
COOKIE_SALT=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --openrouter-key)  OPENROUTER_KEY="$2"; shift 2 ;;
        --public-url)      PUBLIC_URL="$2"; shift 2 ;;
        --listen-ip)       LISTEN_IP="$2"; shift 2 ;;
        --listen-port)     LISTEN_PORT="$2"; shift 2 ;;
        --postgres-pass)   POSTGRES_PASSWORD="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --openrouter-key KEY   OpenRouter API key (required)"
            echo "  --public-url URL       Public URL (default: https://localhost:PORT)"
            echo "  --listen-ip IP         Bind IP (default: 127.0.0.1)"
            echo "  --listen-port PORT     Bind port (default: 8443)"
            echo "  --postgres-pass PASS   PostgreSQL password (auto-generated if omitted)"
            echo "  --non-interactive      Skip all prompts"
            echo ""
            exit 0
            ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================================
# Step 1: Prerequisites
# ============================================================================

step "Step 1/6: Checking Prerequisites"

# Docker
if ! command -v docker &>/dev/null; then
    err "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    log "Docker installed"
else
    log "Docker: $(docker --version)"
fi

# Docker Compose
if ! docker compose version &>/dev/null; then
    err "Docker Compose plugin not found. Installing..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
    log "Docker Compose installed"
else
    log "Docker Compose: $(docker compose version --short)"
fi

# Check Docker is running
if ! docker info &>/dev/null; then
    err "Docker is not running. Starting..."
    systemctl start docker
fi
log "Docker daemon: running"

# Git
if ! command -v git &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq git
fi
log "Git: available"

# jq (for JSON processing)
if ! command -v jq &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq jq
fi
log "jq: available"

# ============================================================================
# Step 2: Configuration
# ============================================================================

step "Step 2/6: Configuration"

# Generate secure passwords if not provided
if [[ -z "$POSTGRES_PASSWORD" ]]; then
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
    log "Generated PostgreSQL password"
fi

if [[ -z "$COOKIE_SALT" ]]; then
    COOKIE_SALT=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
    log "Generated cookie signing salt"
fi

# OpenRouter key — required
if [[ -z "$OPENROUTER_KEY" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        err "OpenRouter API key required. Pass with --openrouter-key"
        exit 1
    else
        read -p "Enter your OpenRouter API key: " OPENROUTER_KEY
        if [[ -z "$OPENROUTER_KEY" ]]; then
            err "OpenRouter key is required"
            exit 1
        fi
    fi
fi

# Public URL
if [[ -z "$PUBLIC_URL" ]]; then
    PUBLIC_URL="https://${LISTEN_IP}:${LISTEN_PORT}"
    if [[ "$LISTEN_IP" == "0.0.0.0" ]]; then
        HOST_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
        PUBLIC_URL="https://${HOST_IP}:${LISTEN_PORT}"
    fi
fi

# Results directory
RESULTS_DIR="/opt/pentest-results"
mkdir -p "$RESULTS_DIR"

# Create .env
cat > .env <<EOF
# Athena Pentest — Auto-generated $(date -Iseconds)
# ================================================

# Gateway
GATEWAY_LISTEN_IP=${LISTEN_IP}
GATEWAY_LISTEN_PORT=${LISTEN_PORT}
PUBLIC_URL=${PUBLIC_URL}
CORS_ORIGINS=https://localhost:${LISTEN_PORT},${PUBLIC_URL}
COOKIE_SIGNING_SALT=${COOKIE_SALT}

# Database
POSTGRES_USER=athena
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=athena_pentest

# LLM Provider
OPENROUTER_KEY=${OPENROUTER_KEY}

# Storage
PENTEST_RESULTS_DIR=${RESULTS_DIR}
EOF

log ".env created"
chmod 600 .env
log ".env permissions set (600)"

# Save credentials for the agent
cat > .credentials.json <<EOF
{
  "created_at": "$(date -Iseconds)",
  "public_url": "${PUBLIC_URL}",
  "listen_ip": "${LISTEN_IP}",
  "listen_port": "${LISTEN_PORT}",
  "postgres_user": "athena",
  "postgres_password": "${POSTGRES_PASSWORD}",
  "results_dir": "${RESULTS_DIR}"
}
EOF
chmod 600 .credentials.json
log "Credentials saved to .credentials.json"

# ============================================================================
# Step 3: Create Results Directory
# ============================================================================

step "Step 3/6: Setting Up Storage"

mkdir -p "$RESULTS_DIR"
log "Results directory: $RESULTS_DIR"

# ============================================================================
# Step 4: Build Images
# ============================================================================

step "Step 4/6: Building Images"
warn "First run builds both images — takes 15-25 minutes total"

# Build Athena gateway from your fork
log "Building Athena gateway from your hermes-agent fork..."
docker compose build athena-gateway 2>&1 | tail -20

if docker images | grep -q "athena/gateway"; then
    log "Gateway image built: athena/gateway:latest"
else
    err "Gateway image build failed"
    exit 1
fi

# Build pentest tools image
log "Building pentest tools image..."
docker build -t athena/pentest-tools:latest -f docker/pentest-tools.Dockerfile docker/ 2>&1 | tail -20

if docker images | grep -q "athena/pentest-tools"; then
    IMAGE_SIZE=$(docker images athena/pentest-tools --format "{{.Size}}")
    log "Tools image built: athena/pentest-tools:latest ($IMAGE_SIZE)"
else
    err "Tools image build failed"
    exit 1
fi

# ============================================================================
# Step 5: Deploy Stack
# ============================================================================

step "Step 5/6: Deploying Stack"

# Pull base images first
log "Pulling base images..."
docker compose pull --ignore-buildable 2>/dev/null || true

# Start the stack
log "Starting services..."
docker compose up -d

# Wait for services
log "Waiting for services to start..."
sleep 10

# Check postgres health
POSTGRES_HEALTHY=false
for i in $(seq 1 30); do
    if docker compose exec -T postgres pg_isready -U athena &>/dev/null; then
        POSTGRES_HEALTHY=true
        break
    fi
    sleep 2
done

if [[ "$POSTGRES_HEALTHY" == true ]]; then
    log "PostgreSQL: healthy"
else
    warn "PostgreSQL: health check timed out (may still be starting)"
fi

# ============================================================================
# Step 6: Verify
# ============================================================================

step "Step 6/6: Verification"

echo ""
echo -e "${CYAN}Service Status:${NC}"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps

echo ""
echo -e "${CYAN}Tools Verification:${NC}"
docker run --rm athena/pentest-tools:latest bash -c '
    TOOLS="nmap nuclei subfinder httpx ffuf sqlmap nikto hydra gobuster wfuzz whatweb wapiti searchsploit john hashcat masscan"
    for tool in $TOOLS; do
        if command -v $tool &>/dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
'

echo ""
log "Setup complete!"
echo ""

# ============================================================================
# Summary
# ============================================================================

cat <<EOF
${CYAN}╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   🎯  ATHENA PENTEST — READY                            ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║   Gateway URL:  ${PUBLIC_URL}                           ║
║   Results:      ${RESULTS_DIR}                          ║
║   Config:       $(pwd)/.env                             ║
║                                                          ║
║   Default login: admin@pentagi.com / admin              ║
║   ⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY               ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║   USAGE                                                 ║
║   ─────                                                 ║
║   Start engagement:                                     ║
║     ./scripts/run-engagement.sh target.com client-id    ║
║                                                          ║
║   Teardown engagement:                                  ║
║     ./scripts/teardown-engagement.sh client-id          ║
║                                                          ║
║   Via Discord (with Athena skills loaded):              ║
║     "pentest target.com"                                ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║   STACK                                                 ║
║   ─────                                                 ║
║   • Athena Gateway (built from YOUR fork)               ║
║   • Docker-in-Docker (sandbox engine)                   ║
║   • PostgreSQL + pgvector (memory)                      ║
║   • 20+ pentesting tools                                ║
║   • 5 pentest skills (recon, web, network, report,      ║
║     orchestrator)                                       ║
║                                                          ║
║   Source: gitlab.com/chinomonatinotenda19/hermes-agent    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝${NC}
EOF

# Save setup completion marker
cat > .setup-complete <<EOF
{
  "setup_completed_at": "$(date -Iseconds)",
  "version": "1.0.0",
  "public_url": "${PUBLIC_URL}",
  "results_dir": "${RESULTS_DIR}"
}
EOF

log "Setup marker saved. Stack is ready for engagements."

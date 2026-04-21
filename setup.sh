#!/usr/bin/env bash
# ============================================================================
# Athena Pentest — Self-Contained Setup
#
# Pulls images from registry.gitlab.com and pulls secrets from Infisical.
# Run on any Ubuntu 24.04 server with Docker installed and `infisical` logged in.
#
# Prereqs:
#   - Docker + Docker Compose plugin
#   - External ParadeDB (or any Postgres + pgvector) reachable from this host
#   - Infisical CLI logged in (`infisical login`)
#   - .infisical.json present in this directory (`infisical init`)
#   - The Infisical environment you pass with --env contains:
#       OPENROUTER_API_KEY, HERMES_MEMORY_DATABASE_URL
#     and optionally: IMAGE_TAG, PUBLIC_URL, GATEWAY_LISTEN_IP,
#                     GATEWAY_LISTEN_PORT, CORS_ORIGINS, TZ,
#                     LANCEDB_EMBED_PROVIDER, LANCEDB_EMBED_MODEL
#
# Usage:
#   ./setup.sh                       # uses Infisical env "dev" (default)
#   ./setup.sh --env prod
#   ./setup.sh --env staging --listen-ip 0.0.0.0 --listen-port 8443
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

INFISICAL_ENV="dev"
PUBLIC_URL=""
LISTEN_IP=""
LISTEN_PORT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --env)             INFISICAL_ENV="$2"; shift 2 ;;
        --public-url)      PUBLIC_URL="$2"; shift 2 ;;
        --listen-ip)       LISTEN_IP="$2"; shift 2 ;;
        --listen-port)     LISTEN_PORT="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

# Build the infisical run prefix once — every docker compose call uses it
INFISICAL_RUN=(infisical run --env="$INFISICAL_ENV" --silent --)

# ============================================================================
# Step 1: Prerequisites
# ============================================================================

step "Step 1/5: Checking Prerequisites"

if ! command -v docker &>/dev/null; then
    err "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    log "Docker installed"
else
    log "Docker: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    err "Docker Compose plugin not found. Installing..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
    log "Docker Compose installed"
else
    log "Docker Compose: $(docker compose version --short)"
fi

if ! docker info &>/dev/null; then
    err "Docker is not running. Starting..."
    systemctl start docker
fi
log "Docker daemon: running"

if ! command -v git &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq git
fi
log "Git: available"

if ! command -v jq &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq jq
fi
log "jq: available"

if ! command -v infisical &>/dev/null; then
    err "infisical CLI not found. Install: https://infisical.com/docs/cli/overview"
    exit 1
fi
log "Infisical: $(infisical --version 2>&1 | head -1)"

if [[ ! -f .infisical.json ]]; then
    err ".infisical.json missing. Run: infisical init"
    exit 1
fi
log "Infisical project: linked"

# ============================================================================
# Step 2: Verify Required Secrets
# ============================================================================

step "Step 2/5: Verifying Infisical Secrets (env=$INFISICAL_ENV)"

REQUIRED_SECRETS=(OPENROUTER_API_KEY HERMES_MEMORY_DATABASE_URL)
MISSING=()

# `infisical secrets get` exits 0 even when the secret is missing — only the
# value is empty. So we check stdout, not exit code.
for secret in "${REQUIRED_SECRETS[@]}"; do
    val="$(infisical secrets get "$secret" --env="$INFISICAL_ENV" --silent --plain 2>/dev/null | head -1)"
    if [[ -n "$val" ]]; then
        log "  ✓ $secret"
    else
        err "  ✗ $secret (missing)"
        MISSING+=("$secret")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "Add the missing secrets in the Infisical UI for env '$INFISICAL_ENV', then re-run."
    err "  HERMES_MEMORY_DATABASE_URL — full connection URL to your ParadeDB instance"
    err "    (postgresql://user:pass@host:5432/dbname). The agent auto-creates the"
    err "    'hermes_memory' schema on first connect."
    err "  OPENROUTER_API_KEY — your OpenRouter key (used for both LLM and embeddings)"
    exit 1
fi

# Optional config secrets — fall back to flag/default if absent
get_optional() {
    local name="$1" fallback="$2"
    infisical secrets get "$name" --env="$INFISICAL_ENV" --silent --plain 2>/dev/null | head -1 || echo "$fallback"
}

[[ -z "$LISTEN_IP" ]]   && LISTEN_IP="$(get_optional GATEWAY_LISTEN_IP 127.0.0.1)"
[[ -z "$LISTEN_PORT" ]] && LISTEN_PORT="$(get_optional GATEWAY_LISTEN_PORT 8443)"
[[ -z "$PUBLIC_URL" ]]  && PUBLIC_URL="$(get_optional PUBLIC_URL "https://${LISTEN_IP}:${LISTEN_PORT}")"

IMAGE_TAG_VAL="$(get_optional IMAGE_TAG stable)"
log "Image tag: ${IMAGE_TAG_VAL}"

# ============================================================================
# Step 3: Storage
# ============================================================================

step "Step 3/5: Setting Up Storage"

RESULTS_DIR="$(get_optional PENTEST_RESULTS_DIR /opt/pentest-results)"
mkdir -p "$RESULTS_DIR"
log "Results directory: $RESULTS_DIR"

# Export non-secret config so docker compose interpolation picks it up.
# Secret values are injected by infisical run.
export PENTEST_RESULTS_DIR="$RESULTS_DIR"
export GATEWAY_LISTEN_IP="$LISTEN_IP"
export GATEWAY_LISTEN_PORT="$LISTEN_PORT"
export PUBLIC_URL
export CORS_ORIGINS="${CORS_ORIGINS:-https://localhost:${LISTEN_PORT},${PUBLIC_URL}}"

# ============================================================================
# Step 4: Pull Images
# ============================================================================

step "Step 4/5: Pulling Images from Registry"
log "Tag: ${IMAGE_TAG_VAL}"

"${INFISICAL_RUN[@]}" docker compose pull
log "Images pulled"

# ============================================================================
# Step 5: Deploy
# ============================================================================

step "Step 5/5: Deploying Stack"

"${INFISICAL_RUN[@]}" docker compose up -d
log "Stack started"

log "Waiting for gateway to come up..."
sleep 5

echo ""
echo -e "${CYAN}Service Status:${NC}"
"${INFISICAL_RUN[@]}" docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
    || "${INFISICAL_RUN[@]}" docker compose ps

echo ""
log "Setup complete!"
echo ""

cat <<EOF
${CYAN}╔══════════════════════════════════════════════════════════╗
║   ATHENA PENTEST — READY                                  ║
╠══════════════════════════════════════════════════════════╣
║   Gateway URL:  ${PUBLIC_URL}
║   Image tag:    ${IMAGE_TAG_VAL}
║   Infisical:    env=${INFISICAL_ENV}
║   Results:      ${RESULTS_DIR}
║
║   Default login: admin@pentagi.com / admin
║   ⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY
╠══════════════════════════════════════════════════════════╣
║   USAGE
║   Start engagement:
║     ./scripts/run-engagement.sh target.com client-id
║   Teardown engagement:
║     ./scripts/teardown-engagement.sh client-id
║   Subsequent compose calls (use the wrapper):
║     infisical run --env=${INFISICAL_ENV} -- docker compose ps
║     infisical run --env=${INFISICAL_ENV} -- docker compose logs -f
╚══════════════════════════════════════════════════════════╝${NC}
EOF

cat > .setup-complete <<EOF
{
  "setup_completed_at": "$(date -Iseconds)",
  "infisical_env": "${INFISICAL_ENV}",
  "image_tag": "${IMAGE_TAG_VAL}",
  "public_url": "${PUBLIC_URL}",
  "results_dir": "${RESULTS_DIR}"
}
EOF

log "Setup marker saved."

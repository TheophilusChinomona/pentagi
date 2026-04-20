#!/usr/bin/env bash
# ============================================================================
# Engagement Container Launcher — Enhanced
# Spins up an isolated pentest container for a specific engagement
# Includes audit logging, monitoring, and state tracking
#
# Usage: ./run-engagement.sh <target> [engagement-id]
# Example: ./run-engagement.sh example.com client-abc-2026
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
step() { echo -e "\n${CYAN}═══ $1 ═══${NC}\n"; }

TARGET="${1:?Usage: $0 <target> [engagement-id]}"
ENGAGEMENT_ID="${2:-engagement-$(date +%Y%m%d-%H%M%S)}"
IMAGE="athena/pentest-tools:latest"
RESULTS_DIR="/opt/pentest-results/${ENGAGEMENT_ID}"

mkdir -p "$RESULTS_DIR"

step "Pentest Engagement Launcher"
echo "  Target:     $TARGET"
echo "  Engagement: $ENGAGEMENT_ID"
echo "  Results:    $RESULTS_DIR"
echo "  Image:      $IMAGE"
echo ""

# ============================================================================
# Audit Log
# ============================================================================

AUDIT_LOG="${RESULTS_DIR}/audit.log"

audit_log() {
    echo "[$(date -Iseconds)] $1" >> "$AUDIT_LOG"
}

audit_log "ENGAGEMENT_START target=${TARGET} id=${ENGAGEMENT_ID}"

# ============================================================================
# Create Isolated Network
# ============================================================================

NETWORK_NAME="pentest-${ENGAGEMENT_ID}"

if docker network ls -q -f name="$NETWORK_NAME" | grep -q .; then
    log "Network already exists: $NETWORK_NAME"
else
    docker network create "$NETWORK_NAME" 2>/dev/null
    log "Created isolated network: $NETWORK_NAME"
    audit_log "NETWORK_CREATED name=${NETWORK_NAME}"
fi

# ============================================================================
# Launch Container
# ============================================================================

step "Launching Container"

CONTAINER_ID=$(docker run -d \
    --name "pentest-${ENGAGEMENT_ID}" \
    --network "$NETWORK_NAME" \
    --hostname "pentest-${ENGAGEMENT_ID}" \
    -v "${RESULTS_DIR}:/pentest/results" \
    -e "TARGET=${TARGET}" \
    -e "ENGAGEMENT_ID=${ENGAGEMENT_ID}" \
    -e "ENGAGEMENT_DIR=/pentest/results" \
    --memory=4g \
    --cpus=2 \
    --cap-add=NET_RAW \
    --cap-add=NET_ADMIN \
    --label "pentest.target=${TARGET}" \
    --label "pentest.engagement=${ENGAGEMENT_ID}" \
    --label "pentest.created=$(date -Iseconds)" \
    "$IMAGE" \
    sleep infinity)

log "Container started: $CONTAINER_ID"
audit_log "CONTAINER_STARTED id=${CONTAINER_ID} name=pentest-${ENGAGEMENT_ID}"

# ============================================================================
# Initialize Engagement State
# ============================================================================

cat > "${RESULTS_DIR}/engagement-state.json" <<EOF
{
  "engagement_id": "${ENGAGEMENT_ID}",
  "target": "${TARGET}",
  "container_id": "${CONTAINER_ID}",
  "network": "${NETWORK_NAME}",
  "status": "active",
  "started_at": "$(date -Iseconds)",
  "phases_completed": [],
  "current_phase": "initializing",
  "findings_count": {"critical": 0, "high": 0, "medium": 0, "low": 0}
}
EOF

log "Engagement state initialized"

# ============================================================================
# Create Directory Structure Inside Container
# ============================================================================

docker exec "$CONTAINER_ID" mkdir -p /pentest/results/{recon,web,network,api,evidence,reports}

log "Directory structure created"
audit_log "STRUCTURE_CREATED dirs=recon,web,network,api,evidence,reports"

# ============================================================================
# Output
# ============================================================================

step "Ready"

echo "Container:  $CONTAINER_ID"
echo "Network:    $NETWORK_NAME"
echo "Audit log:  $AUDIT_LOG"
echo "State:      ${RESULTS_DIR}/engagement-state.json"
echo ""
echo "To attach:"
echo "  docker exec -it pentest-${ENGAGEMENT_ID} bash"
echo ""
echo "To run a scan:"
echo "  docker exec pentest-${ENGAGEMENT_ID} nmap -sV {target}"
echo ""
echo "To monitor:"
echo "  docker logs -f pentest-${ENGAGEMENT_ID}"
echo ""
echo "To stop:"
echo "  ./scripts/teardown-engagement.sh ${ENGAGEMENT_ID}"
echo ""

audit_log "ENGAGEMENT_READY target=${TARGET} container=${CONTAINER_ID}"

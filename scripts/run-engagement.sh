#!/usr/bin/env bash
# ============================================================================
# Engagement Container Launcher
# Spins up an isolated pentest container for a specific engagement
#
# Usage: ./run-engagement.sh <target> [engagement-id]
# Example: ./run-engagement.sh example.com client-abc-2026
# ============================================================================

set -euo pipefail

TARGET="${1:?Usage: $0 <target> [engagement-id]}"
ENGAGEMENT_ID="${2:-engagement-$(date +%Y%m%d-%H%M%S)}"
IMAGE="athena/pentest-tools:latest"

# Results directory
RESULTS_DIR="/opt/pentest-results/${ENGAGEMENT_ID}"
mkdir -p "$RESULTS_DIR"

echo "============================================"
echo " Pentest Engagement Launcher"
echo "============================================"
echo " Target:     $TARGET"
echo " Engagement: $ENGAGEMENT_ID"
echo " Results:    $RESULTS_DIR"
echo " Image:      $IMAGE"
echo "============================================"

# Create isolated network for this engagement
NETWORK_NAME="pentest-${ENGAGEMENT_ID}"
docker network create "$NETWORK_NAME" 2>/dev/null || true

# Launch container
CONTAINER_ID=$(docker run -d \
    --name "pentest-${ENGAGEMENT_ID}" \
    --network "$NETWORK_NAME" \
    --hostname "pentest-${ENGAGEMENT_ID}" \
    -v "${RESULTS_DIR}:/pentest/results" \
    -e "TARGET=${TARGET}" \
    -e "ENGAGEMENT_ID=${ENGAGEMENT_ID}" \
    --memory=4g \
    --cpus=2 \
    --cap-add=NET_RAW \
    --cap-add=NET_ADMIN \
    "$IMAGE" \
    sleep infinity)

echo ""
echo "Container started: $CONTAINER_ID"
echo "Network: $NETWORK_NAME"
echo ""
echo "To attach:"
echo "  docker exec -it pentest-${ENGAGEMENT_ID} bash"
echo ""
echo "To run a scan:"
echo "  docker exec pentest-${ENGAGEMENT_ID} nmap -sV ${TARGET}"
echo ""
echo "To stop:"
echo "  docker stop pentest-${ENGAGEMENT_ID}"
echo "  docker rm pentest-${ENGAGEMENT_ID}"
echo "  docker network rm ${NETWORK_NAME}"
echo ""

# Save engagement metadata
cat > "${RESULTS_DIR}/engagement.json" <<EOF
{
  "id": "${ENGAGEMENT_ID}",
  "target": "${TARGET}",
  "container": "${CONTAINER_ID}",
  "network": "${NETWORK_NAME}",
  "image": "${IMAGE}",
  "started_at": "$(date -Iseconds)",
  "status": "active"
}
EOF

echo "Engagement metadata saved to ${RESULTS_DIR}/engagement.json"

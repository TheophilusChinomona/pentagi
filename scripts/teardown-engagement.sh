#!/usr/bin/env bash
# ============================================================================
# Engagement Teardown
# Stop and clean up a pentest engagement container
# Evidence is preserved in the results directory
#
# Usage: ./teardown-engagement.sh <engagement-id>
# ============================================================================

set -euo pipefail

ENGAGEMENT_ID="${1:?Usage: $0 <engagement-id>}"
CONTAINER_NAME="pentest-${ENGAGEMENT_ID}"
NETWORK_NAME="pentest-${ENGAGEMENT_ID}"
RESULTS_DIR="/opt/pentest-results/${ENGAGEMENT_ID}"

echo "Tearing down engagement: $ENGAGEMENT_ID"

# Stop container
if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Stopping container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
fi

# Remove container
if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Removing container..."
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Remove network
if docker network ls -q -f name="$NETWORK_NAME" | grep -q .; then
    echo "Removing network..."
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
fi

# Update engagement metadata
if [[ -f "${RESULTS_DIR}/engagement.json" ]]; then
    jq '.status = "completed" | .completed_at = now | .completed_at_str = (now | todate)' \
        "${RESULTS_DIR}/engagement.json" > "${RESULTS_DIR}/engagement.json.tmp" \
        && mv "${RESULTS_DIR}/engagement.json.tmp" "${RESULTS_DIR}/engagement.json"
    echo "Engagement metadata updated"
fi

echo ""
echo "Done. Evidence preserved at: $RESULTS_DIR"
echo ""
echo "To archive:"
echo "  tar czf ${ENGAGEMENT_ID}-evidence.tar.gz -C /opt/pentest-results ${ENGAGEMENT_ID}"

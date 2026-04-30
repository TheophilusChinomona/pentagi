#!/usr/bin/env bash
# ============================================================================
# Engagement Teardown — Enhanced
# Stop and clean up a pentest engagement container
# Evidence is preserved in the results directory
# Includes audit logging
#
# Usage: ./teardown-engagement.sh <engagement-id>
# ============================================================================

set -euo pipefail

ENGAGEMENT_ID="${1:?Usage: $0 <engagement-id>}"
CONTAINER_NAME="pentest-${ENGAGEMENT_ID}"
NETWORK_NAME="pentest-${ENGAGEMENT_ID}"
RESULTS_ROOT="${PENTEST_RESULTS_ROOT:-/pentest/results}"
RESULTS_DIR="${RESULTS_ROOT}/${ENGAGEMENT_ID}"
AUDIT_LOG="${RESULTS_DIR}/audit.log"

audit_log() {
    mkdir -p "$RESULTS_DIR"
    echo "[$(date -Iseconds)] $1" >> "$AUDIT_LOG" 2>/dev/null
}

echo "Tearing down engagement: $ENGAGEMENT_ID"
audit_log "TEARDOWN_START"

# ============================================================================
# Capture Final State
# ============================================================================

if [[ -d "$RESULTS_DIR" ]]; then
    # Count files in evidence
    EVIDENCE_COUNT=$(find "${RESULTS_DIR}/evidence" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$RESULTS_DIR" 2>/dev/null | awk '{print $1}')
    audit_log "EVIDENCE_SUMMARY files=${EVIDENCE_COUNT} size=${TOTAL_SIZE}"
    echo "Evidence: $EVIDENCE_COUNT files, $TOTAL_SIZE total"
fi

# ============================================================================
# Stop Container
# ============================================================================

if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Stopping container..."
    CONTAINER_UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
    docker stop "$CONTAINER_NAME" 2>/dev/null
    audit_log "CONTAINER_STOPPED name=${CONTAINER_NAME} started_at=${CONTAINER_UPTIME}"
    echo "Container stopped"
fi

# ============================================================================
# Remove Container
# ============================================================================

if docker ps -aq -f name="$CONTAINER_NAME" | grep -q .; then
    echo "Removing container..."
    docker rm "$CONTAINER_NAME" 2>/dev/null
    audit_log "CONTAINER_REMOVED name=${CONTAINER_NAME}"
    echo "Container removed"
fi

# ============================================================================
# Remove Network
# ============================================================================

if docker network ls -q -f name="$NETWORK_NAME" | grep -q .; then
    echo "Removing network..."
    docker network rm "$NETWORK_NAME" 2>/dev/null
    audit_log "NETWORK_REMOVED name=${NETWORK_NAME}"
    echo "Network removed"
fi

# ============================================================================
# Update Engagement State
# ============================================================================

if [[ -f "${RESULTS_DIR}/engagement-state.json" ]]; then
    if command -v jq &>/dev/null; then
        jq --arg time "$(date -Iseconds)" \
           '.status = "completed" | .completed_at = $time | .phases_completed += ["teardown"]' \
           "${RESULTS_DIR}/engagement-state.json" > "${RESULTS_DIR}/engagement-state.json.tmp" \
           && mv "${RESULTS_DIR}/engagement-state.json.tmp" "${RESULTS_DIR}/engagement-state.json"
    fi
    echo "Engagement state updated"
fi

# ============================================================================
# Archive Evidence
# ============================================================================

if [[ -d "$RESULTS_DIR" ]]; then
    ARCHIVE="${RESULTS_ROOT}/${ENGAGEMENT_ID}-evidence-$(date +%Y%m%d).tar.gz"
    echo "Archiving evidence to ${ARCHIVE}..."
    tar czf "$ARCHIVE" -C "${RESULTS_ROOT}" "$ENGAGEMENT_ID" 2>/dev/null
    audit_log "EVIDENCE_ARCHIVED archive=${ARCHIVE}"
    echo "Evidence archived: $ARCHIVE"
fi

audit_log "TEARDOWN_COMPLETE engagement=${ENGAGEMENT_ID}"

echo ""
echo "Done. Engagement $ENGAGEMENT_ID complete."
echo ""
echo "Evidence preserved at: $RESULTS_DIR"
echo "Audit log: $AUDIT_LOG"
echo ""
echo "To review findings:"
echo "  cat ${RESULTS_DIR}/findings.json | jq '.'"
echo ""
echo "To review audit trail:"
echo "  cat ${AUDIT_LOG}"
